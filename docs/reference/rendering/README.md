# Rendering

- Renderer: Compatibility (OpenGL), black unlit background, no tone mapping, no fog, no MSAA. It was chosen because it mixes translucent polygons on stored colour values, as the original did.
- Depth buffer. A texture pixel made transparent by the black-is-transparent rule is discarded. Semi-transparent polygons go in separate surfaces that do not write depth, in four blend variants: average, add, subtract, add a quarter.
- One family of unshaded shaders written out from one template (`ModelShaders`). A textured pixel is texture colour times lit colour times 2, the lit colour stopping at full brightness. An untextured pixel is the lit colour as it is, not doubled. All of it is computed on stored colour values.
- The optional map model probe computes lit vertex colours from map lights. The standalone model viewer uses the polygon's own colour. Terrain uses stored colours except the cave Gouraud replacement.
- The renderer converts a shader's colour to linear light and back with two approximations that darken dark colours. The shaders undo this beforehand. `tools/probe_model_shader.gd` measures what reaches the screen; run it after changing the Godot version, the renderer or the environment.
- The black-is-transparent rule is a colour key over a whole 256x256 texture page in the original, not per image.
- Models use one clamped texture per VLO image; maps reconstruct physical PC pages for byte-wrapped UVs. No mipmaps. Filtering is a user option; the font is always nearest.
- One mesh per map group, split by material. Polygons with animated textures get their own surfaces.
- Map captures use a fixed 640x480 viewport; projection is explicit. The dedicated game scene adds the single-player HUD; the terrain viewer retains its inspection status overlay.

Map instances cache static material settings separately from animated UVs,
water offsets and texture bindings. Filtering, projection and reference-mode
changes invalidate settings for inactive animation frames too. Model instances
retain material bindings and prepare cel samples per tick;
unchanged animation samples and constant geometry skip redundant work without
stopping their animation clocks. Terrain
playback draws once per host frame and refreshes its overlay when displayed
state changes. None of these caches selects or suppresses gameplay entities.

## Stored colour conversion

- **In the Compatibility renderer a shader's `ALBEDO` is a stored colour value, not linear light.** The renderer converts it to linear light and back before writing it (`drivers/gles3/shaders/scene.glsl` and `tonemap_inc.glsl` in Godot's source).
- **The two conversions are approximations that do not undo each other for dark colours.** Without correction a grey of 8 came out as 1, 20 as 16, 40 as 38; from 64 up the value was unchanged. The shaders now work out beforehand the value that comes out right, and every value from 0 to 255 that was tried comes out exact.
- Mixing with the background happens after the conversion, on stored values, which is what the original did. A renderer that mixes in linear light would give about 0.73 where the original gives 0.5.
- Textures are given to the shader without Godot's colour conversion, and vertex colours reach it unchanged.

## Model lighting

Models are lit while the game runs; nothing is baked into the files. From the original's source (`API.SRC/MR_LIGHT.C`, `MR_VIEW.C`, `mr_stat.c`) and the reference engine:

- `lit = clamp((base * clamp0(ambient + colours * clamp0(directions * normal))) / 4096, 0, 255)`, per channel. `base` is the polygon colour; ambient RGB accumulates in C's byte-sized viewport back-colour fields (wrapping at 256), then is multiplied by 16. Light colours are multiplied by 16. Directions are normalized. Map creation uses only ambient/parallel lights; point/spot records are retained but ignored. Viewport registration prepends lights, so the last three parallel map records occupy the directional slots.
- A flat polygon is lit once from its one normal; a gouraud polygon once per corner.
- A level's lights are stored in its map file. The options screens use an ambient light of (0x60, 0x60, 0x60) and one parallel light of (0xA0, 0xA0, 0xC0).
- Lit values can exceed 128, so the stop at full brightness in `min(2 * lit, 255)` matters.
- Cave levels scale every live entity's colour by XZ distance from the frog's light: models unconditionally, model-free sprite forms unless the form's "don't fade colour" flag is set. Gameplay commits the scale and the live radii each tick ([entity contract](../gameplay/entities.md#cave-whole-map-behavior)); presentation applies committed scales, including an applied black, and feeds the committed radii to the terrain ramp uniforms. The non-cave edge fade remains unimplemented. Cave terrain is separate: C replaces Gouraud terrain colours with a squared-distance grey ramp. See [map lighting](../data/maps.md#rendering).

