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
intact. Standalone transform inspection remains available. `TerrainRun` can also
own an entity run for the bounded reaction sequence below. The frozen live-entity
traversal depends on visibility and creation lifecycle, which this all-attached
component does not reproduce.

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
supported safe FORM surface. This probe does not execute the reactions below.
The [testing guide](../testing/README.md) describes both inspection modes.

## Bounded POP reactions

`EntityCollisionSetup` composes base transforms, contact definitions and copied
map-group bounds. An optional `LevelDefinition.entity_collision` enables the
integrated run. Nonzero scripts exclude reaction execution because frozen
`ENTITY.C` runs scripts before frog collision. Geometry remains inspectable.
Collision callback addresses remain excluded until verified mappings and
implementations exist. Bonus callbacks belong to tongue collection; they remain
unexecuted diagnostics without independently blocking a FORM reaction.

The all-attached model assumes every accepted base entity is live. Following
`mapload.C` and `ENTITY.C/LinkEntities`, statics retain their authored group;
moving entities use their advanced path position. Group placement truncates
signed division toward zero and clamps to the map. Moving `HIDDEN` entities
are unlinked; static `HIDDEN` entities remain linked under this explicit lifetime
assumption. `NO_DISPLAY` does not disable collision. `COLLIDE.C/CollideFrog`
visits the frog's bounded 3-by-3 group neighborhood in Z then X order, with
reverse-authored moving entities before reverse-authored statics in each group.
Authored indices, not unique IDs or compacted array offsets, identify outcomes.

`ReactFrogWithForm` requires `USABLE` and selects CHECKPOINT, SAFE, POPDEATH,
DEADLY, SLIPPY, then BOUNCY in that order. This slice implements POPDEATH and
DEADLY with form-book death type POP. Higher-priority unsupported branches never
fall through to POP. Other deaths, checkpoint, safe-platform and bounce reactions
are diagnosed and omitted. Unusable squares do nothing; supported usable no-op
squares still set the per-tick hit observation. Scanning continues after a
death request, so later supported usable contacts also record hits. The first
accepted death wins through `FrogKill`'s pending-death guard.

POP requests animation 23, fixed camera, the existing life-decrement outcome
and an explosion effect. It clears control and marks pending death without
immediately entering DYING. Null death velocity preserves an ongoing jump to
land; otherwise velocity clears. The next control tick enters DYING with timer
70 and requests the death camera transition. FORM POP adds no sound, shadow
change or volcano-fire override. Animation request locks still apply. Explosion
and game-flow outcomes are requests, not effect rendering, lives progression
or full-engine effect RNG simulation.

`TerrainRun` advances private entity path/transform candidates before frog
control, movement and collision. Frozen collision early returns also suppress
entity queries: excluded frog modes, pending death, camera wait without twist,
fade death, freefall landing even on safe terrain, and theme-height death.
Entity reactions precede camera and animation. Reset and ticks commit entity,
frog, camera, animation and RNG state together; failures publish no partial
snapshots, hits or requests. Hit observations clear on the next successful tick.
See [architecture](../architecture.md) for ownership.

The retail demonstration uses high-detail DES2 and its primitive-free cactus
forms. An explicit inspection start at terrain cell `(17,30)` presses EAST at
command tick zero. Entity 46, `DES_STAT_CACTUS`, is first contacted while airborne
at command tick four, before the destination terrain's own POPDEATH reaction.
Its source facts and reproduction belong in the
[entity golden specification](../../../tests/golden/specs/entities.md).
Runtime verification is against v3.0e, not an assertion of equivalent runs on
the other supported builds.

Platform centring, carrying, jumping off, camera attachment, current/forbidden
entity links, visibility-driven live creation, scripts, zones, primitives,
callback dispatch and multiplayer remain outside this reaction slice. It does
not make a complete level playable.
