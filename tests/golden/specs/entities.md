# Entities

`pc-retail-v3.0e/entities_retail.tsv` has one row for every final `FROG` map in
the supported v3.0e archive. It records the map resource and name, total entity
count, generic `STATIC` and `MOVING` counts, and the count accepted by base
entity setup. The remaining columns are [list digests](../README.md#digest-convention)
of decoded integer facts. An empty list uses `-`.

`identity_digest` flattens every source ordered entity as `(index, source offset,
end offset, form grid id, unique id, form id, flags, EXE entity type, EXE script
id, EXE collision callback, EXE bonus callback)`. Missing forms use `-1` for
the four EXE fields. `base_record_digest` flattens generic `STATIC` entities as
`(index, 0, matrix[0..8], translation[0..2])` and generic `MOVING` entities as
`(index, 1, path id, segment id, segment distance, authored motion flags, speed)`.
The matrix is row major fixed12 rotation plus whole unit translation. Its
stored 16 bit pad and the PATH_INFO alignment pad are omitted from the digest;
the latter must be zero for setup acceptance. `setup_digest` flattens each
accepted `(index, unique id)`. Unknown behavior, unsupported alignment flags,
invalid path geometry or start, malformed PATH_INFO padding, and unknown flags
are omitted from setup but remain in the total identity count.

The generator follows FrogLord's `FroggerMapFilePacketEntity`,
`FroggerMapEntity`, `FroggerEntityDataMatrix`, `FroggerPathInfo` and
`PSXMatrix` layouts. It independently reads the owner's EXE form libraries,
FrogLord name configuration and MWD. It never writes source bytes to the
golden file. Regenerate with:

```powershell
python -B tools/make_golden_entities.py --data-dir C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER --out-dir tests\golden\pc-retail-v3.0e
```

`fixtures/entities.json` contains invented source ordered entity definitions.
Moving entities reference an invented case in `fixtures/paths.json` or provide
inline path segments. `synthetic/entities_trace.tsv` records tick zero and each
later tick with entity index, unique id, full matrix, and all fourteen path
snapshot values. Static entities use fourteen `-1` fields for the absent path.
The independent Python evaluator implements frozen `PATH.C` and generic entity
update math; before writing a trace, it requires exact agreement with
`entity_oracle_adapter.c`. That adapter calls unchanged frozen
`ENTSTRUpdateMovingMOF` and path functions and runs all paths before entity
transforms. The component reset applies authored flags before tick zero, so it
intentionally does not use the fresh live entity creation tangent. Build and
regenerate with external compiler output:

```powershell
& tools/build_entity_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-entity-oracle')
python -B tools/make_golden_entities.py --oracle (Join-Path $env:TEMP 'frogger-entity-oracle/entity_oracle.exe') --out-dir tests\golden\synthetic
```

Cases cover static transforms, world alignment, ordinary orientation from
diagonal and vertical lines, zero tangent, arc and spline tangents, shared paths
with different speeds, `NO_MOVEMENT`, backwards starts, and one shot/repeat
endpoints. Generic forms can also have scripts and callbacks; this component
leaves them unexecuted and does not claim complete entity behavior. Local
alignment and land projection are outside this component's scope.

## Guarded JUN1 route and zones

`fixtures/jun1_log_bank.json` supplies logical WEST `8` at command tick 0 and
EAST `2` at tick 12, observing 60 ticks. The independent retail reader combines
the player's MAP 656, EXE tables and resolved models. Its frozen-C transport
extends `platform_oracle.c`, retaining all 115 authored scan identities and
all six potentially contacting generic logs. Explicit proof-excluded null-live
shells retain the other identities and group order; this adapter does not claim
to execute their custom behavior. The [entity contract](../../../docs/reference/gameplay/entities.md#guarded-jun1-bank-route)
owns the boundary, exclusion conditions and route outcome.

`pc-retail-v3.0e/platform_jun1_route.tsv` contains 360 ordered rows: Control,
Move, Collision, Camera, Scripts and Pose for each command tick. Columns retain
fixed-point frog position/velocity, source cell/mode/flags/direction/input,
attachment, local cell, forbidden identity, selected-log pose/path cursor,
tracked camera/controller mapping, hit identities and source scan diagnostics.
Expected rows require agreement with the independent Python route calculation.
The C transport's synthetic animation lengths are not retail animation/RNG
expectations. Existing animation goldens cover those rules; full rendered
schedule comparisons include runtime animation, RNG and all outcomes.

`jun1_zone_records.tsv` records all 18 authored definitions, source offsets,
types, signed stored bounds, ordered child bounds/offsets, camera flags,
direction and eight vectors. `jun1_zones.tsv` contains 3,360 queries: all 28×60
cells for both camera type 0 and absent type 1. `fixtures/zones_synthetic.json`
and `synthetic/zones.tsv` additionally pin inclusive edges, empty child lists,
region gaps, overlapping zones/source order, inverted bounds and unsigned outer
versus signed child bounds. Both query families compare independent Python
results with unchanged frozen `CheckCoordsInZones`; GDScript never generates
expected data. The [map contract](../../../docs/reference/data/maps.md) owns
the packet layout and signedness disagreement.

Build the existing platform oracle into an external directory, then generate
numeric transports there. Use the builder provenance's frozen `acos_le.dat` path in
place of `<acos-table>` below. All stored golden files are text facts only.

```powershell
& tools/build_platform_oracle.ps1 -OutputDirectory <external-oracle>
python -B tools/verify_jun1_admission.py --data-dir <game-folder>
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --route-fixture <external-route-input>
& <external-oracle>/platform_oracle.exe <acos-table> --retail-route <external-route-input> > <external-route-csv>
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --route-trace <external-route-csv> --route-golden tests/golden/pc-retail-v3.0e/platform_jun1_route.tsv --verify
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --route-admission src/presentation/setup/jun1_exploration_admission.json --verify
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --zones-records-golden tests/golden/pc-retail-v3.0e/jun1_zone_records.tsv --verify
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --zones-fixture <external-zone-input>
& <external-oracle>/platform_oracle.exe <acos-table> --zones <external-zone-input> > <external-zone-csv>
python -B tools/make_golden_retail_platform.py --data-dir <game-folder> --zones-trace <external-zone-csv> --zones-golden tests/golden/pc-retail-v3.0e/jun1_zones.tsv --verify
```

For the synthetic zone family, replace `--data-dir <game-folder>` with
`--zones-synthetic-case tests/golden/fixtures/zones_synthetic.json` in the two
zone transport/comparison commands and use `tests/golden/synthetic/zones.tsv`.
Omit `--verify` only for intentional regeneration after source review. Corrupt
and restore one fact in each new family, requiring the focused check to fail
then pass. The [inspection guide](../../../docs/reference/testing/terrain-inspection.md#guarded-jun1-bank-exploration)
owns full 30/60/144 schedule and keyboard/capture acceptance.

The admission helper enumerates every integer distance on complete authored
paths, checks exact unresolved broad-phase identities, transformed FORM bounds,
the hippo's integer contact maximum and signed arithmetic closure. The source
behavior exclusions are documented in the helper and entity contract. Its
input dependency manifest contains hashes and decoded numeric facts, never
retail bytes; changing determining inputs requires a fresh source proof.

## FORM grids and bounded contact

`pc-retail-v3.0e/forms_retail.tsv` has one row per final-PC `FROG` map with
`resource_id`, map name, FORM count, FORM_DATA count, and three list digests:
`form_digest`, `form_data_digest` and `flags_digest`. `form_digest` flattens
`(form index, offset, data count, stored maximum Y, X count, Z count, X offset,
Z offset)`. `form_data_digest` flattens `(form index, data index, offset, height
mode, height, flags pointer, heights pointer)`. `flags_digest` concatenates
square flags in form, data and Z-major cell order. The independent Python
reader follows FrogLord's FORM pointer, header and grid-square layouts. It
reads the player's map data; the TSV contains decimal facts and digests only.
Regenerate with:

```powershell
python -B tools/make_golden_form_contacts.py --data-dir C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER --out-dir tests\golden\pc-retail-v3.0e
```

`pc-retail-v3.0e/form_contacts_retail.tsv` pins every ORG1 small-log entity's
source identity and its resolved collision facts: `resource_id`, `map`,
`entity_index`, `source_offset`, `unique_id`, `form_grid_id`, `form_id`,
`form_name`, `entity_flags`, `form_source_offset`, `xnum`, `znum`, `xofs`,
`zofs`, `height`, `max_y`, `radius_squared` and `flags_digest`. The generator
independently combines the player's EXE form book, map FORM/EMTP records and
MOF boxes. This is a narrow setup check for the first log contact case.

`fixtures/form_contacts.json` supplies invented contact definitions and world
points. `synthetic/form_contacts.tsv` records `case`, `status`, `local_x/y/z`,
`cell_x/z`, `height` and `cell_flags`; statuses are `contact`, `miss` and
`disabled`. A cell not reached by the query uses `(-1,-1)`; its height and
flags are zero. The Python evaluator independently checks frozen
`MR_SVEC_MOD_SQR` distance, `MRTransposeMatrix`/`MRApplyMatrix` local XYZ, and
each case's contact boolean against an adapter calling `CollideFrog` with one
live entity and map group. A signed 32-bit overflow case verifies source sphere
arithmetic. The adapter uses a model without API collision primitives and
USABLE, SLIPPY grid flags, so agreement checks the bounded contact gate, not
frog reactions, platform riding or full live-entity ordering. Build and regenerate:

```powershell
& tools/build_form_contact_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-form-contact-oracle')
python -B tools/make_golden_form_contacts.py --oracle (Join-Path $env:TEMP 'frogger-form-contact-oracle/form_contact_oracle.exe') --out-dir tests\golden\synthetic
```

The [entity contact contract](../../../docs/reference/gameplay/entities.md#form-contact-inspection)
defines the supported first GRID-mode record, model exclusions, shared runtime
maximum Y and exact geometric boundaries. An unusable square can still have
geometric contact; the query returns its raw flags without a reaction.

For each new golden family, corrupt one fact, observe its focused test fail,
restore it and observe the focused test pass.

## Entity FORM reactions and DES2 cactus

`fixtures/entity_reactions.json` contains invented terrain scenarios with a
detached `level.entity_collision` aggregate: source-ordered STATIC/MOVING entities,
paired first-GRID FORM contacts, and map-group base, dimensions and cell size.
Every case runs a stationary frog's first collision tick. The compact
`synthetic/entity_reactions.tsv` records frozen frog mode, flags, death
animation, velocity, camera mode, particle/audio requests and linked-order hit
IDs, followed by the independent bounded contact order, reaction statuses and
first lethal entity. A geometric contact on an unusable square has status
`none`. `POPDEATH` takes precedence over `DEADLY`, which uses the EXE death
type. Hidden and no-display flags do not disable STATIC collision; no-collision
does. Source group linking prepends static entities, reversing their authored
order within each group, and the frog visits a clipped 3×3 group area in Z,
then X order. Later contacts may mark hits after the first lethal contact.
Static entities link during map setup; moving entities are then prepended, so
traversal visits moving entities first. Hidden moving entities do not link.
Cases also pin source integer division for negative group coordinates,
out-of-bounds group rejection, shared paths and gaps in authored indices with
duplicate unique IDs. Moving collision poses are authored transport facts in
this component; path advancement is checked by the integrated trace below.
The bounded game deliberately reports unsupported non-POP death types and
omits their effects; only supported reactions are compared to frozen effects.

`entity_reaction_oracle.c` calls unchanged frozen `EntityLinkToMapGroup`,
`CollideFrog`, `ReactFrogWithForm` and `FrogKill`. Its wrappers count only
display and sound requests; it does not execute scripts, callbacks, collision
primitives, safe-platform attachment or checkpoint behavior. For supported
source-side effects, the independent Python evaluator checks exact C facts
before writing the synthetic fixture and trace. Safe/checkpoint diagnostic
cases only assert the bounded game omission.
Build outside both repositories and regenerate with:

```powershell
& tools/build_entity_reaction_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-entity-reaction-oracle')
python -B tools/make_golden_entity_reactions.py --oracle (Join-Path $env:TEMP 'frogger-entity-reaction-oracle/entity_reaction_oracle.exe')
```

`pc-retail-v3.0e/entity_reactions_retail.tsv` pins all 23 eligible DES2 cactus
entities, their source identity and STATIC matrices, resolved EXE book fields,
high-detail WAD/model resource, FORM grid/flags and shared writer indices,
and runtime model-derived maximum Y and squared radius. It contains decimal
facts only. The generator reads the owner's EXE, MWI/MWD, MOF and high-detail
DES2 map independently; every writer of a selected shared grid must use the
same form-book ID. Regenerate with:

```powershell
python -B tools/make_golden_entity_reactions.py --data-dir C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER
```

The bounded retail probe starts at DES2 cell (17,30), facing EAST with
identity controller directions. The independent frozen trajectory first
contacts entity 46 on command tick 4 at world (-683,-1576,2176), local
(47,-21,5), squared distance 2675. Its FORM cell flag is 5, and EXE death
type 5 selects POP animation 23 while preserving the airborne jump velocity.
The pending kill enters dying mode on the next control tick. The rendered
schedule probe uses the selected high-detail DES2 level and an explicit 30 Hz
component start; the C integrated trace below uses invented geometry and forms.

`fixtures/integrated_entities.json` and `synthetic/integrated_entities.tsv`
exercise three longer invented runs: a POP during a jump, a moving path entity
updated before frog collision, and two overlapping STATIC entities in reversed
linked order. The trace records six source phases per tick through the deferred
70-tick death outcome. It includes frog position/velocity, grid, flags, mode,
camera, animation script and RNG facts, both entity poses, ordered contacts,
hit IDs, first killer and intercepted effect/sound request counts. The
independent Python composition must match `integrated_entity_oracle.c`, which
calls unchanged frozen path, entity transform, control, move, collision,
camera and animation functions. The adapter's display/audio wrappers count
requests without creating render assets. Build and verify outside both
repositories with:

```powershell
& tools/build_integrated_entity_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-integrated-entity-oracle')
python -B tools/make_golden_integrated_entities.py --c-oracle (Join-Path $env:TEMP 'frogger-integrated-entity-oracle/integrated_entity_oracle.exe') --verify
```

## JUN1 SAFE platform

`pc-retail-v3.0e/platform_retail.tsv` contains one selected high-detail JUN1
`JUN_LOG` entity. It records its authored map/entity index and offset, EXE form
book identity, behavior and callback IDs, high-detail WAD/model kind and primitive
count, tick-zero position/tangent/matrix, first GRID
FORM dimensions, bounds, height, flags and model-derived collision radius.
It also records the PATH start and selected line segment, then the first SAFE
contact with that log from an explicit water-cell inspection start. The contact columns give
the command and advanced-entity tick, frog/entity world position, entity-local
position, FORM cell/flags and squared distance. All fields are decimal facts or
names; no source asset bytes are included.

The independent Python generator reads the owner's EXE, archive, JUN1 map and
MOF, then evaluates the frozen path sample, 6-tick normal hop and
`CollideFrog` fixed-width contact gate. It starts at authored water cell
`(18,5)`, facing NORTH and commanding NORTH at tick zero; this is an inspection
start, not an established route from safe terrain. The selected source entity
has no behavior script or collision/bonus callback. Regenerate or verify with:

```powershell
python -B tools/make_golden_retail_platform.py --data-dir C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER
python -B tools/make_golden_retail_platform.py --data-dir C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER --verify
```

## Synthetic SAFE interaction and camera correction

`fixtures/platforms.json` supplies invented platform scenarios through the
existing terrain start API. `synthetic/platforms.tsv` compares control, movement,
collision, camera, animation-script and pose phases independently. Its header
names fixed-point frog position/velocity, count, mode, flags, input, direction,
old height, no-input timer, attachment/forbidden indices, local cell/offset,
relative matrix and carry list. It also includes entity pose/path distance,
camera position, modification matrix, correction angles and projected controller
vectors; animation program/offset, script type/timer/flags, action/cel/environment;
shared RNG and intercepted sound/particle request counts. Matrices are row-major
fixed12 plus whole translations; positions ending in `16` are 16.16. Empty carry
lists are `-`; indices are authored identities, with `-1` absent.

The Python implementation must agree field-for-field with `platform_oracle.c`
before writing expected data. The adapter calls unchanged frozen path/entity,
frog, collision, camera, script and pose functions. Display/audio factories are
intercepted as requests; renderer transform construction and effect RNG are
outside this component comparison. Builder provenance hashes source and linked
objects and stays outside both repositories. The original read-only acos table
must be loaded explicitly; an uninitialized POP adapter table is not an oracle.

`synthetic/platform_acos_digest.txt` is the standard comma-separated decimal
list digest over reconstructed inputs -4096 through 4096. The generator compares
all entries against the original table before writing its digest; Godot computes
the entire mathematical sequence independently and compares the digest.

```powershell
& tools/build_platform_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-platform-oracle')
python -B tools/make_golden_platforms.py --c-oracle (Join-Path $env:TEMP 'frogger-platform-oracle/platform_oracle.exe') --acos-table ../froggy/engine/vendor/frogger-psx-src/source/API.BIN/acos_le.dat --verify
```

Omit `--verify` to regenerate. Platform trajectories, acos digest and JUN1 retail
facts each require a deliberate corruption/failure/restoration check. Runtime
retail acceptance checks the complete ordered scan, including earlier candidates,
against the independently predicted first contact; it does not bypass the scan
with a selected-entity query.

## Visibility-driven live-entity lifecycle

`fixtures/lifecycle_visibility.json` defines a 32×32 invented map-group grid,
two source-ordered entities with authored indices 2 and 9 and duplicate unique
ID 77, camera axes, a seven-step visibility/attachment schedule, selector edge
cases and signed raster lines. `synthetic/lifecycle_visibility.tsv` records the
ordered selected groups, polygon sum, both live/pending/generation states,
live-list order, creation/destruction observations and continuing path distance.
Tick zero is dormant. `synthetic/lifecycle_mapview_lines.tsv` pins the row
extents for short forward/reverse Z edges and signed coordinate boundaries.
The away-facing camera reaches the source 128-group cap; the far camera selects
no groups. Camera axes are fixed12 **columns**, while the C transport receives
the corresponding row-major `MR_MAT`.

Creation occurs at the tail of a tick, so first live update and collision are
deferred to the next tick. Pending instances disappear at the following entity
update unless the current frog link retains them. Paths advance while their
instances are absent; re-entry creates a new generation from that cursor. The
fixture keeps authored indices and duplicate unique IDs separate. These rows
describe the supported script-free mortal lifecycle only; they cannot justify
script, zone, custom callback, immortal or selective reset behavior.

`fixtures/lifecycle_integrated.json` is an invented 24×4 flat SAFE terrain
scenario with origin `(-512,-512)`, a 336-tick EAST/return WEST command sequence,
zero entity collision and one polygon per map group. The matching
`synthetic/lifecycle_integrated.tsv` records every command tick's frog X/Y,
camera source, ordered visible groups, live list, lifecycle events and dormant
path distance. The complete independent event schedule is: tick 0 creates 9
then 2; tick 59 destroys 9; tick 63 recreates 9; tick 75 destroys 9 then 2;
tick 245 recreates 2; tick 255 creates moving generation 3. The generation 2
recreation at tick 63 is an early visibility edge reentry; the later tick 255
creation follows full disappearance and return. This is a component inspection,
not a playable-level claim.

The Python generator implements C signed division, fixed12 projection, border
normalization, six-edge rasterization, source group links, paths and mortal
live-list transitions independently. It requires three separately built C
transports and compares every expected row before writing or verifying facts.
The first calls unchanged `CreateMapViewList` and `MapViewDrawLine`; the second
calls unchanged `UnlinkEntities`, `UpdatePathRunners`, `UpdateLiveEntities`,
`LinkEntities` and `CreateMapGroups`, using the source `NO_MODEL` form flag and
an initialized memory arena; the third reuses the existing integrated source
transport to call frozen frog, collision, camera and animation functions on the
invented 24×4 grid. The integrated Python hop/camera trajectory agrees with
all 336 frozen rows, including the camera matrix, before selecting groups.
Only model/polygon payloads and presentation sinks are omitted from C
transport. Polygon budget eligibility is checked separately against the text
counts; selected total must remain strictly below 2500.

`MAPVIEW.C` leaves the final view ray's Y in its scratch `vec` when it writes
only average X/Z before border normalization. Thus the border delta uses that
retained Y; for the default integrated camera at source `(-128,-512,-640)`,
group 556 is excluded. This source detail is pinned by the full selector array,
in addition to the signed short-Z line cases.

Build outside both repositories, then regenerate or verify:

```powershell
& tools/build_lifecycle_mapview_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-lifecycle-mapview-oracle')
& tools/build_lifecycle_entity_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-lifecycle-entity-oracle')
& tools/build_lifecycle_integrated_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-lifecycle-integrated-oracle')
python -B tools/make_golden_entity_lifecycle.py --mapview-oracle (Join-Path $env:TEMP 'frogger-lifecycle-mapview-oracle/lifecycle_mapview_oracle.exe') --entity-oracle (Join-Path $env:TEMP 'frogger-lifecycle-entity-oracle/lifecycle_entity_oracle.exe') --integrated-oracle (Join-Path $env:TEMP 'frogger-lifecycle-integrated-oracle/lifecycle_integrated_oracle.exe') --verify
```

Omit `--verify` only when intentionally regenerating after reviewing source
behavior. Corrupt and restore a fact in each TSV, and require its golden test
to fail then pass. `tools/verify_lifecycle_schedules.py` compares the complete
headless and 30/60/144 FPS lifecycle traces, validates the 336-tick final
states against `lifecycle_integrated.tsv`, and checks external captures. It
also accepts `lifecycle_safe_moving.json` and `lifecycle_safe_static.json` to
check attachment/departure presentation without a retail asset.

Independent v3.0e retail inspection identifies high-detail FOR1 resource 654
as a zero-zone, script-free generic MOVING candidate with 11×9 groups and 2,992
polygons. Entity 1 has offset 3684,
unique ID 1532, path 2, initial distance 348, speed 18 and repeat motion; its
line runs `(512,-1433,3200)` to `(-896,-1433,2048)`, length 1819. Component
path calculations place it in group 83 initially, group 82 at advanced tick 18,
and group 83 again at tick 94. Holding group 83 constant creates it after the
first advance, destroys it at tick 19 and recreates it at tick 94. Group 83 has
74 polygons. That manual
selection is not an automatic retail camera sequence. A rendered retail
visibility demonstration remains unverified.