Fireflies draw as unlit two-image sprites in the entity's local XY plane at twice the image size; pickups draw the source glow and image quads from the pickup table with fixed colours, and both resolve images from the general and theme banks, then the resident `FIXE_VRAM`/`GEN_VRAM` banks. Sprite animation phases use the committed tick rather than a per-instance creation tick.

ORG1 flipbooks consume committed colour scaling and custom ambient,
including the diving turtle's blue tint. `AnimatedModelInstance` clones materials
per instance, preparing every texture-frame variant during initial lighting setup
so playback never allocates those materials. Shared meshes and materials remain
unchanged. The shader applies
map parallel lights to transformed normals, source colour-matrix scaling and
custom ambient narrowing before polygon modulation. Animated frog per-part
lighting remains deferred; this path does not establish full retail pixel equality.
The terrain viewer samples entity poses once per committed tick, then interpolates
continuous transforms and cel geometry per rendered frame.
[Cel atlases](../data/animation.md) move flipbook interpolation into the existing
vertex shader without changing source lighting or fragment materials. Reset and replacement
collapse history; resize refreshes projection bindings. Lighting uniforms update
when their inputs change; camera/cave setters visit only affected materials.
Inspector markers share selection materials, and unchanged FORM outlines/cells
retain their meshes. These caches never advance simulation or hide entities.

## Semi-transparency

For models, a textured polygon is drawn semi-transparent when its texture has the translucent flag (bit 0), using the texture's blend mode. Model untextured polygons are opaque. Maps instead use polygon flag bit 0; ENVMAP and MAX_OT control camera-relative UVs and background ordering. Retail textures use modes 0 (average) and 1 (add); synthetic tests cover all four.

## Behavior differences

Follow the frozen C engine for behavior:

| Subject | FrogLord | Reference engine, followed here |
|---|---|---|
| Semi-transparent model polygons on PC retail | Never shown. `MRMofPolygon.isSemiTransparent` answers no for every build after build 8, while its own comment says the game starts doing this at build 11, so the test reads as the wrong way round. | Shown for textures with the translucent flag |
| Lighting of models | None: the polygon's colour is shown | Lit while running, from the map's lights |

## Screen colour check

`tools/probe_model_shader.gd` checks textured modulation, dark colours,
transparency, all four blend modes, custom ambient and dive colour scaling
against expected screen RGB values.
Run it with a window after renderer/environment changes; it writes its report
outside the repository. The probe uses background (100, 60, 20) and permits
one byte per channel. For example, texture (200, 120, 40) with polygon colour
64 yields (100, 60, 20). Averaging the unmodulated texture with that
background yields (150, 90, 30). The expected cases live in the probe.

See [model animation](../data/animation.md) for animated UV/blend rules and
[map rendering](../data/maps.md#rendering) for terrain sampling and ordering.

`godot --path . --script tools/probe_model_morph.gd -- --output=<external-folder>`
compares native
blend-shape and cel-shader captures at five interpolation fractions, both unlit
and with changing normals under source lighting. It requires a rendered window
and writes paired PNGs plus pixel comparison facts outside the repository. The
existing one-byte-per-channel shader colour tolerance applies; geometry differences fail.

## Single-player HUD

The game scene uses a 640×480 canvas with proportional scaling and letterboxing.
`GameplayHud` reads detached committed state and events; its sprite animation,
help fade and counters never advance gameplay. Pause freezes the display clock.
Restart clears presentation history; source replacement releases HUD textures.
The shared world view keeps interpolation separate from the 30 Hz rules clock.

HUD textures resolve by FrogLord image names from the player's GENERAL, English
fixed-UI and level-select banks. The font uses its source 8×8 atlas with opaque glyph colours. Grey panels
average with the background; the timer panel draws over its coloured fill. Timers, spare-life groups,
checkpoint gather/return and bonus displays follow `HUD.C`; start release and
bonus awards remain owned by gameplay. Rendering consumes the existing checkpoint
mask rather than maintaining a second progress value.

P10 uses English UI assets. It does not yet read the options-language texture
pointer table or support repointing those UI entries; localization and full
options remain P13. Audio playback and particles retain their separate roadmap
scope. The rendering limitations above also apply to the dedicated scene.

The frozen port differs from unsanitized `HUD.C` here: its sanitizer changes
the score and timer background carriers from subtractive ABR2 to average ABR0.
Ordering-table insertion draws the opaque timer gradient before the averaged
RGB64 panel. `GAMEFONT.C` specifies font ABR1 but does not set the translucent
flag, so the native sprite path draws opaque glyphs. The game scene follows
these verified native results, rather than the unsanitized blend declarations.
