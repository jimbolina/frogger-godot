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

Deliberate-break and regeneration results: [P5 validation](../../../docs/validation/p5.md).

[Golden data index and shared rules](../README.md). Commands above run from the repository root.
