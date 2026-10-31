# Animation facts

Generate with `python tools/make_golden_animation.py <retail-folder>
tests/golden/pc-retail-v3.0e`. It uses the existing Python archive readers,
FrogLord's animation format definitions and the C engine's fixed-point
matrix and playback formulas. It shares no animation code with GDScript.
The earlier `mof_*` facts remain unchanged.

All digests use the [shared list-digest convention](../README.md#digest-convention). Raw
transform lists omit padding. Matrix sample lists contain nine row-major
4.12 basis integers followed by three whole-unit translations, ordered
by frame then part. Geometry includes every effective partcel: vertex
count and XYZ values, normal count and XYZ values, box count and XYZ values.
Incomplete models use their counterpart's geometry and animation data;
their original polygons and raw stored counts remain covered by `mof_*`.

| File | Rows and meaning |
|---|---|
| `animation_xar.tsv` | 78 files: resource, encoding, frame origin, set/transform counts, raw-transform digest, model metadata digest. Metadata is set model/action counts, then each model's static index, part count, flags, box length and XYZ values. |
| `animation_actions.tsv` | 187 actions: resource/static/set/action IDs, cel/part/frame counts, flags, availability, virtual-cel digest, transform-index digest, every sampled pose digest. |
| `animation_parts.tsv` | 1,009 parts: resource/static/part IDs, inheritance flag, effective cel count, geometry digest, ordered flipbook start/count pairs, target type/global polygon index/list index triples, and texture lists (length followed by image/duration pairs). |
| `animation_flipbooks.tsv` | 230 effective actions: resource/static/part/action IDs, start, length and availability. Includes 174 stored actions and the 19 unsafe authored ranges. |
| `animation_texture_cycles.tsv` | 613 targets: resource/static/part/target/list IDs, cycle duration, digest of entry/image pairs after each update through one cycle and its wrap. Zero durations take one update. |
| `animation_summary.txt` | Independent census of models, encodings, transforms, actions, virtual frames, raw flipbooks, unsafe actions and texture targets. |

`test_retail_animation.gd` verifies these against the readers and player.
The separate frog hash test uses the reference driver's FNV-1a over a
32-byte matrix, including its two zero padding bytes: action zero yields
`0x9655a8c6` at viewer tick zero and `0xa933ba38` after 179 further ticks.

## Animated part lighting

`python3 -I tools/make_golden_animated_lighting.py <retail-folder>
tests/golden/pc-retail-v3.0e` verifies `animated_lighting.tsv` against an
independent regeneration and exits non-zero on any difference; `--write`
regenerates it. It reuses the Python archive, model, XAR, map and
executable-table readers and the shared `MRNormaliseVEC` helper of
`make_golden_paths.py`; it never reads Godot output.
`test_retail_animated_lighting.gd` checks it.

Maps are each level's high-poly map-book row (`ORG1.MAP`, `CAV1.MAP`,
`SWP1.MAP`), the map `MapBookEntry.map_id(false)` names. Models are
`GEN_FROG.XAR`, the high-detail frog `TerrainFrogAssets` loads, and
`ORG_TURTLE3.XMR`, a flipbook whose cels carry their own normals.

| Rows | Columns |
|---|---|
| 3 `lights` | resource, map name, viewport ambient bytes, then the filled parallel slots in viewport order as `dx:dy:dz:r:g:b` joined by `/` (`-` for none). Directions are normalised 4.12 integers in game axes. |
| 1,764 `sample` | resource, model, map, action, virtual frame (flipbook cel), root rotation (`identity` or `y90`), part, polygon, light flags, colour scale and custom ambient bytes (zero when unused), polygon colour bytes, then `lit`: one `r:g:b` for a flat polygon or one per corner in stored order, joined by `/`. |

Samples cover the frog at action 0 frame 0 and the first longest valid
action (10) at its middle frame (17), every part; the flipbook at cels 0
and 27 of flipbook action 0. Each part contributes its first, middle and
last polygon with normals. The frog also has flags 3 with scale (0,64,192)
and custom ambient (32,64,64), and flags 2 with scale (64,64,64).

Lighting follows the frozen C:

- `mapdisp.c:1818-1872`: only static records (category 1) of API type
  ambient (1) or parallel (2) make lights; the colour word's low byte is red.
  A parallel direction is normalised (`MRNormaliseVEC`, rounded half away
  from zero as the reference `VectorNormal`) into the frame's z column.
- `API.SRC/MR_VIEW.C:843-876`: lights are prepended, so the last records
  come first; ambient bytes add into byte-sized back-colour fields, wrapping.
- `API.SRC/MR_LIGHT.C:114-155` and `178-220`: the first three parallel lights
  fill colour-matrix columns (bytes `<< 4`) and light-matrix rows.
- `API.SRC/MR_LIGHT.C:369-416`: flag 1 alone replaces the back colour; flag 2
  multiplies the colour matrix by `diag(scale << 5)` with `>> 12`, and the back
  colour becomes `(source * scale) >> 7`, the source being the custom ambient
  under flag 1 and the viewport ambient otherwise. The GTE back colour is
  bytes `<< 4`.
- `API.SRC/MR_ANIM.C:829-830` and `904-907`: the part world matrix is root
  times part matrix, and the GTE light matrix is the light matrix times it,
  each a 4.12 product shifted right by 12. Flipbook parts use the identity.
- GTE normal colour: `IR = clamp((LLM * n) >> 12, 0, 32767)`, then
  `clamp((back * 4096 + LCM * IR) >> 12, 0, 32767)`, then
  `clamp((base * that) >> 12, 0, 255)` per channel. Normals are the stored
  partcel normals, never renormalised.

The test configures `MapLighting` from the parsed map and compares ambient,
directions (`GameSpace.normal`) and colours exactly. For each sample it poses
`ModelAnimationPlayer`, takes the normals of the pose's partcel, applies the
flags as `AnimatedModelInstance.set_source_lighting` does and calls
`MapLighting.shade` with the Godot root basis times the pose basis. Each
channel must be within 1 of `lit`: the port shades in floats while the GTE
truncates at three stages, so a channel can land one step either side.
Every row and corner must be compared.

Deliberate break: change one `lit` triple and one `lights` ambient byte,
run the test and see `test_posed_part_lighting` and `test_map_light_inputs`
fail, then restore with `--write` and rerun.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.
