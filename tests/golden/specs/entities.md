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
