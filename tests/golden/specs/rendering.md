# Rendering

## Scene lighting

`synthetic/scene_lighting.json` is written by
`python3 tools/golden/make_golden_scene_lighting.py tests/golden/synthetic/scene_lighting.json --write`;
without `--write` the generator verifies the file and exits non-zero on any
difference. It implements the C viewport reduction (`API.SRC/MR_LIGHT.C`,
`MR_VIEW.C`, `mapload.C`, as summarised in
[model lighting](../../../docs/reference/rendering/lighting.md#scene-lighting))
and the Godot light mapping in Python from this specification, and shares no
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

## Map UVs

`synthetic/map_uv.json` is written by
`python3 tools/golden/make_golden_map_uv.py tests/golden/synthetic/map_uv.json --write`.
Without `--write` the generator checks the file and exits non-zero on any
difference. It implements in Python, sharing no GDScript: `mapload.C`
`ResolveMapPolys`, `mapdisp.c` `MapUpdateAnimatedPolys`, the ENVMAP branch of
`MapRenderQuads`, the sky-land set-up in `mapdisp.c` with the `MR_VRAM.C` HIT
trims, and the VLO padding rule.

`test_map_uv.gd` builds one `MapSceneData` per fixture (each
image a `VloImage` with a solid texture, each polygon its own group), runs
`MapMeshBuilder` and a `MapMesh.Instance`, calls `set_tick(tick)` per state and
`set_camera_presentation(camera)` for environment states, checks the
material's `image_origin`, `image_padding`, `image_padded_size`, `animated` and
`environment_uv`, the current cel and track offset, and compares at all six
mesh vertices (strip corners 0,1,2,1,3,2) within `tolerance` (1e-6):
`MapShaders.normalised_uv(mesh UV, image[, animation_offset])` for static
and animated polygons, `MapShaders.normalised_environment_uv(vertex ×
(256, −256, −256), camera_game, image)` for environment polygons, and
`MapSkyTiles.layer_uv(mesh UV, tile image)` for sky tiles with `UV2.x`
against `layer` and `sky_tiles.get_layers()` against `layer_count`.

| Field | Arithmetic |
|---|---|
| image `u`, `v` | `vram % 256 + (padded − size) / 2`, byte |
| static page byte | `((b × size) // 255 & 255) + u`, byte; size is the in-game size and fixtures keep HIT flags off ordinary polygons |
| animated page byte | base `(b × size) // 255 & 255` from the polygon's own image plus `(cel u + offset) & 255`, byte; each update increments the UV counter, zeroes the packed offset and counter when it equals the duration, otherwise adds `du \| dv << 8` 16-bit with U carrying into V; texture tracks advance the cel at their period and wrap to cel 0; tick t means t + 1 updates |
| environment page | `(vertex + short(−camera)) / 32 + 128`, without the floor or byte wrap |
| sky corners | `(u, v)`, `(u + w′, v)`, `(u, v + h′)`, `(u + w′, v + h′)` with `w′ = w − HIT_X`, `h′ = h − HIT_Y`, assigned by rotation orders 0123, 2031, 3210, 1302 |
| `uv` | `(page − vram % 256) / padded size` per axis |
| `sampled` | `uv − floor(uv)`, the texel repeat sampling reads |
| `retail_texel` | the retail page byte (floored for environment UVs) minus `vram % 256` |
| `layer` | first-seen index of the tile's texture in row-major order |

Without `divergence`, `floor(sampled × padded size)` equals `retail_texel` at
every corner; with it, at least one corner differs. Fixtures: `edge_byte_255`
(byte 255 reaches `u == width` on a 64-wide image and wraps to 0 on a 256-wide
one), `environment_page_256` (a pad-1 page-filling image with HIT_X seen from
three cameras including a fractional one and a short-wrapping one),
`environment_page_255` (the texture 1465 shape), `negative_dv_scroll` (dv −1,
duration 16, across the reset), `scroll_beyond_image` (the `SWP5_WIN95`
texture 1456 case), `cels_of_different_sizes` (32×32, 64×48, 40×36, period 2),
`sky_hit_x_rotations` (a HIT_X tile in all four rotations, a plain tile and a
HIT_X | HIT_Y tile). Divergences: `repeat_255` (the 255-padded environment
texture repeats every 255 texels where the page byte repeats every 256) and
`wraps_within_image` (a scroll that leaves its image wraps inside it where
retail samples the neighbouring page pixels). Deliberate break: change one
expected `uv`, confirm the generator refuses and the test fails, restore with
`--write`.

## Cave light

`synthetic/cave_light.json` is written by
`python3 tools/golden/make_golden_cave_light.py tests/golden/synthetic/cave_light.json --write`;
without `--write` the generator verifies the file and exits non-zero on any
difference. It implements the retail cave grey ramp (`mapdisp.c`, as
[maps](../../../archive/docs/formats/maps.md) describes it), Godot's omni
attenuation window and both light modes in Python from this specification,
and shares no GDScript. `test_cave_light.gd` compares
`CaveLightShape.inner_of`, `range_of`, `energy_of`, `window` and `ramp` with
every value within the file's `tolerance` (1e-4), and checks `fit_rings`,
`fit_reach`, `scale_steps` and `band` against the class constants.

Radii are squared game units; distances and ranges are Godot units (game
units over 256).

| Field | Arithmetic |
|---|---|
| ramp `g(t)` | `min(2 * grey / 255, 1)`; `grey` is 128 for `t < min`, 0 for `t > max`, else `128 - ((((128 << 16) // (max - min)) * (t - min)) >> 16)` clamped to 0..128; equal radii cut off hard at `max` |
| window `w(d, R)` | `(1 - (d / R)^4)^2` for `d < R`, else 0 (also 0 when `R <= 0`) |
| fit rings | 512 rings, ring `k` at integer `t = (4 * max * (2k + 1)) // 1024`, distance `sqrt(t) / 256` |
| fitted energy | `sum(w g) / sum(w w)` over the rings at range `R`; 0 when every `w` is 0 |
| `inner` | `sqrt(min) / 256` |
| `exact_edge.range` | `sqrt(max) / 256` |
| `fitted_range.range` | `sqrt(max) / 256` times the scale in [1, 2] maximising `sum(w g)^2 / sum(w w)` against the ramp with minimum `max - 0x100000` (1 on 32-bit underflow), by 32 golden-section steps from the bracket [1, 2] (ratio `(sqrt 5 - 1) / 2`, the left probe kept on ties, the final bracket's midpoint returned) |
| `energy` | the fitted energy of the fixture's own radii at that mode's range |
| `samples` | at `fraction` 0.25, 0.5, 0.75, 1.0 and 1.1 of the range: `window`, `lit = energy * window`, and `ramp` at `distance_r2 = floor((fraction * range * 256)^2)` |

Fixtures: initial radii for maximum radii 1, 3, 4, 5, 8, 12 and 255 squares
(`max = (r << 8)^2`, `min = max - 0x100000` or 1 on underflow, as
`ENTSTRCavCreateFroggerLight` seeds them), and croak swells of radii 1, 4, 8
and 12 (both radii grown by six steps of `max // 6`, wrapping at 32 bits, as
`FrogUpdateCroak` inflates them).

For the deliberate-break check, change one expected `energy`, confirm the
generator refuses the file and the golden test fails, then restore with
`--write`.
