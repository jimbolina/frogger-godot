# Lighting and materials

The game draws through Godot's Forward+ renderer with scene lights, real
shadows and lit materials: the map's light records become directional lights
and an ambient, models and terrain are lit per pixel, caves are lit by an
omni light at the frog, and terrain samples ordinary per-image textures. This
pipeline replaced the ported C lighting recipe and the texture-page sampling
in S2 ([roadmap](../../PORTING.md#s2-modern-rendering-profile)); the C recipe
survives only as `MapLighting.shade`, which lights sprites on the CPU, and in
the goldens that pin it. Byte-for-byte colour matching with the retail game
is not a goal; the mappings below keep its intent.

## Renderer

`project.godot` sets `renderer/rendering_method="forward_plus"` (Metal on
Apple Silicon, Vulkan or Direct3D 12 on Windows, Vulkan on Linux). The
headless suites run on the dummy renderer, which builds node trees but never
compiles shaders, so shaders are checked by windowed probes and captures
([verification](#verification)). On any other renderer the game still runs
and `AssetCatalog.note_renderer` logs "rendering on <method>; the game
targets forward_plus, shadows and lighting may differ"; the screens push the
catalog's warnings to the log. Unshaded surfaces decode their stored colours
to linear light and the tone mapper is linear, so opaque sprites show their
stored bytes; translucent blends mix in linear light (about 0.73 where the
original mixed stored values to 0.5), a known and accepted divergence.

## Scene lighting

`SceneLightingBuilder.from_lighting` (`src/rendering/`) turns a `MapLighting`
(the C viewport's ambient plus up to three parallel slots, reduced from the
map's light records by `MapLighting.configure`, [sprite lighting](README.md#sprite-lighting))
into a node-free `SceneLightingSpec`. With stored fractions `a = ambient / 4096` and
`p_i = colour_i / 4096` and `γ(x) = clamp(x, 0, 1)^2.2`:

- ambient (linear) `= γ(a)`;
- light `i` (linear) `= max(γ(a + p_i) − γ(a), 0)`, split into
  `light_energy = max channel × LAMBERT_SCALE` and the normalised colour.
  Both the ambient-only face and a fully lit face then show the byte the C
  recipe gave; its stop at full brightness becomes saturation of the same
  mapping.
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
them with the entity visuals. `build_entities` applies the map's
lights; a scene without map lights (the sandbox, mapless builds, maps whose
records give neither direction nor ambient) applies the options screen's
ambient and parallel light instead, so lit shaders never draw black. The
architecture scanner keeps light and
environment nodes inside `src/presentation/`
([architecture](../architecture.md#automated-checks)). The golden is
[scene lighting](../../../tests/golden/specs/rendering.md#scene-lighting).

## Model shaders

Models, sprites and effects draw through two families of thin shader files
under `src/rendering/shaders/`, each sharing one include and named by
`ModelShaders.shader_path`. Both keep the original colour rules: a textured
pixel is the texel times twice the polygon colour, stopping at full
brightness; an untextured pixel is the polygon colour; texels with alpha
under 0.5 are discarded; translucent polygons mix in one of four ways
(average 0.5, add, subtract, quarter add) and do not write depth;
`depth_bias` pulls depth toward the camera in game units without moving the
polygon on screen ([depth ordering](README.md#depth-ordering)) and
`projection_scale` applies the clip-Y projection scale.

The lit family, `model_{textured|flat}_{opaque|average|add|subtract|add_quarter}[_linear][_two_sided].gdshader`
(30 files, `model.gdshaderinc`), draws every model mesh; the committed
materials under `assets/materials/model/` name these files by path and the
importer writes them through the same `ModelShaders`. Godot's lights shade it
(`diffuse_lambert, specular_disabled, ambient_light_disabled`): the texture
is read through `source_color`, the polygon colour is decoded to linear
(`texel × linear(min(2 × colour, 1))`, or `linear(colour)` untextured), the
inward source normals are flipped, the scene ambient arrives as an emission
of `albedo × frogger_model_ambient`, and the depth bias and projection scale
are skipped in shadow passes (`IN_SHADOW_PASS`) so casters keep their true
shape; lighting uses view-space positions, which the clip scale does not
touch. `ModelMeshCopy` gives a view its own material copies (swapping in the
`_linear` variants for the x4 set) and lit parts join the shadow-caster layer.

The committed colour scale and custom ambient
([animated part lighting](gameplay-projection.md#animated-part-lighting))
reach a lit model as a `SceneTint` through two per-node instance uniforms, so
materials stay shared (flipbook parts keep per-instance copies for their cel
pose). `AnimatedModelInstance.set_source_lighting` and `set_tint` both write
it: `tint_scale = γ(scale / 128)` per channel (unclamped, so the desert crack
goes above one) multiplies the albedo; a custom ambient replaces
`frogger_model_ambient` for that model through `tint_ambient`. This covers
the frog's edge fade, drowning and Volcano tints and reset ambient, the
diving turtle, beaver, rat, checkpoint and desert crack.

The unlit family, `model_unlit_{textured|flat}_{blend}[_linear]_two_sided.gdshader`
(15 files, `model_unlit.gdshaderinc`, `unshaded`, all two-sided because no
sprite is culled), draws what was lit on the CPU by `MapLighting.shade` or
not at all: effect sprites, particles, splashes, shadows, the pop ring and
hop trail, pop pieces, fireflies and pickups, the swarm, the tongue, the
front-end water and the gold-frog quads. It shows the stored result decoded
to linear light. Views that need a variant edit the unlit text from
`ModelShaders.shader_code`: effect sprites and pop pieces drawn in front add
`depth_test_disabled`, the menu water a fixed `background_depth`.
`tools/probe_model_morph.gd` checks that cel-shader geometry matches native
blend shapes through both families.

## Terrain

Map terrain samples each image's own padded texture with repeat wrapping
([assets](../assets.md#layout)); the original's fourteen reconstructed VRAM
pages are format knowledge in the archive (`VramPages`). `MapMeshBuilder`
adds corner normals (`MapNormals`: clockwise front faces, flat types keep the
face normal, Gouraud types blend within 60° at shared vertices) and writes the
water rank and the sky tile layer in `UV2`. `MapShaders` binds the per-image
texture through `TextureLibrary.texture_for`, so `--texture-set=x4` draws
from `images_x4/`. The family
`map_{opaque,average,add,subtract,add_quarter}{,_far}.gdshader` plus
`map_sky.gdshader` shares `map.gdshaderinc`: a polygon keeps the
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
sky node casts none. The frozen `map_slice` reference projection and the
cave grey ramp are retired with the retail pipeline
([archive](../../../archive/docs/formats/maps.md#camera-and-reference-captures)).

Documented divergences, pinned by the
[map UV ranges](../../../tests/golden/specs/imported-assets.md#map-uv-ranges)
golden: texture 1465 (253×253 padded to 255) repeats every 255 texels instead
of 256; on the low-detail `SWP5_WIN95` map 32 instances of texture 1456 and
on the multiplayer `VOLM` maps two instances of texture 1068 scroll out of
their image, which the original showed as the neighbouring page pixels and
the port wraps within the image; the original keyed exact black page-wide
while per-image textures carry each image's own alpha. Frozen C scales map
UV bytes by the HIT-trimmed texture size where the documented contract and
the port use the in-game size
([textures](../../../archive/docs/formats/textures.md#map-texture-contract)).

## Sky

The sky samples a `Texture2DArray` of the sky-land tile images
(`MapSkyTiles`), one layer per distinct tile texture in first-seen row-major
order, with the layer index in `UV2.x`. Each tile's image-relative,
HIT-trimmed pixel is normalised into the shared 40×40 padded layer,
`(pixel + 4) / 40`, so sky levels load no page set and `--texture-set=x4`
draws 160×160 layers. The tiles stay in one unshaded surface in source
row-major order with the original's far push, sky colour, drift and camera
placement; a missing or differently sized tile draws as a magenta layer with
a diagnostic. The golden is
[map UVs](../../../tests/golden/specs/rendering.md#map-uvs).

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
independent. The MAX_OT riverbed stays plain lit terrain.

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
spec.

With attenuation 0 Godot weights an omni light by `(1 − (d/R)^4)^2` inside
its range, measured on Forward+ within 8-bit quantisation, and the terrain's
`LIGHT_COLOR / PI` equals the light energy. The C ramp multiplies the
texel by `min(2 × grey / 255, 1)`, falling linearly in squared distance from
the minimum to the maximum radius. `CaveLightShape` fits the light to that
ramp by area-weighted least squares over 512 rings, in two modes chosen with
`CaveLightShape.DEFAULT_MODE`:

- `EXACT_EDGE` (default): the range is the ramp's edge `sqrt(max_r2) / 256`,
  so darkness begins where C's does; the fitted energy is about 0.91 for
  radii up to four squares and about 1.3 from eight squares up, brighter than
  the C ramp near the frog and darker toward the edge.
- `FITTED_RANGE`: range scale and energy fitted together, about 1.04× the edge
  at energy 0.88 for small radii and 1.2–1.28× at about 1.17 for large ones;
  closer inside, but dim light leaks up to a quarter of the radius past the C
  edge, and the fit costs about 1.8 ms per radius change.

The fit targets the C factor directly, not in linear light, so falling edges
read brighter than the ramp did; the owner judges the mode, the 0.5 light
height and the near-black ambient by eye on CAV1, CAV3 and CAV4. Lit entity models on cave maps take their fade from the light
instead of the committed cave colour scale (a scale counts as the fade alone
when `colour_scaled` is set and the entity neither opts out of screen fades
nor multiplies script colours nor is hidden); fireflies and pickups are
sprites and keep the committed fade, as does everything outside caves. The
golden is [cave light](../../../tests/golden/specs/rendering.md#cave-light).

## Map viewer

The map viewer lights each map like gameplay: a `SceneLighting` child in its
own world applies the map's lights (or the options lights when the map has
none) and owns the environment, and a cave map gets the cave light at the
map midpoint with the initial radii. It has one camera, the map's default
offsets around the bounds midpoint at H=256, plus custom poses, and draws
every nonempty visible group with water on; the frozen `map_slice` preset,
its group budget and integer projection and the capture-mask comparison are
retired. Captures still write a PNG and metadata JSON outside the repository.

## Shadows

Real shadows come from the brightest directional light with the values above,
kept after the S2e check of ORG1, SUB1, JUN1 and VOL1 at 640x480: frames with
and without shadows showed no acne on lit surfaces and no gap between casters
and their shadows. `--shadows=off` after `--` (project setting
`frogger/rendering/shadows`, default `on`) builds the scene lights without a
caster so the owner can compare; `ViewerArguments.shadows` reads it and
`GameplayWorldView.real_shadows` passes it to `SceneLightingBuilder.from_lighting`.

The original's blob shadows (the frog's ground shadow and the Desert
falling-rock and tumbleweed quads, [effects](effects.md#frog-effects-p11b))
would draw beside the real shadows, so they follow
`frogger/rendering/effect_shadows`: `off` (default) leaves them out, `retail`
keeps them, and `--effect-shadows=retail|off` overrides it for one launch.
`ShadowEffectPolicy` (`src/rendering/effects/`) decides from the setting;
`GameplayWorldView.shadow_requests` returns no requests when it says no, so
nothing reaches `FrogShadowView`. The shadow colours golden still pins the
effect's geometry and colours. The sandbox's zone faces
are unshaded, so real shadows have no surface to fall on there.

## Front end

The level-select stack, the options page, the name-entry page and the
high-score pages draw their 3D models through the lit shaders. `StackLighting`
(`src/rendering/`) turns the stack's ambient and three parallel lights
(`StackLayout`, SELECT.C) into one `MapLighting` for
`SceneLightingBuilder.from_lighting`. `LevelStackView` adds a
`SceneLighting` to the stack's world without shadows and owns that world's
environment, keeping the black background or the high-score canvas checker
(`BG_CANVAS`). Box materials are lit; a row's
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
sprites, reflections, splashes and the frog's jump shadow draw through the
unlit family; the water reads lighter than the original through the
linear-light blend. Every front-end light is cleared when its view leaves the tree and
applied again when it returns.

## Sandbox and viewers

The sandbox lights its frog and entities through `GameplayWorldView`'s
options-light fallback; its zone faces stay unshaded `terrain_debug` tints.
The model viewer shows lit models under a `SceneLighting` holding the options
lights without shadows, in front of its grey backdrop. The camera-zone viewer lights its map from the light
records like the map viewer (options lights when the map has none, cave light
at the static start on cave maps); its probe and markers stay unshaded. The
terrain viewer follows `TerrainCaptureStages.entity_lighting`: a scenario
whose contract includes entity lighting draws under the map's lights, any
other under a flat ambient with no lights, so terrain and entities show their
stored colours as the original drew unlit entities. Map-viewer scenario runs inherit its lighting.

## Look choices

These are the owner's tunables left open after S2. Each has a default in
place; change it, play the named levels against your memory of the original,
and keep what reads best. None affects gameplay.

| Choice | What it is | Default and where | Look at |
|---|---|---|---|
| Cave light mode | Godot's point light cannot match the original's linear grey ramp everywhere. `EXACT_EDGE` keeps darkness starting at the ramp's radius (brighter near the frog, darker toward the edge); `FITTED_RANGE` fits range and energy together (closer inside, dim light leaking up to a quarter of the radius past the edge). | `CaveLightShape.DEFAULT_MODE = EXACT_EDGE`; the light's lift above the frog `CaveLightShape.HEIGHT` (0.5) and the cave ambient `CAVE_AMBIENT` (0.02) sit beside it ([cave light](#cave-light)) | CAV1, CAV3, CAV4: the darkness boundary, the brightness around the frog, the croak swell |
| Water glint | Water keeps part of its colour as reflected light so it never goes black in shadow, plus a specular highlight from the sun. | `MapMesh.Instance.WATER_REFLECTION` 0.35, `WATER_SPECULAR` 0.2, `WATER_SHININESS` 512; `set_water_look(reflection, specular, shininess)` at run time ([water](#water)) | SUB1, SWP1: a compact glint, not a white wash (0.5/0.5/64 washed a quarter of SUB1) |
| Blob shadows | The original's frog shadow quad and the Desert rock and tumbleweed shadow squares, which doubled up with the real shadows. | Off: `frogger/rendering/effect_shadows="off"` in `project.godot`; `--effect-shadows=retail` after `--` shows both for one launch ([shadows](#shadows)) | ORG1, DES1: whether the real shadow is enough of a landing cue |
| Real shadows | The directional light's shadow and its constants. | On: `frogger/rendering/shadows="on"`; `--shadows=off` for one launch; splits, distance, bias and blur are the fields of `SceneLightingSpec` ([scene lighting](#scene-lighting)) | ORG1, JUN1, VOL1: acne, gaps under casters, shimmer while the camera follows |
| Tone mapper | Converts the linear scene for the screen. Linear puts stored sprite and HUD colours on screen exactly; AgX or Filmic compress highlights and desaturate, shifting every stored colour. | `TONE_MAPPER_LINEAR`, exposure 1, set by `SceneLighting.apply` | Lava and the water glint if highlights read too harsh |
| Baked terrain shading | The maps carry per-vertex shading from the original artists, which now doubles with real light on slopes. | `vertex_tint` 1.0 (full), 0 ignores it; `MapMesh.Instance.set_vertex_tint` ([terrain](#terrain)); cave terrain stays at 0 | DES1, VOL1 slopes: dark bands under real light |
| Texture filtering | Retail images sample nearest without mipmaps and shimmer at distance; mipmaps on `images/` and `fix_alpha_border` on `images_x4` would change the pinned import policy (`test_asset_import_settings`). | Unchanged; an owner decision recorded in the [roadmap](../../PORTING.md#needed-from-the-owner) | Far terrain under `--texture-set=x4` and retail |

## Verification

The headless suites never compile shaders, so verification is by eye and by
windowed tools: `tools/probe_scene_lighting.gd` measures the energy mapping
on Forward+ (`LAMBERT_SCALE` is exact at 1), `tools/probe_model_morph.gd`
checks cel geometry through both shader families, and the capture tools fail
on any `SHADER ERROR` or a single-colour map capture
([testing](../testing/README.md#tools-and-visual-verification)). The goldens
pin the node-free mappings: [scene lighting](../../../tests/golden/specs/rendering.md#scene-lighting),
[cave light](../../../tests/golden/specs/rendering.md#cave-light),
[map UVs](../../../tests/golden/specs/rendering.md#map-uvs) and
[map UV ranges](../../../tests/golden/specs/imported-assets.md#map-uv-ranges).
