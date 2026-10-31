# Modern rendering profile

The game draws through one rendering profile per launch: `retail`, the
stored-colour pipeline described in [rendering](README.md), or `modern`,
where Godot's lights, shadows and lit materials replace the C lighting recipe
and terrain samples ordinary per-image textures. `--rendering=modern` after
`--` selects it; `frogger/rendering/default_profile` in `project.godot` holds
the default (`retail`). `RenderingProfile` (`src/data/rendering/`) is the
value, `ViewerArguments.rendering_profile` reads the launch, `ImportedAssets`
resolves it (an unknown name falls back to retail with a warning) and every
view asks the catalog or `TextureLibrary` for it, as with the
[texture set](../assets.md#upscaled-textures). The retail look is unchanged:
no retail shader, mesh array, golden or probe expectation moved
([roadmap](../../PORTING.md#s2-modern-rendering-profile)).

## Renderer

The modern profile targets Forward+. `tools/play.sh`, `tools/play.ps1` and
`tools/launch_macos.command` pass `--rendering-method forward_plus` before the
scene path when the profile is modern; a direct launch must do the same. The
profile also runs on Compatibility (headless tests, F5 in the editor) and
then logs a warning through `AssetCatalog.note_renderer`, because shadows and
blending differ there. Every retail shader keeps its Compatibility colour
correction under `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY`; on any
other renderer `through_renderer` returns the exact sRGB decode, so opaque
unshaded surfaces (HUD-adjacent sprites, effects, the front end) show the
same bytes under Forward+ with the linear tone mapper. Translucent blends mix
in linear light there (about 0.73 where retail gives 0.5); that difference is
accepted for the spike.

## Scene lighting

`SceneLightingBuilder.from_lighting` (`src/convert/`) turns the same
`MapLighting` that lights the frog and entities in retail (ambient plus up to
three parallel slots, [model lighting](README.md#model-lighting)) into a
node-free `SceneLightingSpec`. With stored fractions `a = ambient / 4096` and
`p_i = colour_i / 4096` and `γ(x) = clamp(x, 0, 1)^2.2`:

- ambient (linear) `= γ(a)`;
- light `i` (linear) `= max(γ(a + p_i) − γ(a), 0)`, split into
  `light_energy = max channel × LAMBERT_SCALE` and the normalised colour.
  Both the ambient-only face and a fully lit face then show the retail byte;
  retail's stop at full brightness becomes saturation of the same mapping.
  Forward+ measured `LAMBERT_SCALE = 1` exact (`tools/probe_scene_lighting.gd`).
- direction: the light node's −Z is the slot direction. C lights a face when
  the stored direction and its normal agree, and the source models store
  normals pointing inward (every corner of the committed `GEN_FROG` and
  `ORG_LOG_SMALL` meshes), so that direction is the way the light travels.
- the slot with the largest luminance casts shadows: two parallel splits,
  split 0.25, maximum distance 32 (8192 game units), fade 0.8, bias 0.05,
  normal bias 1.0, blur 1.0, caster mask `SceneLightingSpec.SHADOW_CASTER_LAYER`
  ([shadows](#shadows)).

`SceneLighting` (`src/presentation/`), a child of `GameplayWorldView`, is the
only owner of light nodes: it builds the `DirectionalLight3D`s and one
`WorldEnvironment` (black background, the ambient as a flat colour at energy
1, linear tone mapping at exposure 1, every screen-space and volumetric effect
off) on `apply`, sets the `frogger_model_ambient` shader global, and clears
them with the entity visuals. Under modern `build_entities` applies the map's
lights; a scene without map lights (the sandbox, mapless builds, maps whose
records give neither direction nor ambient) applies the options screen's
ambient and parallel light instead, so lit shaders never draw black. Under
retail nothing is created. The architecture scanner keeps light and
environment nodes inside `src/presentation/`
([architecture](../architecture.md#automated-checks)). The golden is
[scene lighting](../../../tests/golden/specs/rendering.md#scene-lighting).

## Lit models

Every retail `model_*.gdshader` has a lit counterpart
`src/convert/shaders/modern/model_lit_*.gdshader` with the same blend, depth
and cull modes plus `diffuse_lambert, specular_disabled,
ambient_light_disabled`, sharing `model_lit.gdshaderinc`. No material file is
added: `ModelMeshCopy` swaps each retail shader for its lit variant (after the
linear variant for x4) and carries the texture, UV, depth-bias and projection
parameters; `ModelMeshLibrary` keeps one copy per model, texture set and
profile; runtime-built meshes take the lit shaders from the library's
profile. The shader flips the inward normals, decodes the polygon colour to
linear (`texel × linear(min(2 × colour, 1))`, or `linear(colour)` untextured),
keeps the colour-key discard and the four blends, and applies the frog's
depth-bias pull and the clip-Y projection scale only outside shadow passes
(`IN_SHADOW_PASS`), so casters keep their true shape; lighting uses view-space
positions, which the clip scale does not touch. The ambient is an emission of
`albedo × frogger_model_ambient`, not the environment ambient. Lit parts join
the shadow-caster layer.

The committed colour scale and custom ambient
([animated part lighting](gameplay-projection.md#animated-part-lighting))
reach a lit model as a `SceneTint` through two per-node instance uniforms, so
materials stay shared (flipbook parts keep per-instance copies for their cel
pose). `AnimatedModelInstance.set_source_lighting` and `set_tint` keep their
signatures: `tint_scale = γ(scale / 128)` per channel (unclamped, so the
desert crack goes above one) multiplies the albedo; a custom ambient replaces
`frogger_model_ambient` for that model through `tint_ambient`. This covers
the frog's edge fade, drowning and Volcano tints and reset ambient, the cave
fade, the diving turtle, beaver, rat, checkpoint and desert crack. Fireflies,
pickups, effect sprites, pop pieces, the tongue, the swarm, blob shadows,
CPU-lit splashes and the HUD stay unlit through the retail shaders.

## Terrain

Under modern, map terrain samples each image's own padded texture with repeat
wrapping instead of the fourteen reconstructed PC pages
([assets](../assets.md#layout)). The mesh is shared with retail: the builder
adds corner normals (`MapNormals`: clockwise front faces, flat types keep the
face normal, Gouraud types blend within 60° at shared vertices) and the sky's
tile layer in `CUSTOM0.x`; every other array is unchanged. `MapLitShaders`
binds the per-image texture through `TextureLibrary.texture_for`, so
`--texture-set=x4` draws from `images_x4/` and needs no page bake. The family
`map_lit_{opaque,average,add,subtract,add_quarter}{,_far}.gdshader` plus
`map_lit_sky.gdshader` shares `map_lit.gdshaderinc`: a polygon keeps the
retail byte wrap around its page origin (`mod(p + origin [+ animation], 256)
− origin`) and then normalises inside the padded image, `(p + padding) /
padded_size`, which lands on the texel the page held (page byte `= vram_x %
256 + left padding + p`). Across all 78 retail maps no static polygon samples
outside its padded image, every animated scroll stays inside its image, and
the five ENVMAP textures each fill a page, so repeat sampling reproduces the
page. Environment UVs drop the retail per-vertex `floor` and `mod`; varyings
are perspective-correct. A custom `light()` gives Lambert diffuse with a wrap
term for omni lights and optional Blinn specular; the albedo is the texel
times `mix(1, linear(min(2 × colour, 1)), vertex_tint)`, so the owner-tunable
`vertex_tint` runs from 0 (the stored shading ignored, only Godot's lights
shade the texture) to 1 (full baked shading); cave Gouraud terrain stays at 0
with `omni_wrap` 1 because C replaces those colours with the ramp that the
[cave light](#cave-light) now is. Opaque surfaces use alpha scissor at 0.5, translucent ones
discard; missing images show magenta. The terrain depth push, far-layer push
and projection scale are skipped in the shadow pass; far layers and
translucent surfaces never cast. Group meshes receive and cast shadows; the
sky node casts none. The reference projection, `CUSTOM0` depths and the cave
grey ramp are retail-only.

Documented divergences, pinned by the
[map UV ranges](../../../tests/golden/specs/imported-assets.md#map-uv-ranges)
golden: texture 1465 (253×253 padded to 255) repeats every 255 texels instead
of 256; on the low-detail `SWP5_WIN95` map 32 instances of texture 1456 and
on the multiplayer `VOLM` maps two instances of texture 1068 scroll out of
their image, which retail shows as the neighbouring page pixels and modern
wraps within the image; the retail page cache keys exact black page-wide
while per-image textures carry each image's own alpha. Frozen C scales map
UV bytes by the HIT-trimmed texture size where the documented contract and
the port use the in-game size
([textures](../../../archive/docs/formats/textures.md#map-texture-contract)).

## Sky

Under modern the sky samples a `Texture2DArray` of the sky-land tile images
(`MapSkyTiles`), one layer per distinct tile texture in first-seen row-major
order, with the layer index in `CUSTOM0.x`. Each tile's image-relative,
HIT-trimmed pixel is normalised into the shared 40×40 padded layer,
`(pixel + 4) / 40`, so sky levels load no page set and `--texture-set=x4`
draws 160×160 layers. The tiles stay in one unshaded surface in source
row-major order with the retail far push, sky colour, drift and camera
placement; a missing or differently sized tile draws as a magenta layer with
a diagnostic. The golden is
[modern map UVs](../../../tests/golden/specs/rendering.md#modern-map-uvs).

## Water

Environment-mapped water surfaces (ENVMAP, the layer-2 far surfaces) stay lit
terrain but read as a partial reflection: `reflection_emission` moves that
share of the surface colour from albedo into emission (`ALBEDO = shown × (1 −
r)`, `EMISSION = shown × r`), so the surface still darkens in shadow without
going black, and a Blinn highlight from the scene lights (`specular_strength`,
`shininess`) sits on top. `MapMesh.Instance` gives every ENVMAP surface
`WATER_REFLECTION` 0.35, `WATER_SPECULAR` 0.2 and `WATER_SHININESS` 512, and
`set_water_look(reflection, specular, shininess)` retunes them for the owner.
Godot's light colour already carries π, so the highlight peaks at π × strength
× light energy and the exponent sets only its size; on a flat water plane the
half-vector moves by about half the view angle per pixel, so exponents of
64–256 spread the highlight over a large part of the frame (SUB1 at 0.5/64
was about 16% near-white), while 512 gives a compact glint. No
energy-conserving factor is applied, which keeps brightness and size
independent. The MAX_OT riverbed stays plain lit terrain; retail materials
carry none of these uniforms.

## Cave light

A cave map (`MapSceneData.cave_enabled`) is lit by one `OmniLight3D` instead
of the C grey ramp. Each drawn frame `GameplayWorldView` places the light
`CaveLightShape.HEIGHT` (0.5) above the interpolated frog origin with the
squared radii interpolated between the previous and current entity
environments, so croak swells and the decay move smoothly.
`SceneLighting.set_cave_light` creates the light once (attenuation exponent 0,
no shadow, no specular); the first call switches the scene to cave mode: the
directional lights go, the environment ambient energy drops to `CAVE_AMBIENT`
(0.02), the `frogger_model_ambient` global is scaled the same way and the
background stays black; `clear_cave_light` and `clear` restore the applied
spec. Retail is unchanged.

With attenuation 0 Godot weights an omni light by `(1 − (d/R)^4)^2` inside
its range, measured on Forward+ within 8-bit quantisation, and the terrain's
`LIGHT_COLOR / PI` equals the light energy. The retail ramp multiplies the
texel by `min(2 × grey / 255, 1)`, falling linearly in squared distance from
the minimum to the maximum radius. `CaveLightShape` fits the light to that
ramp by area-weighted least squares over 512 rings, in two modes chosen with
`CaveLightShape.DEFAULT_MODE`:

- `EXACT_EDGE` (default): the range is the ramp's edge `sqrt(max_r2) / 256`,
  so darkness begins where C's does; the fitted energy is about 0.91 for
  radii up to four squares and about 1.3 from eight squares up, brighter than
  retail near the frog and darker toward the edge.
- `FITTED_RANGE`: range scale and energy fitted together, about 1.04× the edge
  at energy 0.88 for small radii and 1.2–1.28× at about 1.17 for large ones;
  closer inside, but dim light leaks up to a quarter of the radius past the C
  edge, and the fit costs about 1.8 ms per radius change.

The fit targets the retail factor directly, not in linear light, so falling
edges read brighter than retail; the owner judges the mode, the 0.5 light
height and the near-black ambient by eye on CAV1, CAV3 and CAV4 against the
retail launch. Lit entity models on cave maps take their fade from the light
instead of the committed cave colour scale (a scale counts as the fade alone
when `colour_scaled` is set and the entity neither opts out of screen fades
nor multiplies script colours nor is hidden); fireflies and pickups are
sprites and keep the committed fade, as does everything outside caves. The
golden is [cave light](../../../tests/golden/specs/rendering.md#cave-light).

## Map viewer

Under modern the map viewer lights each map like gameplay: a `SceneLighting`
child in its own world applies the map's lights (or the options lights when
the map has none) and owns the environment, and a cave map gets the cave
light at the static start the retail ramp uses with the initial radii. The
map-slice preset keeps its camera pose, but the reference group budget,
frozen water and integer projection are retail-only. Captures record
`rendering_profile` in their metadata so comparison tools can refuse a modern
capture, and `modern_texture_issues()` reports any textured material that
does not bind its image's own padded texture into the capture diagnostics.

## Shadows

Real shadows come from the brightest directional light with the values above,
kept after the S2e check of ORG1, SUB1, JUN1 and VOL1 at 640x480: frames with
and without shadows showed no acne on lit surfaces and no gap between casters
and their shadows. `--shadows=off` after `--` (project setting
`frogger/rendering/shadows`, default `on`) builds the scene lights without a
caster so the owner can compare; `ViewerArguments.shadows` reads it and
`GameplayWorldView.real_shadows` passes it to `SceneLightingBuilder.from_lighting`.

The retail blob shadows (the frog's ground shadow and the Desert falling-rock
and tumbleweed quads, [effects](effects.md#frog-effects-p11b)) would draw
beside the real shadows, so under modern they follow
`frogger/rendering/effect_shadows`: `off` (default) leaves them out, `retail`
keeps them, and `--effect-shadows=retail|off` overrides it for one launch.
`ShadowEffectPolicy` (`src/convert/effects/`) decides from the profile and the
setting; `GameplayWorldView.shadow_requests` returns no requests when it says
no, so nothing reaches `FrogShadowView`. Retail draws them under every
setting and the shadow colours golden is unchanged. The sandbox's zone faces
are unshaded, so real shadows have no surface to fall on there.

## Front end

The level-select stack, the options page, the name-entry page and the
high-score pages draw their 3D models through the lit shaders. `StackLighting`
(`src/convert/`) turns the stack's ambient and three parallel lights
(`StackLayout`, SELECT.C) into one `MapLighting`, which both the retail box
materials' source lighting and `SceneLightingBuilder.from_lighting` read, so
the two profiles light the stack from one record. `LevelStackView` adds a
`SceneLighting` to the stack's world without shadows and owns that world's
environment, keeping the black background or the high-score canvas checker
(`BG_CANVAS`). Box materials are the lit variants of the retail ones; a row's
tint (glow, light or dark, `StackSelector`) reaches its box as the `SceneTint`
of the grey scale tint/128 on the box's instance uniforms; the spinning box's
level picture is its own child node with the neutral tint. The gold-frog
quads stay unlit. The options page, the main menu's table, the name-entry
page and the high-score table light their models with the options viewport's
lights without shadows: the options page through `MenuWaterView.light_scene`,
a `WaterModelSet` (hence `HighScoreSceneView`) through its own `SceneLighting`
after making the enclosing water view give up its environment
(`release_environment`), so each world has one environment. The volume
models' glow still reaches them as custom ambient. The menu water, title
sprites, reflections, splashes and the frog's jump shadow keep the retail
shaders; the water reads lighter under Forward+ through the linear-light
blend. Every front-end light is cleared when its view leaves the tree and
applied again when it returns.

## Sandbox and viewers

The sandbox lights its frog and entities through `GameplayWorldView`'s
options-light fallback; its zone faces stay unshaded `terrain_debug` tints.
The model viewer shows lit models under a `SceneLighting` holding the options
lights without shadows, in front of its grey backdrop; retail still shows each
polygon's stored colour. The camera-zone viewer lights its map from the light
records like the map viewer (options lights when the map has none, cave light
at the static start on cave maps); its probe and markers stay unshaded. The
terrain viewer takes the catalog's profile and follows
`TerrainCaptureStages.entity_lighting`: a scenario whose contract includes
entity lighting draws under the map's lights, any other under a flat ambient
with no lights, so terrain and entities show their stored colours as retail
draws unlit entities. Map-viewer scenario runs inherit its lighting.

## Verification

Verification is by eye and by windowed tools, because the headless
suites never compile shaders: `tools/probe_model_shader.gd` under retail,
`tools/probe_scene_lighting.gd` under Forward+, and captures with
`--rendering modern` that fail on any `SHADER ERROR`
([testing](../testing/README.md#tools-and-visual-verification)).
