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
  normal bias 1.0, blur 1.0, caster mask `SceneLightingSpec.SHADOW_CASTER_LAYER`.
  These are starting values, tuned by eye in S2e.

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
atlas slot in `CUSTOM0.x`; every other array is unchanged. `MapLitShaders`
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
times the linearised doubled vertex colour, scaled by the owner-tunable
`vertex_tint`. Opaque surfaces use alpha scissor at 0.5, translucent ones
discard; missing images show magenta. The terrain depth push, far-layer push
and projection scale are skipped in the shadow pass; far layers and
translucent surfaces never cast. Group meshes receive and cast shadows; the
sky node casts none. The reference projection, `CUSTOM0` depths and the cave
grey ramp are retail-only.

Documented divergences: texture 1465 (253×253 padded to 255) repeats every
255 texels instead of 256; on the low-detail `SWP5_WIN95` map texture 1456's
scroll leaves its image, which retail shows as the neighbouring page pixels
and modern wraps within the image; the retail page cache keys exact black
page-wide while per-image textures carry each image's own alpha.

## Limits after S2c

Cave Gouraud terrain draws black (`vertex_tint` 0, `omni_wrap` 1) and cave
entities keep the committed fade until S2d's omni light; the sky still samples
the baked atlas, so sky levels still load their page set; water is lit like
terrain; the front end, sandbox effects, viewers and shadow constants are
S2e. Verification is by eye and by windowed tools, because the headless
suites never compile shaders: `tools/probe_model_shader.gd` under retail,
`tools/probe_scene_lighting.gd` under Forward+, and captures with
`--rendering modern` that fail on any `SHADER ERROR`
([testing](../testing/README.md#tools-and-visual-verification)).
