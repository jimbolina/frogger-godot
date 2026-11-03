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
stored bytes; bloom adds only light above 1.0, so it leaves them alone.
Translucent blends mix in linear light (about 0.73 where the
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
- the slot with the largest luminance casts shadows: fade 0.8, blur 1.0 and
  caster mask `SceneLightingSpec.SHADOW_CASTER_LAYER` from the spec; splits,
  split position, distance and biases from the graphics settings (defaults two
  parallel splits, split 0.25, maximum distance 32 (8192 game units), bias
  0.05, normal bias 1.0) ([shadows](#shadows)).

`SceneLighting` (`src/presentation/`), a child of `GameplayWorldView`, is the
only owner of light nodes: it builds the `DirectionalLight3D`s and one
`WorldEnvironment` (black background, the ambient as a flat colour at energy
1, fog, volumetric fog, SSIL, SSR and SDFGI off) on `apply`, sets the
`frogger_model_ambient` shader global, and clears them with the entity
visuals. Bloom, tone mapping, SSAO and the shadow constants come from the live
`GraphicsSettings` behind `GraphicsProfile.current()` (`src/presentation/graphics/`,
mapped to engine values by `GraphicsMapping`). Bloom is Godot glow in additive
blend with `glow_bloom` 0, HDR threshold 1.0 and HDR scale 2.0, so stored
colours of 1.0 or less are unchanged and only brighter values (water glints,
unclamped tints, stacked additive sprites) halo. The real-shadow switch is
`casts_shadow and spec.shadows and real_shadows`, so `--shadows=off` stays a
per-launch ceiling. While in the tree, a profile change updates these
properties on the existing environment and lights in place and never reapplies
the spec, so a background set by the owning view and cave mode are kept. `build_entities` applies the map's
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
`_linear` variants for each upscaled texture-pack or lettering image) and lit
parts join the shadow-caster layer.

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
texture through `TextureLibrary.texture_for`, so a
[texture pack](../assets.md#texture-packs) draws its own images; an upscaled
image samples linearly with mipmaps whatever the instance's filter switch
says. The family
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
`(pixel + 4) / 40`, so sky levels load no page set and a texture pack's tiles
draw at their own scale: the layers take the largest tile scale (160×160 for a
4x tile), a smaller tile is enlarged by repeating pixels, and an upscaled sky
always samples linearly with mipmaps. The tiles stay in one unshaded surface in source
row-major order with the original's far push, sky colour, drift and camera
placement; a missing or differently sized tile draws as a magenta layer with
a diagnostic; so does one whose texture is no whole multiple of its padded size. The golden is
[map UVs](../../../tests/golden/specs/rendering.md#map-uvs).

## Water

Environment-mapped water surfaces (ENVMAP, the layer-2 far surfaces) stay lit
terrain but read as a partial reflection: `reflection_emission` moves that
share of the surface colour from albedo into emission (`ALBEDO = shown × (1 −
r)`, `EMISSION = shown × r`), so the surface still darkens in shadow without
going black, and a Blinn highlight from the scene lights (`specular_strength`,
`shininess`) sits on top. `MapMesh.Instance` gives every ENVMAP surface
`WATER_REFLECTION` 0.35, `WATER_SPECULAR` 0.2 and `WATER_SHININESS` 512, and
`set_water_look(reflection, specular, shininess)` retunes them; the world view
and the map viewer pass the profile's `water_reflection`, `water_specular` and
`water_shininess` and `vertex_tint` after building the map and on every
change.
Godot's light colour already carries π, so the highlight peaks at π × strength
× light energy and the exponent sets only its size; on a flat water plane the
half-vector moves by about half the view angle per pixel, so exponents of
64–256 spread the highlight over a large part of the frame (SUB1 at 0.5/64
was about 16% near-white), while 512 gives a compact glint. No
energy-conserving factor is applied, which keeps brightness and size
independent. The MAX_OT riverbed stays plain lit terrain.

## Lava

Lava and hot rock glow: map surfaces drawing an image listed in the
hand-authored `assets/rendering/emissive_images.tres`
([assets](../assets.md#layout)) add emission on top of their lit colour.
`EmissiveSurfaces.resolve` turns the table's image names into texture ids
through FrogLord's image names for `MapSceneData.emissive`; an unknown name
becomes a scene diagnostic. `MapMesh.Instance` sets `emission_strength`
(the entry's strength times the scale) and `emission_colour` on every
material it configures with such an image, so each frame of an animated
track glows by its own image. The shader adds `texel × colour × strength`
(the vertex colour on untextured surfaces, a quarter on add-quarter ones),
independent of the baked vertex shading and the lights, so lava in baked
shadow still glows; a missing image still shows plain magenta.
`set_emission_scale` takes the profile's `lava_emission`, which the world view
and the map viewer pass after building the map and on every change.

| Family | Images | Strength | Colour |
|---|---|---|---|
| Molten lava | `vol_lava2/3/5/5a`, `vol_lavacent`, `vol_lavacent2`, `vol_lavani1`–`9` | 1.0 | (1, 0.6, 0.4) |
| Lava edges | `vol_lavaedge`, `vol_lava6`, `vol_lava7` | 1.0 | (1, 0.6, 0.4) |
| Cracked hot rock | `vol_hotrocka/b/c1`–`6`, `vol_hhotrock1` | 1.8 | (1, 0.5, 0.3) |
| Plain hot rock | `vol_hotrock1`, `vol_hotrock3` | 0.5 | (1, 0.5, 0.3) |

The red channel of bright molten texels passes the bloom threshold, so lava
blooms softly red-orange onto nearby walls; the cracked rock's dark stone
emits almost nothing, so only its cracks glow. Every family is drawn on
VOL1, VOL2 or VOL3.

Molten lava and its edges (`light` set, energy 1.0 and 0.6) also light their
surroundings; hot rock does not. `EmissiveClusters.build` takes the textured
faces of visible groups whose image, or any frame of their animated track,
casts light, and bins their area-weighted centroids into 4-square horizontal
cells. Cells with less than one square of glowing surface are dropped. Each
remaining cell gives a light one square above its centroid, with a range of
1.5 times the cell's half-diagonal (about 4.2 squares), the area-weighted
entry colour and an energy of `ENERGY` (0.6) times the area-weighted light
energy times the share of the cell covered. At most 24 are kept, largest
first. VOL1 gets 22, VOL2 24 (capped) and VOL3 16. UV scrolling does not move
them.

`SceneLighting.set_emissive_lights` places them in an `EmissiveLightSet` of
shadowless, specular-free `OmniLight3D`s with attenuation 0.25, fading out
between 40 and 50 squares from the camera. They show while the profile's
`lava_lights` is set, and their energy is scaled by `lava_emission`, so
dimming the lava dims its light. A profile change updates the same lights.
They ignore cave mode, since no cave map has glowing images. The world view
computes the clusters when it builds the map and applies them each time it
lights the scene, after an entity rebuild has cleared it. The map viewer does
the same.

Each light also brightens the lava under it, so molten strength dropped from
1.2 to 1.0 when the lights arrived. That keeps the lava's overall brightness
close to its look without lights. The frame-time difference on VOL1–VOL3 was
within run-to-run noise in the map-viewer benchmark.

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
`CaveLightShape.DEFAULT_MODE`, which is the default of the profile's
`cave_light_mode` that the world view and map viewer pass:

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

## Glow

Pickup glows (bonus flies, fat fire flies) and gold-frog glows draw a soft
halo instead of the retail grey mask 1727, whose image now sets only the
quad's size; position, pulse, colour and depth bias are unchanged
([effects](effects.md)). `GlowHaloMaterial` (`glow_halo.gdshader`) is unlit
and additive without depth writes, with the unlit sprites' depth bias and
projection lines; its brightness is
`to_linear(min(2 × colour, 1)) × (1 − r)^3 × halo_strength`, `r` being the
distance from the centre in half-quad units, so the core exceeds the bloom
threshold (inside about a fifth of the radius at the default strength 2)
and blooms while the rim stays soft.

Each drawn glow also gives a `GlowLightSpec.Point` (`src/rendering/effects/`):
its centre, the halo colour, a range of `RANGE_SQUARES` (1.5 squares) and an
energy of `ENERGY` times the pulse magnitude over its peak, so the light
pulses with the halo; `glow_light_energy` scales it. `SceneLighting.place_glow_lights` keeps the 16 nearest
the camera (stable on ties) and places them in a `GlowLightPool` of
shadowless, specular-free `OmniLight3D`s (attenuation 1) that are reused and
hidden, never freed per frame. In cave mode the glow lights stay hidden unless
`glow_lights_in_caves` is set, because cave terrain would lose its darkness;
the halos still draw.

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
are lit terrain, so real shadows fall on them.

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

The sandbox lights its frog, entities and zone faces through
`GameplayWorldView`'s options-light fallback. The zone faces draw through the
opaque terrain shader (`MapShaders`), coloured per vertex with up-facing
normals, and join the shadow-caster layer, so they take shadows and glow lights
like map terrain.
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
| Cave light mode | Godot's point light cannot match the original's linear grey ramp everywhere. `EXACT_EDGE` keeps darkness starting at the ramp's radius (brighter near the frog, darker toward the edge); `FITTED_RANGE` fits range and energy together (closer inside, dim light leaking up to a quarter of the radius past the edge). | Settings `cave_light_mode` `EXACT_EDGE`, matching `CaveLightShape.DEFAULT_MODE`; the light's lift above the frog `CaveLightShape.HEIGHT` (0.5) and the cave ambient `CAVE_AMBIENT` (0.02) sit beside it ([cave light](#cave-light)) | CAV1, CAV3, CAV4: the darkness boundary, the brightness around the frog, the croak swell |
| Water glint | Water keeps part of its colour as reflected light so it never goes black in shadow, plus a specular highlight from the sun. | Settings `water_reflection` 0.35, `water_specular` 0.2, `water_shininess` 512, matching `MapMesh.Instance.WATER_*` ([water](#water)) | SUB1, SWP1: a compact glint, not a white wash (0.5/0.5/64 washed a quarter of SUB1) |
| Blob shadows | The original's frog shadow quad and the Desert rock and tumbleweed shadow squares, which doubled up with the real shadows. | Off: `frogger/rendering/effect_shadows="off"` in `project.godot`; `--effect-shadows=retail` after `--` shows both for one launch ([shadows](#shadows)) | ORG1, DES1: whether the real shadow is enough of a landing cue |
| Real shadows | The directional light's shadow and its constants. | On: settings `real_shadows`, below the ceiling `frogger/rendering/shadows="on"` and `--shadows=off` for one launch; `shadow_splits` 2, `shadow_split_1` 0.25, `shadow_max_distance` 32, `shadow_bias` 0.05, `shadow_normal_bias` 1.0; fade and blur on `SceneLightingSpec` ([scene lighting](#scene-lighting)) | ORG1, JUN1, VOL1: acne, gaps under casters, shimmer while the camera follows |
| Tone mapper | Converts the linear scene for the screen. Linear puts stored sprite and HUD colours on screen exactly; AgX or Filmic compress highlights and desaturate, shifting every stored colour. | Settings `tonemapper` Linear, `exposure` 1 | Lava and the water glint if highlights read too harsh |
| Bloom | A soft halo around light above 1.0; stored colours of 1.0 or less are unchanged. | On: settings `bloom`, `bloom_intensity` 0.8, `bloom_threshold` 1.0; additive, HDR scale 2.0 ([scene lighting](#scene-lighting)) | SUB1 water glint, DES1 crack tint: a halo, not a wash |
| Glow halo | The soft additive halo around pickups and gold frogs that replaces the grey mask 1727. | Settings `glow_halo_strength` 2.0, matching `GlowHaloMaterial.DEFAULT_STRENGTH`; falloff `DEFAULT_FALLOFF` 3 ([glow](#glow)); 3.0 with falloff 2 clipped to a flat disc | ORG1 home flies, CAV1 fat fire flies, the ORG gold baby frog: a soft halo with a bright core, not a disc |
| Glow lights | Small coloured lights at each glow that tint the nearby ground and pulse with the halo. | On: settings `glow_lights`, `glow_light_energy` 1.0; `GlowLightSpec.ENERGY` 0.75 and `RANGE_SQUARES` 1.5 ([glow](#glow)); energy 2 washed the grass | ORG1, ORG gold frog: a visible tint under the glow without washing out the ground |
| Glow lights in caves | Whether cave glows also light the ground. | Off: settings `glow_lights_in_caves` ([glow](#glow)) | CAV1: whether the fat fire flies' light breaks the cave darkness |
| Lava emission | How strongly lava and hot rock glow and bloom. | Settings `lava_emission` 1.0, scaling each entry of `emissive_images.tres` ([lava](#lava)); molten lava at 1.5 saturated the red channel over about 30% of the VOL2 overview and flattened its texture; molten is 1.0 now that the lava lights also brighten it | VOL1 cracks, VOL2 lava lake, VOL3 lava pit: a red-orange glow with visible texture, not a flat sheet |
| Lava lights | Soft red-orange lights over lava that tint nearby rocks, walls, entities and the frog. | On: settings `lava_lights`, energy scaled by `lava_emission`; `EmissiveClusters.ENERGY` 0.6, `LIGHT_HEIGHT` 1.0, `CELL_SQUARES` 4, `MAX_LIGHTS` 24, `EmissiveLightSet.ATTENUATION` 0.25 ([lava](#lava)). Lights half a square up with attenuation 0.75 left bright patches on the lava and barely reached raised blocks | VOL1 blocks and gears beside the lava, the VOL2 walkway, the VOL3 pit walls: a warm tint, not a wash |
| Baked terrain shading | The maps carry per-vertex shading from the original artists, which now doubles with real light on slopes. | Settings `vertex_tint` 1.0 (full), 0 ignores it; `MapMesh.Instance.set_vertex_tint` ([terrain](#terrain)); cave terrain stays at 0 | DES1, VOL1 slopes: dark bands under real light |
| Texture filtering | Retail images sample nearest without mipmaps and shimmer at distance; mipmaps on `images/` would change the pinned import policy (`test_asset_import_settings`). Texture-pack images above scale 1 are mipmapped and linear. | Unchanged; an owner decision recorded in the [roadmap](../../PORTING.md#needed-from-the-owner) | Far terrain with and without a texture pack |

## Verification

The headless suites never compile shaders, so verification is by eye and by
windowed tools: `tools/probe_scene_lighting.gd` measures the energy mapping
on Forward+ through `SceneLighting` with the profile's bloom (`LAMBERT_SCALE`
is exact at 1), `tools/probe_model_morph.gd`
checks cel geometry through both shader families, and the capture tools fail
on any `SHADER ERROR` or a single-colour map capture
([testing](../testing/README.md#tools-and-visual-verification)). The goldens
pin the node-free mappings: [scene lighting](../../../tests/golden/specs/rendering.md#scene-lighting),
[cave light](../../../tests/golden/specs/rendering.md#cave-light),
[map UVs](../../../tests/golden/specs/rendering.md#map-uvs) and
[map UV ranges](../../../tests/golden/specs/imported-assets.md#map-uv-ranges).
