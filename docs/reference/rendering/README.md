# Rendering

- Renderer: Forward+ with scene lights, real shadows, lit materials and a
  linear tone mapper; the [lighting](lighting.md) reference owns the light
  mapping, the shader families, terrain sampling, the sky, water, the cave
  light and the shadow policy. The headless suites run on the dummy renderer.
- Depth buffer. A texture pixel made transparent by the black-is-transparent
  rule is discarded. Semi-transparent polygons go in separate surfaces that do
  not write depth, in four blend variants: average, add, subtract, add a
  quarter; they mix in linear light.
- Two shader families, one file per variant under `src/rendering/shaders/`
  (`ModelShaders` and `MapShaders` select and load them): lit for models and
  terrain, unlit for sprites and effects. A textured pixel is texture colour
  times polygon colour times 2, the colour stopping at full brightness; an
  untextured pixel is the polygon colour as it is.
- The black-is-transparent rule was a colour key over a whole 256x256 texture
  page in the original; the per-image PNGs carry each image's own alpha.
- Models use one clamped texture per VLO image and maps one repeating texture
  per image, UVs in retail pixels at any texture-set scale. The retail texture
  set samples nearest without mipmaps; the upscaled `x4` set samples through
  the `_linear` variants with mipmaps, and 2D draws scale it back to retail
  pixels. Filtering is a viewer option; `newfont` text is always linear
  over its 4x page ([fonts](../assets.md#fonts)).
- One mesh per map group, split by material. Polygons with animated textures
  get their own surfaces.
- Map captures use a fixed 640x480 viewport; projection is explicit. The
  dedicated game scene adds the single-player HUD; the terrain viewer retains
  its inspection status overlay.

Map instances cache static material settings separately from animated UVs,
water offsets and texture bindings. Filtering and projection changes
invalidate settings for inactive animation frames too. Model instances
retain material bindings and prepare cel samples per tick; unchanged
animation samples and constant geometry skip redundant work without stopping
their animation clocks. Terrain playback draws once per host frame and
refreshes its overlay when displayed state changes. None of these caches
selects or suppresses gameplay entities.

## Sprite lighting

`MapLighting` reduces a map's light records the way the original's viewport
did (`API.SRC/MR_LIGHT.C`, `MR_VIEW.C`, `mr_stat.c`): ambient RGB accumulates
in byte-sized fields (wrapping at 256) then times 16, light colours times 16,
directions normalized, only ambient and parallel records used (point and spot
records are retained but ignored), and the last three parallel records take
the directional slots because viewport registration prepends lights. The
options screens use ambient 0x606060 and one parallel light 0xA0A0C0 (low
byte red) from (0x800, -0x1000, -0x1000) (`OptionsModels.options_lighting`);
the level-select stack has its own record (`StackLighting`). Scene lights are
built from that record ([scene lighting](lighting.md#scene-lighting)), and
`MapLighting.shade` still lights sprites on the CPU with the C formula
`lit = clamp((base * clamp0(ambient + colours * clamp0(directions * normal))) / 4096, 0, 255)`
(splashes and the options sprites), pinned by the
[animated lighting golden](../../../tests/golden/specs/animation.md#animated-part-lighting).

Cave levels scale every live sprite's colour by XZ distance from the frog's
light unless the form's "don't fade colour" flag is set; gameplay commits the
scale and the live radii each tick
([entity contract](../gameplay/entities.md#cave-whole-map-behavior)), and
models and terrain take their fade from the [cave light](lighting.md#cave-light).
Fireflies draw as unlit two-image sprites in the entity's local XY plane at
twice the image size; pickups draw the source glow and image quads from the
pickup table with fixed colours (the glow as the [glow halo](lighting.md#glow)
sized by image 1727), and both resolve images from the general and
theme banks, then the resident `FIXE_VRAM`/`GEN_VRAM` banks. Sprite animation
phases use the committed tick rather than a per-instance creation tick.
[Cel atlases](../../../archive/docs/formats/animation.md) move flipbook
interpolation into the vertex shader; the terrain viewer samples entity poses
once per committed tick, then interpolates continuous transforms and cel
geometry per rendered frame. Reset and replacement collapse history; resize
refreshes projection bindings.

## Depth ordering

C drew gameplay with a painter's ordering table: 4096 slots over view distance
8192, so slot = view depth (SZ) >> 1. Fixed offsets keep objects in front of the
ground they stand on, which exact per-pixel depth testing loses. The port keeps
those offsets as depth-only vertex adjustments in game units of view depth;
screen positions are unchanged:

| Drawing | C ordering | Port depth bias |
|---|---|---|
| Ordinary terrain | average corner SZ, then `+ MAP_POLY_OT_OFFSET` (64 slots) | 128 further (`MapShaders.TERRAIN_DEPTH_BIAS`) |
| Frog | local table at origin SZ `+ FROG_GLOBAL_OT_OFFSET` (−0x30) before the shift | 48 nearer (`depth_bias` on frog materials) |
| Pickup glow and image | origin slot `+ PICKUP_OT_OFFSET` (−16 slots) | 32 nearer |
| Firefly sprites, entity models | average corner or per-polygon SZ, no offset | 0 |

Terrain therefore hides the frog only when more than 176 units nearer,
pickups 160, and fireflies or models 128. Far layers (MAX_OT, environment
water, sky) keep their own depth.
Per-vertex depth approximates C's whole-object and per-polygon sorting; it does
not reproduce painter's-order artefacts. Forest swarm quads (`FOR_SWARM_OT_OFFSET`)
keep bias 0 for now. Facts and citations:
[maps spec](../../../tests/golden/specs/maps.md#depth-ordering-biases).

## Semi-transparency

For models, a textured polygon is drawn semi-transparent when its texture has the translucent flag (bit 0), using the texture's blend mode. Model untextured polygons are opaque. Maps instead use polygon flag bit 0; ENVMAP and MAX_OT control camera-relative UVs and background ordering. Retail textures use modes 0 (average) and 1 (add); synthetic tests cover all four.

## Behavior differences

Follow the frozen C engine for behavior:

| Subject | FrogLord | Reference engine, followed here |
|---|---|---|
| Semi-transparent model polygons on PC retail | Never shown. `MRMofPolygon.isSemiTransparent` answers no for every build after build 8, while its own comment says the game starts doing this at build 11, so the test reads as the wrong way round. | Shown for textures with the translucent flag |
| Lighting of models | None: the polygon's colour is shown | Lit while running, from the map's lights |

## Geometry check

`godot --path . --script tools/probe_model_morph.gd -- --output=<external-folder>`
compares native blend-shape and cel-shader captures at five interpolation
fractions through both shader families, the lit pass under a directional
light so cel normals are exercised. It requires a rendered window and writes
paired PNGs plus pixel comparison facts outside the repository; geometry
differences fail. See [model animation](../../../archive/docs/formats/animation.md)
for animated UV/blend rules and [map rendering](../../../archive/docs/formats/maps.md#rendering)
for the original's terrain sampling and ordering.

## Single-player HUD

The game scene uses a 640×480 canvas with proportional scaling and letterboxing.
`GameplayHud` reads detached committed state and events; its sprite animation,
help fade and counters never advance gameplay. Pause freezes the display clock.
Restart clears presentation history; source replacement releases HUD textures.
The shared world view keeps interpolation separate from the 30 Hz rules clock.

HUD textures resolve by FrogLord image names from the player's GENERAL, English
fixed-UI and level-select banks. Text draws with `draw_string` from the
texture set's `newfont` bitmap font ([fonts](../assets.md#fonts));
`NewfontText` fixes the cell size and baseline, so retail glyphs land where the
hand-drawn cells did. Grey panels
average with the background; the timer panel draws over its coloured fill. Timers, spare-life groups,
checkpoint gather/return and bonus displays follow `HUD.C`; start release and
bonus awards remain owned by gameplay. Rendering consumes the existing checkpoint
mask rather than maintaining a second progress value.

The in-game HUD uses English UI assets; only the front-end menu images are
localized ([front end](../gameplay/front-end.md#languages)). The port does not
read the options-language texture pointer table or support repointing those UI
entries. Audio playback retains its separate roadmap scope;
[effects](effects.md) own the particle, shadow, splash and tint drawing. The rendering limitations above also apply to the dedicated scene.

The frozen port differs from unsanitized `HUD.C` here: its sanitizer changes
the score and timer background carriers from subtractive ABR2 to average ABR0.
Ordering-table insertion draws the opaque timer gradient before the averaged
RGB64 panel. `GAMEFONT.C` specifies font ABR1 but does not set the translucent
flag, so the native sprite path draws opaque glyphs. The game scene follows
these verified native results, rather than the unsanitized blend declarations.
