# Rendering

- Renderer: Compatibility (OpenGL), no environment, no tone mapping, no fog, no MSAA. It was chosen because it mixes translucent polygons on stored colour values, as the original did.
- Depth buffer. A texture pixel made transparent by the black-is-transparent rule is discarded. Semi-transparent polygons go in separate surfaces that do not write depth, in four blend variants: average, add, subtract, add a quarter.
- One family of unshaded shaders written out from one template (`ModelShaders`). A textured pixel is texture colour times lit colour times 2, the lit colour stopping at full brightness. An untextured pixel is the lit colour as it is, not doubled. All of it is computed on stored colour values.
- The lit colour is the polygon's colour lit by the map's lights, which the game works out while it runs. Until maps are read (P6) the polygon's own colour is used.
- The renderer converts a shader's colour to linear light and back with two approximations that darken dark colours. The shaders undo this beforehand. `tools/probe_model_shader.gd` measures what reaches the screen; run it after changing the Godot version, the renderer or the environment.
- The black-is-transparent rule is a colour key over a whole 256x256 texture page in the original, not per image.
- One texture per VLO image, clamped, no mipmaps. Filtering is a user option; the font is always nearest.
- One mesh per map group, split by material. Polygons with animated textures get their own surfaces.
- HUD on a 640x480 canvas layer. The camera's field of view is derived in P6 against the reference pictures.

## Stored colour conversion

- **In the Compatibility renderer a shader's `ALBEDO` is a stored colour value, not linear light.** The renderer converts it to linear light and back before writing it (`drivers/gles3/shaders/scene.glsl` and `tonemap_inc.glsl` in Godot's source).
- **The two conversions are approximations that do not undo each other for dark colours.** Without correction a grey of 8 came out as 1, 20 as 16, 40 as 38; from 64 up the value was unchanged. The shaders now work out beforehand the value that comes out right, and every value from 0 to 255 that was tried comes out exact.
- Mixing with the background happens after the conversion, on stored values, which is what the original did. A renderer that mixes in linear light would give about 0.73 where the original gives 0.5.
- Textures are given to the shader without Godot's colour conversion, and vertex colours reach it unchanged.

## Lighting contract for P6

Models are lit while the game runs; nothing is baked into the files. From the original's source (`API.SRC/MR_LIGHT.C`, `MR_VIEW.C`, `mr_stat.c`) and the reference engine:

- `lit = clamp((base * clamp0(ambient + colours * clamp0(directions * normal))) / 4096, 0, 255)`, per channel, where `base` is the polygon's colour, `ambient` is the sum of the ambient lights' colours times 16, `colours` holds each light's colour times 16 and `directions` each light's direction. At most three directional or point lights are used.
- A flat polygon is lit once from its one normal; a gouraud polygon once per corner.
- A level's lights are stored in its map file. The options screens use an ambient light of (0x60, 0x60, 0x60) and one parallel light of (0xA0, 0xA0, 0xC0).
- Lit values can exceed 128, so the stop at full brightness in `min(2 * lit, 255)` matters.
- Cave levels also scale each model's colour by distance from the frog's light, unless the form has the "don't fade colour" flag.

## Semi-transparency

A textured polygon is drawn semi-transparent when its texture has the translucent flag (bit 0), mixed the way the texture's blend mode says. Retail textures only use modes 0 (average) and 1 (add). Untextured polygons are never semi-transparent.

## Behavior differences

Follow the frozen C engine for behavior:

| Subject | FrogLord | Reference engine, followed here |
|---|---|---|
| Semi-transparent model polygons on PC retail | Never shown. `MRMofPolygon.isSemiTransparent` answers no for every build after build 8, while its own comment says the game starts doing this at build 11, so the test reads as the wrong way round. | Shown for textures with the translucent flag |
| Lighting of models | None: the polygon's colour is shown | Lit while running, from the map's lights |

Screen measurements: [P4 validation](../validation/p4.md). Animation-specific UV and blend rules: [animation](animation.md). Map-group meshes, map lighting and HUD layout above are planned contracts; the model viewer currently uses unlit polygon colours.
