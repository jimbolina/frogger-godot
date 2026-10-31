# Rendering

## Scene lighting

`synthetic/scene_lighting.json` is written by
`python3 tools/make_golden_scene_lighting.py tests/golden/synthetic/scene_lighting.json --write`;
without `--write` the generator verifies the file and exits non-zero on any
difference. It implements the C viewport reduction (`API.SRC/MR_LIGHT.C`,
`MR_VIEW.C`, `mapload.C`, as summarised in
[model lighting](../../../docs/reference/rendering/README.md#model-lighting))
and the modern mapping in Python from this specification, and shares no
GDScript. `test_scene_lighting.gd` builds `MapLight` records from each fixture
(`enabled` is category 1), runs `MapLighting.configure`, then
`SceneLightingBuilder.from_lighting(lighting, shadows)`, and compares every
value within the file's `tolerance` (1e-4), the light basis's −Z axis against
`forward` included. It also checks `gamma` and `lambert_scale` against
`SceneLightingBuilder.GAMMA` and `LAMBERT_SCALE`; changing the energy scale
means changing both deliberately.

Viewport reduction: records are visited last to first; disabled records and
point lights (type 3) are skipped; ambient (type 1) bytes add times 16 and
narrow to `((sum >> 4) & 255) * 16`; the first three parallel (type 2)
records reached take the slots with colours times 16 and directions
normalised to 4.12 fixed, `round(d * 4096 / |d|)` with halves away from zero
(fixtures refuse components within 0.001 of a half).

| Field | Arithmetic |
|---|---|
| `ambient` | `gamma(A / 4096)` per channel, `gamma(x) = clamp(x, 0, 1) ^ 2.2` |
| `slots[i].forward` | fixed direction `(x, -y, -z) / 4096` in Godot space, renormalised to unit length |
| `slots[i].energy` | largest channel of `max(gamma(a + P_i / 4096) - gamma(a), 0)` times `lambert_scale` (1.0) |
| `slots[i].colour` | that slot over its largest channel, linear to sRGB (`12.92c` below 0.0031308, else `1.055c^(1/2.4) - 0.055`); white when the slot is black |
| `caster` | with `shadows`, the slot of largest `0.2126r + 0.7152g + 0.0722b` on the linear slot, lowest index on ties; −1 without shadows or slots |

Fixtures: `org1_like` (ambient 73, one white parallel light along
(−2246, 3335, 781), a plausible example only) with and without shadows;
`later_record_takes_first_slot`; `four_parallel_three_slots` (the first record
gets no slot); `disabled_records_skipped`; `point_light_ignored`;
`ambient_byte_wrap` (200+100 and 128+128 wrap to 44 and 0);
`saturation` (`a + p` above one in two channels); `straight_down` (0, 4096, 0),
whose basis needs the forward up vector; and `no_lights`.

For the deliberate-break check, change one expected `energy`, confirm the
generator refuses the file and the golden test fails, then restore with
`--write`.
