# Entity transforms and FORM contact

`EntitySetup` resolves each EMTP record through the selected map's theme/form
book, retaining its source/build/resource identity, authored entity index,
unique id, form, flags, script id and callback addresses. The authored index is
the run identity; it may have gaps after unsupported neighbors are omitted.
Duplicate unique ids remain distinct. Setup accepts resolved `STATIC` and
`MOVING` names. A static entity copies the 32-byte PSXMatrix prefix. A moving
entity reads the 12-byte PATH_INFO prefix and attaches a supported
[path](paths.md) by authored path index. Subtype payload bytes remain in the
decoded map record for later behavior work.

Invalid form/name, matrix or PATH_INFO, missing/unsupported path, bad start,
unknown entity flag bits, `LOCAL_ALIGN` and `PROJECT_ON_LAND` omit only that
entity. Diagnostics include source/build/resource, authored index, form and
offset with the reason and fallback. `HIDDEN`, `NO_DISPLAY` and `NO_COLLISION`
are retained as flags; this component intentionally attaches every supported
record and does not model visibility or collision lifetimes. Script and callback
ids are retained but unexecuted, with an `unexecuted_hooks` warning.

`EntityRun` owns copies of definitions and one independent `PathRunner` per
moving entity, even when they share path geometry. Reset applies PATH_INFO
segment, distance, speed and motion flags, then sets active unless
`ENTITY_NO_MOVEMENT` clears it, as frozen `PATH.C/ResetPathRunner` does. Tick 0
is the reset pose; `step(0)` produces tick 1. Paths advance in reverse creation
order before moving transforms are updated in that order. Static transforms
retain the authored matrix. A moving transform starts with identity rotation
and path position. `ALIGN_TO_WORLD` keeps that rotation. Otherwise the generic
`ENTITY.C` create/update rule uses path tangent as Z, world positive Y crossed
with Z as normalized X, and Z crossed with X as Y; matrix axes narrow to signed
16-bit source fields. A zero or vertical tangent may give zero axes under that
source rule. This bounded component omits camera-parallel entity-book behavior.
Fresh `mapload.C` construction first evaluates a forward tangent, then applies
PATH_INFO backward motion; `ResetPathRunner` applies backward motion before
evaluation. Consequently a backward entity's initial tangent can differ between
fresh map load and reset. This component uses the reset-style tick-0 pose.

The snapshots are source ordered and deeply detached, including matrix arrays
and nested path cursors. Failed reset or step leaves the full aggregate state
intact. Transform inspection is independent of `TerrainRun`; no entity affects
the frog yet. The frozen live-entity traversal also depends on visibility and
creation lifecycle, which this all-attached component does not reproduce.

## FORM contact inspection

`MapFile` decodes indexed FORM grids under the [map format contract](../data/maps.md).
`FormContactSetup` reads every authored EMTP entity in source order before
attaching contact facts to the accepted base transforms. Frozen `mapload.C`
writes a FORM grid's runtime maximum Y from each loaded model; when entities
share a grid, the last writer determines the value. `THICK_FORM` writes 32767
before `UNIT_FORM` can write 256; otherwise a static model uses the first
part's first partcel bounding-box corner 7 and an animated model uses the
first set's first model global box.
The stored FORM maximum-Y word is runtime scratch, not that derived value.
An unresolved determining writer leaves the affected grid unavailable. A known
dummy model does not write a new value; a `NO_MODEL` form may still write when
its authored MOF is loaded, so setup checks that model before excluding contact.

The form-book radius is used when nonzero. Otherwise, for a static model,
setup takes the largest signed 32-bit squared distance among all partcel box
corners and adds 100, matching frozen `mapload.C`. Contact supports a static
MOF, including flipbooks, with no collision primitives; the C primitive test
would otherwise take priority. It uses the first FORM_DATA in GRID height mode
zero. Additional entries are retained and reported. `NO_COLLISION`, `NO_MODEL`,
missing bounds, unsupported models or modes, and nonzero collision callback
addresses produce source-located exclusions. Scripts and bonus callbacks remain
source facts without execution. FrogLord's script `CallbackNames` is a separate
namespace; no form callback address mapping is inferred from it.

`FormContactQuery` tests one explicitly selected detached entity pose against
one fixed world point. It narrows the displacement to signed 16-bit source
coordinates, uses signed 32-bit squared-distance math and a strict form-book
sphere check, then applies the transposed 4.12 rotation. Local X/Z grid bounds
are strict; Y accepts the scalar height and derived maximum inclusively. A hit
returns its Z-major cell and raw 16-bit flags, including an unusable square's
flags. Invalid input, omitted support, disabled collision and geometric misses
remain distinct results. The query does not react to flags, kill or move the
frog, ride a platform, dispatch callbacks, or reproduce map-group/live-entity
traversal. It never mutates decoded data or `EntityRun`.

`entity-contact-v1` traces use the same fixed-point, post-tick query for
headless and rendered schedules. ORG1's first small log is an example of a
supported safe FORM surface. The [testing guide](../testing/README.md) describes
the viewer controls; full collision and frog integration remain future work.
