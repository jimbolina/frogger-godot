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
