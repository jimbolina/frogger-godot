# Entity transforms and FORM contact

`EntitySetup` resolves each EMTP record through the selected map's theme/form
book, retaining its source/build/resource identity, authored entity index,
unique id, form, flags, script id and callback addresses. The authored index is
the run identity; it may have gaps after unsupported neighbors are omitted.
Duplicate unique ids remain distinct. Default transform setup accepts resolved static and path-follower behaviors;
custom execution is enabled explicitly. A static entity copies the 32-byte PSXMatrix prefix. A moving
entity reads the 12-byte PATH_INFO prefix and attaches a supported
[path](paths.md) by authored path index. Subtype payload bytes remain in the
decoded map record for later behavior work.

Invalid form/name, matrix or PATH_INFO, missing/unsupported path, bad start
and unknown entity flag bits omit only that entity.
`PROJECT_ON_LAND` is supported for whole-map path followers, fireflies, moving
platforms, hedgehogs, Swamp slugs and nuclear barrels, which project onto the first terrain layer during live
updates while creation and reset keep the plain path pose; other projected
transforms remain omitted. `LOCAL_ALIGN` is supported for whole-map generic
path followers, Swamp slugs and nuclear barrels as frozen
`ENTSTRUpdateMovingMOF` applies it: creation keeps the plain path pose, and each
live update takes Z from the tangent, X from the world Z axis when the previous
X axis leans more than 0x800 along Z and the world X axis otherwise, and
Y = Z x X without re-orthogonalising. Combined with `PROJECT_ON_LAND`, or on any
other behavior, it still omits the entity. Diagnostics include source/build/resource, authored index, form and
offset with the reason and fallback. `HIDDEN`, `NO_DISPLAY` and `NO_COLLISION`
are retained as flags; the default component attaches every supported
record. The opt-in visibility lifetime below narrows that set. Script and callback
ids remain diagnostic-only in transform inspection, with an `unexecuted_hooks` warning.

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
intact. Standalone transform inspection remains available. `GameplayRun` can also
own an entity run for the bounded reaction sequence below. The frozen live-entity
traversal depends on visibility and creation lifecycle, which this all-attached
default does not reproduce.

## Visibility lifecycle

`EntityCollisionDefinition.lifecycle` enables single-player live-entity creation
for integrated runs. Null preserves all-attached inspection.
Generic retail terrain inspection supports zero-zone maps and script-free
generic STATIC/MOVING entities.
Ordinary inspection retains unsupported script-bearing records as dormant
source identities. The separate [scripted custom behavior](#custom-entity-behaviors) supplies validated programs and the required
custom/immortal behaviors. Whole-map ORG1 adds selective checkpoint/death resets
and verified typed collision/bonus callbacks. General inspection retains its
explicit dependency exclusions.

`GameplayRun` advances persistent paths, culls/updates live entities, runs frog
and camera/animation phases, then selects and expands visible groups before
the aggregate commit (`gamesys.C:1322–1350`). Reset has no mortal live
instances and does not prewarm visibility; supported immortals are constructed
in authored order before the first tick. End-of-tick creation first becomes
eligible for updates and collision on the following tick. Paths continue while
their live instances are absent. Recreation uses the current path pose and
increments a generation; a full reset restores generation zero.

`MapGroupVisibility` follows `MAPVIEW.C:55–86,109–243,457–566`: fixed view-plane
half-size 160×120, perspective 256, ground projection, 768-unit border, the six
source raster edges, and at most 128 groups in Z/X order. Geometry must fit the
source's 64-row visibility buffer and signed16 group indices. It consumes the
candidate camera frame, including shake, never Godot culling or an interpolated
camera. Signed source arithmetic, the rasterizer's small-Z branch and the final
view ray's retained Y component during border normalization are preserved. The
selected groups' eight-type polygon counts must sum to less than 2500. This
conservative limit ensures `CreateMapGroups` visits the whole list without
reproducing renderer allocation history; equality is unsupported. Selection or
budget failure rejects the entire tick rather than approximating the live set.
`mapdisp.c:413–435,454–478,962–977` owns this boundary.

Volcano whole-map setup enables source allocation history because its camera
selections can exceed the conservative polygon bound. The detached allocator
visits each group's entities before checking polygon resources, charges existing
groups against the 2500-polygon budget and stops only when that budget is
exhausted. Oversized new groups and a full 128-slot pool do not suppress that
group's entity visit. Existing groups with timer one are charged but not
refreshed; other selected allocations refresh to three. The source RenderMap
timer decrement runs once per committed logic tick, including headless runs,
so display frame rate cannot change entity lifetime. Allocation history copies
and rolls back with the run; bounded inspection retains its checked limit.

The high-detail retail ORG1 map has 84 visible groups containing 395 counted
polygons in total. Any camera selection is a subset of these groups, so its
polygon count remains below 2500 and the map cannot exhaust the 128-slot pool.
This whole-map bound covers arbitrary camera motion, including authored zones,
without a route or corridor assumption. [Independent map facts](../../../tests/golden/specs/maps.md)
pin every group's count. Repointed entities do not alter this bound; map edits
that increase geometry still receive the checked selector diagnostics.

Every surviving mortal instance is marked DESTROY during entity update.
Visible nonhidden membership clears that mark at the tail. A mark surviving
until the next update destroys the instance, except when frog 0 retains its
current entity link (`ENTITY.C:370–400`). This protection also covers angled
departure and retained-link freefall, independent of ON_ENTITY/CARRY flags.
The forbidden identity alone does not protect an instance. Destruction does
not invent a detachment or camera transition. Hidden moving records are
unlinked; hidden statics retain their groups but receive no creation/renewal.
NO_DISPLAY has no lifetime effect. Collision and attachment pose lookups
require a live supported identity.

Snapshots retain source-ordered slots, authored indices and duplicate unique
IDs, plus live/pending state, generations, actual live-list order and ordered
creation/destruction observations. Dormant matrices are inspection poses only.
The viewer creates a fresh presentation instance at each generation and releases
it on destruction; a tail-created instance starts at its initial animation frame.
All lifecycle definitions and snapshots are detached. Failed tick/reset leaves
frog, entities, paths, camera, animation, RNG and requests unchanged.

The automatic-camera demonstration is synthetic. High-detail v3.0e FOR1 is
a source-data candidate with zero zones and script-free FOR_JAY movers, but an
automatic retail camera/lifecycle sequence is not verified. A manually selected
group is only a component stimulus. Reproduction and independent facts belong
in the [entity golden specification](../../../tests/golden/specs/entities.md);
inspection commands belong in the [testing guide](../testing/terrain-inspection.md).

## Combined camera zones and lifecycle

Authored `LevelDefinition.camera_zones` may coexist with visibility lifecycle.
Movement selects the frog zone before collision; the camera consumes that
selection, then visibility uses its updated source position and fixed12 basis
after animation. Creation is still at the tail, with update/contact eligibility
on the following tick. Current attachment protects an offscreen live instance;
the forbidden identity alone does not. A visibility failure discards zone
selection, camera transitions, paths, lifecycle events/generations and all
other candidate state. Reset leaves entities dormant without prewarming.

The synthetic out-and-back scenario verifies automatic zone entry/exit and
entity recreation. The separate v3.0e high-detail JUN1 probe selects eleven
script-free `JUN_LOG` entities, retaining authored indices. It pins supplied
map bytes by digest, resolved behavior/model bindings and log model digests
against independent text facts. Omitted records receive explicit diagnostics.
It uses the existing prescribed camera sequences with fresh camera/entity
state between them; it performs no frog movement or contact. Camera, selection
and entity state commit atomically, including at that sequence boundary.
Presentation creates/releases log instances from committed generations.

These bounded fixtures retain their selected dependencies and all-attached
presets. Whole-map ORG1 uses separate dependency setup with scripts, custom
behaviors, immortals and selective resets. Reproduction and evidence
fields belong to the [golden specification](../../../tests/golden/specs/entities.md#combined-camera-zones-and-lifecycle);
launch commands belong to [inspection](../testing/terrain-inspection.md#combined-zone-and-lifecycle-inspection).

## FORM contact inspection

`MapFileReader` decodes indexed FORM grids into `MapFile` under the [map format contract](../../../archive/docs/formats/maps.md).
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
corners, expands it for each collision primitive's squared offset plus squared
extent, then adds 100, matching frozen `mapload.C`. Primitive expansion uses
source unsigned arithmetic; an explicit form-book radius bypasses derivation.
Default contact supports a static
MOF, including flipbooks, with no collision primitives. The road preset below
supports vehicle cuboids before any optional FORM fallback. Ordinary
FORM contact uses the first FORM_DATA in GRID height mode
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
integrated run. General inspection excludes nonzero scripts from reaction
execution because frozen `ENTITY.C` runs scripts before frog collision.
The guarded ORG1 adapter supplies its verified script closure; whole-map ORG1
resolves the complete authored dependency set.
Geometry remains inspectable.
Unknown collision callback mappings remain excluded with diagnostics. Verified
callbacks resolve to typed behavior during application setup. Bonus callbacks
execute during tongue collection in whole-map play; the bounded POP probe does
not execute them.

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
DEADLY, SLIPPY, then BOUNCY in that order. The default mode implements POPDEATH and
DEADLY with all eight form-book death values. DIE_ON_BACK and unknown values
use the source default SQUISHED animation. DROWN supplies downward velocity;
FLOP hides the shadow and preserves velocity for FORM contacts in CAV3.
Higher-priority unsupported branches never fall through to a death reaction.
Checkpoints collect through the shared mask; BOUNCY forbids the entity, snaps the frog to the entity origin and starts the forced bounce jump described under [Jungle](#jungle-whole-map-behavior); SAFE requires the platform capability below. Unusable squares do
nothing; supported usable no-op
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

`GameplayRun` advances private entity path/transform candidates before frog
control, movement and collision. Frozen collision early returns also suppress
entity queries: excluded frog modes, pending death, camera wait without twist,
fade death, freefall landing even on safe terrain, and theme-height death.
Entity reactions precede camera and animation. Reset and ticks commit entity,
frog, camera, animation and RNG state together; failures publish no partial
snapshots, hits or requests. Hit observations clear on the next successful tick.
See [architecture](../architecture.md) for ownership.

The [DES2 golden specification](../../../tests/golden/specs/entities.md#entity-form-reactions-and-des2-cactus)
owns the retail probe and its source comparisons. Runtime evidence is v3.0e.

## Bounded SAFE platforms

`EntityCollisionDefinition.platforms_enabled` defaults to false. Enabling it
adds SAFE to the existing POP capability and requires an integrated camera.
The same primitive-free static/flipbook model and first GRID-mode FORM_DATA
limits apply. The copied form-book flags retain `NO_ROTATION_SNAPPING` (2),
`NO_ENTITY_ANGLE` (4), `NO_CENTRING_X` (64) and `NO_CENTRING_Z` (128).

`COLLIDE.C:216–330,902–1106` owns contact and attachment order. The neighborhood
and forbidden authored identity are cached at scan start. Current attachment
and position are read again for every candidate: a SAFE landing can move or
transfer the frog before a later SAFE or POP reaction. Scanning continues after
mount or death request. SAFE classification alone sets no HIT. It rejects a
forward axis whose horizontal squared length is below `0x700²`; otherwise the
inclusive FORM Y volume is the gate, even for an ascending frog. Unless SOFT
bypasses it, the existing fall reaction runs first, retaining ordered safe,
stun/shake and fatal-fall requests without terrain snapping or clear masks.

Landing starts from contact-local X/Z and FORM height. Each enabled centring
axis targets the authored cell centre; a coordinate outside
`±(dimension−1)*128` forces centring even with NO_CENTRING. A displacement at
least 96 on either axis requests STRUGGLE, otherwise PANT. Source vector length
gives `count = length / 15 + 1`; velocity truncates, movement decrements first,
and zero snaps and clears velocity. Stationary and centring carry use the
advanced pose and signed-short whole local coordinates. Airborne local X/Z
uses full 16.16 values and the frozen wide matrix accumulator. Entity update
clears transient HIT/CARRY, which their source phases reassert.

`FROG.C:1038–1507,1818–1849,1944–2134,2300–2338` owns local hops and departure.
Normal/quick/super hops retain 6/3/15 ticks, buffering, auto-hop and ordered
animation/sound/score requests. A requested in-FORM destination requiring an
unsupported reaction fails the whole tick before commit. An unusable destination
blocks with OUCH, except source `BOUNCE_WALL_N` permits departure. Same-platform
hops perform their special FORM re-reaction after movement reduces count to 1;
a surviving frog completes the jump on the next tick with terrain-style grid-flag
reaction order. Authored DEADLY reactions kill at count one and prevent normal
landing from replacing the selected death.
Usable no-op, POP and authored DEADLY destinations remain supported; they are not
reclassified as SAFE. The special count-one path reasserts HIT outside the FORM
reaction, even if that reaction rejects a now-vertical SAFE surface.

Departure searches terrain using camera controller directions; NO_ENTITY_ANGLE
uses a world target. Angled departure without terrain retains the entity frame
until jump completion, whereas NO_ENTITY_ANGLE detaches immediately. Departure
caches the forbidden identity; terrain landing clears it. The
[camera contract](gameplay-camera.md) owns projection and correction behavior.

The [JUN1 golden specification](../../../tests/golden/specs/entities.md#jun1-safe-platform)
owns the retail probe and source comparisons. Entity-specific sliding
and multiplayer stacking remain unsupported; FORM bounce is described under [Jungle](#jungle-whole-map-behavior). Verified v3.0e FORM callbacks
resolve through the application catalog described below.

## Custom entity behaviors

`EntityBehaviorCatalog` resolves names once in application setup. Definitions
carry typed kind, payload layout, immortality, group membership and animation
policy. Recognition alone does not enable custom execution: transform, update
and contact modes are explicit. Unknown names retain source diagnostics and
are omitted from supported execution. Gameplay dispatches only on typed kinds.

`EntityCustomUpdate` sequences detached updates through `EntityFly`,
`EntityCheckpoint` and `EntityBaby`. The fly waits 61 updates, chooses a
checkpoint with shared RNG and appears for 121 updates; position, visibility,
collision and checkpoint bits belong to the transaction. Static noises own
logical moving-sound allocations. Retirement releases sound ownership and
recreation can allocate it again without inventing RNG draws. Checkpoint proximity animation uses the pre-control 3D frog distance, a strict
512-unit radius, ground cel zero and the shared RNG. Jump/inflate/deflate modes
are checkpoint-owned and survive live-instance recreation. Collection updates
the shared checkpoint mask and transactional level flow.

Moving-group membership includes turtles, flies and the baby frog; it is
independent of path ownership. Immortal noise, boundary, baby and fly instances
initialize in authored order. Checkpoints are mortal statics. During each live
visit, retirement precedes custom/script updates. Later visits see earlier
changes; earlier visits see the prior state of a parent not yet visited.
Recreation clears instance scripts, registers, callbacks, deviation, timers,
animation, tint, HIT/CARRY and sound ownership. Persistent paths and immutable
programs survive instance recreation.

## Inspection compatibility

`src/inspection` owns bounded JUN1/ORG1 presets, dependency manifests and
`ExplorationGuard`. These restrictions validate available behavior; they are
not walls or map rules. The generic tick guard rejects and rolls back a
candidate at the relevant phase without changing collision or clamping position.
Generic terrain inspection requires zero-zone retail maps. Whole-map ORG1 setup
loads authored zones and validates dependencies without an exploration guard.
The bounded presets remain regression fixtures, as tracked in
[PORTING](../../PORTING.md).
[Golden specifications](../../../tests/golden/specs/entities.md) own route
coordinates, exclusion geometry, schedules and source comparisons;
[inspection instructions](../testing/terrain-inspection.md) own launch commands.

## Vehicle primitive contacts

The five vehicle types have one first-part cuboid, no primitive matrix and
the SQUISHED death type. `EntityPrimitiveSetup` detaches half extents, local
offset, flags and reaction. `FrogCollisionSetup` detaches every collision
hilite in part/hilite order from partcel zero and all exact discrete action
transforms. It rejects incomplete/interpolated models and collision points on
the imported throat transform. Gameplay retains no source or scene objects.

Collision first applies the current frog-origin sphere gate and source group,
live, hidden, forbidden and NO_COLLISION rules. `EntityPrimitiveQuery` then
tests the stored animated points. It rotates the cuboid offset in owner axes,
narrows the displacement to signed16, applies the transposed owner rotation,
and requires `abs(local) < half_extent` on every axis (`MR_COLL.C:225–274,525–531`).
Fixed12 products use source signed32 accumulation and signed16 matrix/point
stores. LAST/STATIC/DISABLED flags are supported; disabled or missed primitives
continue to the ordinary FORM fallback when data exists. Retail traffic has no
FORM_DATA records: `has_form_data=false` preserves that absence as a miss,
without inventing a grid. General shapes, multiple primitives or primitive parts and borrowed parts reject explicitly.

Animated single-model primitives follow `COLL_B_FLAGS_ANIM`: the first part with
primitives is framed by that part's stored world transform, refreshed after the
entity animation step and kept while the action and actual cel are unchanged, so
the frame keeps the root from the last cel change. A primitive matrix rotates the
point test through `transpose(LW × matrix)` while the offset rotates by the frame
alone, and the matrix translation is ignored. The source collision globals are
never reset, so the transposed rotation is reused while the same frame and matrix
identities recur; the port keeps that cache in the attachment state across
in-level resets. An unrefreshed animated frame reports `UNPRIMED` and misses,
where the source reads uninitialized memory. Retail places such primitives only on
the Jungle plant (part 4, with a matrix) and scorpion (part 0). Facts and
deliberate-break checks are in the
[animated primitive specification](../../../tests/golden/specs/entities.md#animated-primitive-contacts).

The frog is created with `MR_OBJ_STATIC`. Frozen `MR_ANIM.C:1998–2014` retains
stored world transforms when both action and actual cel match, even if the root
moved. `FrogCollisionPose` preserves that cache in each run snapshot. It
also retains the cache while a newly selected action has pending cel -1:
source stored-transform updates skip negative cels (`MR_ANIM.C:1989–1994`).
Selective resets can publish this state before the next animation step.
Collision reads the previous stored pose; refresh happens after final animation stepping
(`gamesys.C:1326–1333`). Inspection reset explicitly primes action 0/cel 0 at
the selected start; it does not claim uninitialized full-engine startup parity.

The first accepted primitive marks HIT, skips that entity's FORM and requests
the form-book death policy. Source scanning continues, retaining the first killer. Arcade squish
zeros the root matrix's Y row, including on a later hit in the same scan.
The next entity update observes HIT and requests the named traffic splat sound.
FORM fallback SQUISHED does not apply primitive-only flattening. All hits,
cached points, death, camera, animation, scripts and RNG commit together or
roll back together. Primitive contacts identify the entity, part and hilite.
Jump-from-primitive state skips entity scanning until its source flag clears.
Squish particle creation and removal, tyre sprites, local ordering tables and
audio playback remain presentation/effect boundaries; no race-mode or full
effect simulation is claimed.

## Pink frog behavior

The pink frog (`ORG_BABY_FROG`, distinct from the five checkpoint frogs) follows
frozen `ent_org.c` search/wait, parent loss, attachment and six-tick FORM hops.
Her parent may retire and recreate. Her supported contact model is a primitive-free flipbook
with a USABLE-only FORM and no collision or bonus callback. Source sphere and strict FORM bounds record HIT without
mounting Frogger on her. Hidden presentation does not suppress source contact.

The next entity visit consumes HIT and replaces the log parent with player 0,
using the source `(0,-20,-20)` local offset. Subsequent visits follow the frog's
pre-control pose and restart the hop animation on its six-tick riding timer.
Repeated HIT while riding does not restart pickup. Drowning requests made during
entity updates become DYING at control; the pink frog therefore hides on her
next visit, records the dead flag and emits one logical `death_pgen` request.
The inactive state remains hidden. All continuation fields and requests share
the run transaction; pickup and parent changes collapse presentation history.

Checkpoint delivery emits its reward once at the next source entity visit.
Tongue, reward and selective-reset behavior is described below. [Independent evidence](../../../tests/golden/specs/entities.md#scripted-visibility)
and [inspection commands](../testing/terrain-inspection.md#scripted-org1-visibility)
cover the supported pickup, riding and death behavior.

## Supported script components

`EntityScriptSetup` resolves supplied programs and the `CallbackNames` bank,
copies the reachable named branch closure and validates both the authored
turtle script and its named non-diving replacement. Turtle register payloads
retain their three words after PATH_INFO; static noise retains two words after
the matrix. Application setup resolves callback names into typed callback kinds;
gameplay never dispatches on those names or executable addresses.
`SUB_TURTLE` keeps its identity while sharing the generic path transform.

`EntityScriptDefinition` validates instruction widths, operand modes, register
indices, action indices, callback kinds, branch targets and balanced single
loops. Program names provide source identity, not an execution allowlist. Validated
programs include turtle/log behavior, five traffic program/SFX pairs,
two noise programs and the original-theme snake/crocodile scripts. Unsupported instructions and malformed
or non-yielding programs fail explicitly. Definitions retain no source data.

`SCRIPT_IF RANDOM` consumes shared RNG before branching. NEW_SCRIPT retains
the original root for RESTART and clears loop pointers. The frozen linked C
ENDLOOP yields, while the vendored reconstruction returns CONTINUE; gameplay
follows the frozen C behavior. STOP retains callbacks and unsigned16 timer
increments. ONCE does not invent a called-bit write. Script callback names and
per-build FORM callback addresses remain separate namespaces.

Control flow also supports animation/path-end waits, direct/random sounds,
timer loop exits, path pause/resume, END and conditional NEW_SCRIPT/GOSUB/return.
END applies that tick's deviation, callbacks and timer before returning to the
single saved GOSUB frame or becoming inactive; inactive scripts do not advance.
Nested GOSUB overwrites the one source return slot. RESTART uses the root retained across branches; START_SCRIPT can change it. NO_CONDITION is a no-op for branches; ALWAYS branches. Path-end
waits use bounce/repeat flags, excluding one-shot hit flags. Pause affects the
next path update and is committed with the entity candidate. STOP_DEVIATE
retains offsets/deltas; CLEAR_DEVIATE clears them. Suppressed random sounds
consume no RNG; sound IDs and divisors narrow to signed16.

`RETURN_GOSUB_IF RANDOM` remains rejected: frozen C reads `script[3]` despite
this instruction having one declared operand. No adjacent-word read is invented.
Its END_OF_PATH condition falls through in C, unlike SCRIPT_IF. Path scripts support three-axis rotation, rotation waits/stops and immediate or
register-based deviation in all six signed directions. Conditions inspect all
three counts. Angular duration updates mask to 12 bits; destination updates
compare signed16 values before masking the reached destination. Rotation composes
X, Y, Z onto the current path pose before world-space deviation. Matrix-mode scripts premultiply the authored rotation by source X/Y/Z rotation
and translate from the authored position. Static entities using path-mode scripts
retain their live matrix between visits, including after END. Matrix mode requires
an authored matrix payload; path payloads are not reinterpreted as matrices. `RETURN_DEVIATE REGISTERS NEG_COORD_X` is rejected:
frozen C uses `coord > NEG_COORD_X` on that branch, indexing outside its three
axis fields for equality. The literal branch uses `coord > COORD_Z` and is safe. The new control-flow and death-policy facts are independent
Python implementations of frozen C; they have not been run through a native C
component adapter. Existing Python/C corpora remain unchanged.

All 25 names in the supplied callback bank have component implementations;
script dependencies still gate execution. Helium-balloon callbacks resolve their
rising program by name and clear loop cursors without replacing the restart root.
Dive callbacks consume CARRY in slot order; frog deaths and notifications retain
their source order within the aggregate transaction. Static dive colour uses the
authored Y position. Path fish/hippo colours use the path height. Callback support
does not admit an otherwise unsupported program or other-theme entity.

START_SCRIPT changes the RESTART root but continues the current instruction
stream, matching the source's overwritten script-pointer assignment. The three
AWARD_FROG instructions are source no-ops. CHANGE_ENTITY_ANIM narrows its action
to signed16 and respects animated/display state. MUTATE_MESH_COLOR uses the live
height before deviation. KILL_SAFE_FROG retains death/sound ordering.
HOME_IN_ON_FROG preserves the source register-or-literal distance test, YX basis,
strict range and near-target snap; dying/checkpoint frogs are excluded.

Appearance and collision instructions change live entity flags transactionally.
Live flags can clear authored NO_COLLISION; standalone probes still combine their
supplied flags with authored defaults. APPEAR writes the saved script position
before motion, so matrix-mode translation subsequently replaces it. Checkpoint
selection consumes one chance draw and, on success, one start-index draw. It
searches uncollected checkpoints and preserves the source's assignment of
NO_COLLISION rather than treating it as an occupancy test. Collected, fly-covered
and collision-disabled masks are distinct; collection uses the shared collected mask.

EJECT_FROG performs ordered forced jumps or zero-duration freefall. Moving-sound
pitch bend emits a logical request; POP retains its 32-tick source lifetime.
Register payload admission and sprite operands retain their explicit bounds; a supported opcode
name does not mean every operand combination or model is admitted.

`EntityRun` owns `EntityScriptState` and `EntityAnimationState`, including
cursors, six registers, callback slots, three-axis signed16 motion, unsigned16 timer,
colour/ambient state and logical moving-sound ownership. SET_ACTION resets cel
to -1 even for the current action; pose advancement uses supplied lengths.
`EntityScriptRunner` returns private state/RNG copies, ordered request parameters
and a drowning effect. A failure returns none of those candidate changes.
Existing script-free APIs remain available. Audio playback stays deferred;
splashes draw as [effects](../rendering/effects.md). [Component goldens](../../../tests/golden/specs/entities.md#entity-script-components)
cover interpreter edge cases independently of the retail route.

The aggregate runs custom/script updates before frog control, using
previous-tick hit/carry flags. Drowning reaches that tick's control phase.
Ordered observations retain each visit before transient flags clear; entity
animation advances after frog animation scripts. Failed later phases discard
requests, clocks, colours, RNG and checkpoint covered bits together. Transform-only baby updates require a live parent; scripted visibility uses the
full parent loss/search behavior. Bounded fixtures reject checkpoint interactions
outside their admitted dependencies.
Presentation reads committed entity actions/cels and hidden state.
ORG1 draws the diving callback's blue tint through the
[model lighting](../rendering/README.md#model-lighting) path.
Dying attached frogs retain source platform carry before death velocity and
reassert CARRY for the next entity update. A deep turtle clears that flag on
each visit; repeated death requests do not repeat the accepted death or effect.

## Whole-map single-player coverage

The existing independent `exe_forms.tsv` inventory has 23 GENERAL and 25
ORIGINAL forms for `pc-retail-v3.0e`. GENERAL selects STATIC, CHECKPOINT,
BONUS_FLY, MULTIPOINT, GEN_TOP_LEFT, GEN_BOTTOM_RIGHT and GEN_GOLD_FROG.
ORIGINAL selects STATIC, MOVING, SUB_TURTLE, STATIC_NOISE, ORG_FLY,
ORG_BABY_FROG, ORG_BEAVER, ORG_CROC_HEAD and ORG_LOG_SNAKE. MULTIPOINT is
excluded with an explicit multiplayer-only diagnostic. Generic pickups, gold
frogs, beavers, crocodile heads and log snakes have typed runtime components.
Generic pickup bobbing and rewards use the source frame clock. Pitch RNG requires
an allocated logical voice; whole-map setup loads supplied sound tables and bank
durations to resolve that gate. Voice allocation, completion, radius changes and
entity retirement commit with gameplay. Rendering and audio-device completion
never control the gate; see [logical sound](simulation.md#logical-sound-clock).

Executable disassembly verifies these six v3.0e identities against frozen C.
The application resolves addresses to names and then typed callback kinds;
gameplay never dispatches executable addresses. FrogLord may repoint a form
to any of these verified callbacks. Unknown mappings remain excluded with
source-located diagnostics. Text-only code digests and function lengths are in
[the callback facts](../../../tests/golden/pc-retail-v3.0e/form_callbacks.json).

| Form | Kind | v3.0e address | Frozen C name |
|---|---|---|---|
| GEN_STAT_COL_BLOCK | Collision | 0x428390 | GenBlockCollPrimCallback |
| GEN_STAT_WATER_FALL_BLOCK | Collision | 0x4287A0 | GenBlockWaterFallCollPrimCallback |
| GEN_STAT_FALL_BLOCK | Collision | 0x4287C0 | GenBlockFallCollPrimCallback |
| ORG_FLY | Bonus | 0x4231D0 | OrgFlyCallBack |
| SUB_BUTTERFLY | Bonus | 0x4284E0 | GenButterFlyCallBack |
| CAV_FIREFLY | Bonus | 0x43D060 | CavFireFlyCallBack |
| JUN_OUTRO_DOOR, JUN_OUTRO_GOLD_DOOR, SWP_CRUSHER, SWP_CRUSHER2 | Collision | 0x4241C0 | SwpCrusherCallback |

All other GENERAL/ORIGINAL callback fields are zero in that inventory; the Cave web wall collision callback (0x43CF20) is unmapped because no retail map places it.
Compatibility verification currently targets v3.0e, including FrogLord-saved
edits based on that build. v1.0 and Vogons verification is outside scope and
does not block ORG1 implementation or P8c acceptance. Do not infer FORM callback
identity from the script CallbackNames bank.


## Tongue and rewards

Stationary, centring, grid-slip and simple-slip control start the tongue with
sound 20, as does live jumping control. Freeform slip starts it silently when no
direction is held. A tongue already in effect is never restarted.

Tongue selection follows the source 3×3 group walk, signed-short distance and
strict nearest comparison. Normal and super radii are 640 and 1152 units.
Landscape obstruction uses GRID.C's tile walk and the first three vertices of
each square. A one-step ray checks only its starting cell, as in frozen C.
Out-of-storage lookups reject the transaction.

The effect extends for eight ticks, grabs for four (eight without a target),
then retracts for eight. Retraction evaluates the source fixed-point Bezier
against the target's current pose each tick. Collection hides the target and
applies its typed bonus callback or supplied pickup reward once. Effects run
after animation updates and before visibility; rendering cannot advance them.
Tongue state, rewards and target mutations are private until the tick commits.

SCORE_BOOK values and flags come from the supplied v3.0e table at 0x472B80,
verified from AddFrogScore's table access. Source flag precedence is retained.
AddFrogPoints compares the signed score against an unsigned life threshold;
therefore a negative score can award a threshold life before REDUCE clamps it
to zero. A call awards at most one threshold life and wraps scores above
99,999,999 by subtracting that value once. Lives cap at ten.


Selective level resets follow `ResetPathRunners` and `ResetEntities`: FORM bit 3
selects reset on checkpoint and bit 4 selects reset on death. FrogLord calls
these flags “don't reset”; frozen C tests the bits positively and resets when
set. Gameplay follows C. Paths reset before instance retirement and retain the
current authored-entity NO_MOVEMENT flag. Unselected instances retain scripts,
animation and generation. Retired immortals are recreated in authored order;
other instances wait for visibility. The global committed tick clock survives.
Frog reset preserves velocity, jump target, input, buffered direction storage,
scale, death fields and no-input/animation counters while clearing active
modifier and buffer counts. Its facing basis resets to a cardinal direction.

Whole-map setup for ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 resolves every authored dependency, including custom contact
execution, before creating a run. Explicit bounded fixtures retain their disabled
neighbors even when those neighbors now have supported primitive definitions.
Collected checkpoint recreation uses the shared collected mask: the source omits
the animation and sets hidden, no-display and no-collision flags. Uncollected
checkpoint recreation clears those flags. Golden-frog recreation also preserves
collection across selective resets.

Live entities track source model presence separately from animation. Recreated
collected checkpoint and gold-frog instances have no model: primitive checks
miss, while FORM fallback remains eligible (`collide.c:445`).

Normal single-player play uses the single-start bounce. The logical start HUD waits for the
first bounce, consumes one random phrase selection, then runs the five staggered
checkpoint gather/scatter clocks and the timer count-up. The count-up includes
its source overshoot before clamping to the authored time. Rendering completion
never releases play. Attract playback retains its separate fast-reset start.
During checkpoint HUD transitions, the super-hop pressed edge supplies the source
BLUE/FR_GO input. Gather, bonus and return consume it in that order; bonus skip
awards only remaining whole seconds, plays the croak request and commits once.
A later transaction failure restores both the award and transition clock.
Simultaneous tongue/directional input on a `NO_ENTITY_ANGLE` platform is rejected:
the frozen source indexes its four direction vectors with the unmasked input.

### Broader level dependencies

`GameplaySetup` selects map, theme, logical sound banks and model resources from
the supplied executable. Whole-map play rejects unresolved required dependencies;
inspection keeps its diagnostic omissions. Missing fade-bound markers retain
frozen `mapload.C` defaults of ±32767; either authored marker overrides its corner.
SUB1 has no markers. Primitive-free single-model skeletal resources may use FORM
contacts, their source model-set maximum Y and global animated bounding-box
radius. A valid model with no FORM data or collision primitives contributes no
contact. These broader model cases are opt-in for whole-map setup. Animated collision
primitives on one part are supported as described under
[vehicle primitive contacts](#vehicle-primitive-contacts).

Suburbia dogs follow `ent_sub.c`: unsigned postdecrement wait, endpoint pause,
one walking RNG draw even at bounced ends, fall-before-hit arbitration, and a
50-tick biting continuation. Biting changes the frog matrix using the prior dog
pose, without changing its authoritative position or repeating FORM death.
Logical bark/bite requests participate in the same transaction. Moving tongueable
entities retain path movement and tongue eligibility. Dynamic entities are
immortal and join moving-group ordering despite their matrix payload.

For MOVING entities running `SCRIPT_TURTLE`, frozen loader behavior reserves three
zeroed register words after the 12-byte path payload. Setup reproduces that narrow
policy rather than reading adjacent entity bytes. Other truncated register
payloads fail. Original-theme turtle splash commands use form-specific offsets;
other themes request one splash at the entity origin. Rendering splashes remains
deferred.

Butterfly callbacks read their unsigned type at payload offset 12 and select a
reward through the supplied score table. That callback payload and reward are
separate from a generic pickup's own type/reward, including when a saved form
repoints either callback role. Truncated records and invalid types are rejected
during setup; collection commits the reward and hidden state together.

The pinned JUN1 bank/log fixture continues to omit moving tongue collectables
from its collision aggregate, with a diagnostic. General transform inspection
can recognize those entities without expanding that fixture's proven behavior.

### Forest

FOR1 and FOR2 use whole-map setup. FOR3–FOR5 are dummy retail entries and FORM
is multiplayer. Hives, breaking branches, squirrels and hedgehogs resolve from
FrogLord names into typed custom behaviors; existing scripts handle owls, river
noise and squirrel sounds. Unsupported dependencies still reject whole-map play.

Hive swarms activate near a controllable frog, chase over terrain, mill behind
live tree-stump FORMs and return home. The source visibility query samples a
ray in sixteen-unit steps, checking the active frog before live stumps; stump
XZ bounds are inclusive and do not use normal frog-contact height gates. The
source Forest stump-form list is retained. Swarm speeds use `WORLD_SHIFT=8`;
the chase cap compares the authored speed directly, while return compares it
shifted by eight. Shared active-swarm count, positions, angles, sound ownership
and pitch RNG commit with the entity/frog transaction. Hive creation and return
preserve the source's count reset and postdecrement behavior.

Breaking branches use the previous hit, an unsigned postdecrement delay and
source gravity/rotation. Breaking disables collision and releases an attached
frog into freefall before control; impact requests the existing logical pop.
Squirrels pause paths at bounced endpoints until their turning action ends;
the authored delay does not alter animation cadence because the corresponding
source assignment is disabled. Hedgehogs switch speed/action at authored timer
and animation boundaries; rolling path repeats restart running. FOR2 hedgehogs
project onto the first terrain layer during updates, retaining source height and slope math without
renormalizing the projected forward axis. Creation keeps the path pose;
`ALIGN_TO_WORLD` suppresses projection.

`FOR_SWAYING_BRANCH` follows the active frozen entity-book mapping: static
creation with a dynamic model and no sway update. Disabled historical sway code
is not executed. Falling-leaf behavior is not admitted by this phase's retail
maps. Compatible edits can select implemented behaviors; unknown mappings retain
diagnostics.

The bee swarm is a visible lethal hazard, so its three original textured sprites
are included here with the gameplay rules. Whole-map
setup requires the named `for_swarm` image from the player's general/theme banks.
Presentation draws committed swarm positions with the source camera-plane
orientation and never advances gameplay or consumes gameplay RNG. Swarm quads
carry no ordering-table bias yet; see [depth ordering](../rendering/README.md#depth-ordering).
Other particles and pop visuals are [effects](../rendering/effects.md); audio playback remains separate work.

## Volcano whole-map behavior

VOL1–VOL3 admit named moving platforms, colour switches and falling platforms,
alongside existing scripted mechanisms, furnaces, lava sprays, spinners and
noise emitters. VOL4/VOL5 have no playable retail map; VOLM remains multiplayer.
The generic `TRIGGER` behavior, which the unplaced `VOL_SWITCH` form shares, is described under [Sky whole-map behavior](#sky-whole-map-behavior).

Moving platforms are immortal path followers. Switches resolve their ordered
signed target IDs against authored identities, initialize target movement on
their first update and toggle or reverse live paths through the same candidate
transaction as contact. Duplicate authored IDs and missing or incompatible
target payloads reject whole-map setup. Frozen C's FREEZE and START operations
both toggle; debounce and the four switch states preserve repeated-contact
behavior. Logical moving-sound ownership follows movement without audio playback.
Switches and falling platforms have no C static flag: contact traversal links
them with moving entities in reverse authored order. The switch callback nudges
the frog matrix from its stored target height without rewriting fixed-point
position; later contacts and jumps read that matrix height. This ordering lets
a switch callback affect a platform contact within the same tick.

Switch models use the frozen colour-to-WAD-slot dispatch through the player's
map book and archive. Per-instance models supply animation and primitive data;
shared FORM height/radius still come from the form-book model. Presentation
consumes committed flipbook actions and paused texture cells. FrogLord disables
colour editing for PC, while frozen C implements all nine colour selections;
this port follows frozen C behavior. The saved payload follows FrogLord's
56-byte layout, excluding the extra trailing field in the C structure.

Falling platforms count prior HIT flags with source-width wrapping, wait using
the authored post-decrement delay, then start a one-shot animation and disable
collision. An attached frog falls in the same transaction. The authored matrix
does not descend. Paused polygon texture animation retains its current cell;
switches explicitly select their on/off cell. Reset and recreation restore
source initial state. Independent transition facts and deliberate-break checks
are documented in the [entity golden specification](../../../tests/golden/specs/entities.md#volcano-entities).

## Cave whole-map behavior

CAV1, CAV3 and CAV4 use whole-map setup. CAV2 and CAVM are dummy map-book rows
and CAV5 has no map. Spiders, vampire bats and snails are generic path followers
with existing scripts; glow worms and other pickups are generic `BONUS_FLY`
records. Rockfall floor, bat, cobweb, web wall, lava drop, slime, rope bridge
and race snail forms are not placed in retail maps and remain unsupported with
diagnostics.

The frogger light (`CAV_FROGGER_LIGHT`) is an immortal model-free entity whose
payload gives minimum and maximum radii in grid squares and a die speed. Setup
precomputes the unsigned squared radii `(radius<<8)²` and the per-tick decay
`(((die<<8)/30)²)>>8`, rejecting min ≤ 1, min ≥ max and max > 255. Creation
seeds the shared radii: the maximum, and the maximum less 0x100000, or 1 when
unsigned wrap would exceed the maximum. Each visit crops an enlarged light back
to its maximum, then subtracts the decay while the maximum exceeds the squared
minimum radius, recomputing the minimum the same way (`ent_cav.c`). The radii
live in `EntityEnvironmentState` so rewards, callbacks, fade and presentation
read one committed value. The light form has no reset bits and no source reset
path touches the radii, so they persist across deaths and checkpoints. Light
pickups add `value<<16`; the firefly callback (`0x43D060`) scores 250 and adds
the raw constant 8 to both radii, reproduced literally.

On cave-light maps every live entity without `NO_SCREEN_FADE` or `NO_DISPLAY`
is colour-scaled after its own visit and before its transient flags clear, using
the XZ squared distance to the frog against the radii as they then stand: 128 at
or inside the minimum, 0 at or beyond the maximum, and the integer ramp between,
with unsigned comparisons (`ENTITY.C FadeLiveEntity`). Models multiply existing
scale colours when `RESPECT_SCALE_COLOURS` is set and otherwise take the grey
directly; `NO_MODEL` sprite forms take `min(128, grey<<2)` unless the form's
don't-fade flag or `NO_COLOUR_FADE` is set. An applied scale sets
`colour_scaled`, so an applied black is distinct from an unscaled entity.
Creation performs no fade, matching the source skip on Cave maps; the non-cave
edge fade remains unimplemented. The fat fire fly's form fades in C against a
particle generator object; the port records the colour and the pickup glow
ignores it.

Fireflies (`FIREFLY`) are tongueable path followers drawn as source sprites;
gameplay owns their path translation. The fat fire fly (`CAV_FAT_FIRE_FLY`) is a
static tongueable pickup at its authored translation, bobbing by
`rsin(((uid&7)<<7)+(frame<<8))>>5` on the source frame clock unless
`NO_MOVEMENT`, drawing one RNG value per update and requesting the buzz sound
through the shared `PlaySoundDistance` gate when `rand()%20==1`. It rewards
through its fly type like generic pickups; type 9 is super light.

Source disagreement: the executable and frozen `formlib.C` give `CAV_SNAIL` the
STATIC entity type, while FrogLord's entity names override it to MOVING and the
CAV3 records carry PATH_INFO. Frozen `mapload.C` creates path runners only for
path-runner entity types, so retail reads those bytes as a matrix. The port
follows the FrogLord name and reports a non-omitting `entity_override`
diagnostic. The player croak (`FrogCroak`, frozen `FROG.C:2941-3042`) starts
on the croak key outside recorded demos: it saves both light radii, adds
`max/6` to each for six ticks, holds four and subtracts for six while the
source `Cav_light_switch` suspends the light's decay, then restores the radii
and either sets the nearest uncollected checkpoint's croak mode or plays the
gold frog's croak. Gameplay commits the throat scale (0x200 to 0xC00) for
presentation. The web wall is a FORM callback no retail map places (see
above), not an effect. Independent facts and
deliberate-break checks are in the [entity golden specification](../../../tests/golden/specs/entities.md#cave-entities)
and the [effects specification](../../../tests/golden/specs/effects.md).

## Desert whole-map behavior

DES1–DES5 use whole-map setup; DESM has no map. Lizards, beetles, bison and
birds are generic path followers with existing scripts, the butterfly is a
generic tongueable with the mapped butterfly callback, and cacti are generic
statics. Seven Desert forms have typed behaviors below. Thermals, the
earthquake, salamanders, holes, noise emitters and the second bird are not
placed in retail maps and remain unsupported with diagnostics. No Desert form
has a collision callback and no theme-specific terrain, camera, lighting or
effect code exists in frozen C. Desert camera selections can exceed the
conservative polygon bound, so DES levels enable the same source allocation
history as Volcano.

Falling rocks (`DES_FALLING_ROCK`) are immortal matrix entities whose payload
holds twelve targets, each an `MR_SVEC` with its pad word followed by an
unsigned time and pad, then the delay, bounce count, flags and sound. Setup
snaps each used target's X and Z to its cell centre and takes Y from the
terrain height selected by the authored Y, unless the authored flags already
say `TARGETS_RESOLVED`; the source `while(i--)` loop lifts target 0 by 0x80,
not the last target. The rock checks for one tick, waits `delay+1` ticks on
its first cycle only, then flies `time+1` integration steps per target under
`UpdateEntityWithVelocity` (gravity 0x2d800, then velocity added, position
truncated) with axes from its velocity and an X roll of −0x60 per tick, drawn
0x80 above the integrated position. Each landing requests the bounce sound;
the last requests the break sound, hides the rock mesh and starts the
explosion overlay: the per-level model WAD slot 1 flipbook (`DES_FALLING_ROCK`
model, sixteen cels), drawn at identity rotation at the landing position. The
rock resets to the delay state with timer 0 after the last cel, so it is hidden
for one tick, then launches again. Collision never toggles and the roll angle
never resets. Rolling rocks (`DES_ROLLING_ROCK`) are immortal path followers
rolling −0x40 per tick; when their path repeats they place the same explosion
at the previous tick's position, pause the path, disable collision and hide the
mesh until the overlay's last cel. Both rocks keep the source shadow-visible
state, which the shadow view draws ([effects](../rendering/effects.md)).

Tumbleweeds (`DES_TUMBLE_WEED`) follow their path in X and Z and own their Y:
when the hop count reaches zero they draw `rand()%4+6`, set
`vy = −((0x100000·(n+1))>>1)` and restart from the path height, otherwise
gravity 0x100000 accumulates and `vy>>16` adds to the height. They roll −0x60
per tick, request a looping moving sound from creation and hide their shadow
on the outermost grid cells. Snakes (`DES_SNAKE`) measure `DistanceToFrogger`
from a point 512 units ahead: under 256 units, facing the frog within ±64 of
its lane, they bite; 256–512 units they rattle with its sound. A path bounce
selects the turning action, sets `NO_MOVEMENT` and pauses the runner with a
hold count of 19, which skips runner updates on the next 20 ticks; the resume
update also selects normal, overwriting any request held through the turn.
Vultures (`DES_VULTURE`) switch on the requested action: a path tangent Y above
−128 requests the swoop and its moving sound, below −128 requests normal, and
exactly −128 changes nothing.

Croc heads (`DES_CROC_HEAD`) are immortal platforms with rise height and speed,
snap, pause and submerged delays and a snap flag. They start submerged and
deadly, rise safely, pause, then either snap (deadly for ten ticks with one snap
sound) when the flag is 1 or pause again, then fall without clamping, so they
overshoot the start height before pausing submerged again. Every wait compares
with equality, so a zero delay never fires and DES5's 65535 snap delay holds
that croc at its pause. While deadly and carrying the frog they request the
munch sound and a BITTEN death each tick. Cracks (`DES_CRACK`) count landings:
each hit writes texture cel `3−(hops_before−hits)` before incrementing the
unsigned byte count and requests the crack sound, which has no visible effect
on the PC model because it has no texture-animation targets. At `hops_before`
the fixed two-then-decrement wait starts the one-shot flipbook on the next tick
with the hole sound; when it finishes, collision turns off and an attached frog
free-falls; the crack then sinks 0x140000 per tick until Y reaches 1024,
scaling its colour by `max(0, ((y0−y)>>3)+0x80)` only on sinking ticks. The
authored fall delay and the rock's entity sound are never read in C.
Independent facts and deliberate-break checks are in the
[entity golden specification](../../../tests/golden/specs/entities.md#desert-entities).

## Jungle whole-map behavior

JUN1 uses whole-map setup. JUN2 is the ending stage: frozen `gamesys.C` starts
it directly in the end-of-game mode and it has no checkpoints, so it stays
outside gameplay setup with the end sequence, videos and credits. JUN3–JUN5 have
no maps and JUNM is multiplayer. The executable enables no Jungle attract demo.
Frozen C also sends a completed JUN1 into the end-of-game mode (camera to the
door, door opening, a level restart waiting for the statue); the port keeps the
level-complete flow until that phase and records the disagreement here.

Logs, turtles, monkeys, rhinos, crocodiles, piranhas, porcupines and the other
movers are generic path followers with existing scripts, the butterfly is a
generic tongueable, water noise is a modelless static with its script, and the
trees and flowers are generic statics. The outro set loads so the map admits:
the modelless `JUN_OUTRO` controller keeps its eleven camera targets and times,
both doors are statics whose collision primitive runs the crusher callback,
plinths select the level WAD model by `op_id` (0 selects slot 58, 1–7 slots
0–6), gold frogs use the general gold-frog flipbook and are hidden unless
`op_id` is 8, which shows the EXCITED action, and stone frogs are statics. The
statue glow and the hippo splash are [effects](../rendering/effects.md). `JUN_OUTRO_STATUE`, floating trees and `JUN_CRACK` are never placed and
remain unsupported with diagnostics. JUN1's map counts 2665 polygons, so camera
selections can exceed the conservative bound and JUN1 enables the same source
allocation history as Volcano and Desert.

Plants (`JUN_PLANT`) are immortal matrix entities with a snap time and delay.
Waiting holds cel 0 with stepping off; a frog within 356 units of the point
measured by `DistanceToFrogger` arms the snap timer, `!(timer--)` starts the
animation, requests the snap sound through the 30-unit distance gate and sets a
15-tick sound repeat; when the animation finishes the delay runs with the same
repeat, then cel 0 and waiting return. The animation is not one-shot, so it
cycles until the delay expires. The plant kills only through its animated
collision primitive with the SQUISHED death. Rope bridges (`JUN_ROPE_BRIDGE`)
are immortal platforms created with stepping off, one-shot animation and
collision on; each tick carrying a hit increments the unsigned byte count, and
reaching `hops_before` loads the unsigned wait, which fires after
`fall_delay + 1` ticks, then starts the animation, disables collision and drops
any rider into a fall. Hippos (`JUN_HIPPO`) carry the Suburbia turtle payload;
type 1 swaps the root to `SCRIPT_JUN_HIPPO_NO_DIVE`, so JUN1 hippos dive and
JUN2 hippos do not. Scorpions are generic movers whose part-0 primitive gives
the FLOP death. The bouncy mushroom is a static with a one-shot animation; its
retail FORM is a plain safe square, so the FORM bounce (forbid the entity, snap
to its origin, forced two-cell fifteen-tick jump) is reachable only through
FrogLord edits and synthetic facts.

The door callback runs the non-Swamp `SwpCrusherCallback` handler: it looks at
the first square of the stack one cell opposite the frog's direction and, when
that square is usable, either sends a normal-mode frog back with
`JUMP_TO_LAND | JUMP_FROM_COLLPRIM`, the reversed direction, six jump ticks,
the source vertical velocity and a translation push, or re-targets a user-mode
frog over `FROG_JUMP_TIME` ticks. The source loop never advances the square
pointer, the user-mode branch writes a crusher count through the door's absent
runtime data (the port omits that write); the Swamp branch is described under
[Swamp whole-map behavior](#swamp-whole-map-behavior). Independent facts and deliberate-break checks are in the
[entity golden specification](../../../tests/golden/specs/entities.md#jungle-entities).

## Swamp whole-map behavior

SWP1–SWP5 use whole-map setup. SWPM is multiplayer with no map. The
executable enables all five Swamp attract demos; they complete with schedule
parity, and SWP1 and SWP5 match native traces per tick (SWP2–SWP4 have no
native baseline). SWP1, SWP2, SWP4 and SWP5 exceed the 2500-polygon budget, so
every Swamp level enables the source allocation history as Desert does.

Oil drums, newspapers, pallets, raccoons, mutant fish, pelicans, oil, waste and
chemical barrels are generic path followers with their existing scripts and
callbacks; the three noise forms are modelless statics with register payloads;
boxes, sunk cars, pipes, trees, logs, litter, marsh, the fridge and the tyre
are generic statics. The bobbing waste barrel is a `DYNAMIC` static whose
script reads one register (its delay) after the matrix, and the nuclear
barrel is an immortal generic path mover whose script reads two registers
(jump distance and time) after `PATH_INFO`, waits for a rider, plays the
geiger loop, ejects the frog with those registers and pops. Frozen
`ENTSCR_PREPARE_REGISTERS` copies any count up to the six `si_registers` from
`sizeof(PATH_INFO)` or `sizeof(MR_MAT)`, so register payloads are admitted at
offset 12 for path entities and 32 for matrix entities with one to six
registers. SWP4 slugs, SWP5 slugs and the SWP4 mutant fish carry
`LOCAL_ALIGN`, applied as described under the transform rules above. Half the
SWP3 presses carry `ALIGN_TO_WORLD`, which matrix entities ignore.

Acid squirts (`SWP_SQUIRT`) are immortal matrix entities with a one-off delay,
a drop time and a target. The signed delay counts down while positive, then
preparation computes a 16.16 velocity from the current translation to the
target with truncating division by the drop time, requests the acid-drip sound
when `DistanceToFrogger` is below 1536, and falling adds `velocity >> 16` each
tick until the post-decremented signed timer was at or below zero, when the
authored matrix is restored and the cycle repeats without the delay. A zero
drop time divides by zero in the source and is rejected at setup. The squirt
kills through its FORM with the SQUISHED death.

Crushers (`SWP_CRUSHER` and `SWP_CRUSHER2`) and presses (`SWP_PRESS`) share
one payload: signed speed, distance, direction and delay. Both wait with an
unsigned post-decremented timer, so motion starts `delay + 1` ticks after
creation, then move `speed >> 8` per tick. A crusher rams along the map axis
its direction names (north and east add, south and west subtract) until the
translation passes the authored origin plus or minus the distance, then
returns until it passes the origin; its ambient crush loop plays at 768/1280
and its debounce count decrements every tick. The press does the same on Y
(up subtracts first, down adds first) and, on the return flip, plays the
frog-crush sound when it carries the frog and otherwise the crusher sound
within 1536; its machine loop plays at 768/1280. Both carry the frog through
their FORM; the crusher form is THICK with the SQUISHED death and runs the
Swamp branch of `SwpCrusherCallback` from its collision primitive, while the
press has a primitive and no callback.

The Swamp crusher callback returns while the crusher's count is nonzero and
otherwise sets it to five. The frog's cell comes from its world position and
the bounce direction opposes the dominant axis of its velocity (ties go to Z);
a frog with no horizontal velocity falls through to the non-Swamp handler,
which uses the stored cell and reversed facing. The first square of the
target stack must be usable; a user-mode frog is re-targeted over
`FROG_JUMP_TIME` ticks and the count becomes four (frozen C writes that count
through the door's absent runtime data too; the port writes it only here), and
a normal-mode frog is sent back as the Jungle doors do. Afterwards, in Swamp only, the frog's
translation is moved into the crusher's local frame and, when it lies inside
the first FORM data grid between the form height and `fo_max_y`, a DEADLY
square kills with SQUISHED. The retail crusher FORMs reach their deadly
squares through the ordinary FORM reaction as well.

Rats (`SWP_RAT`) are immortal matrix entities with a speed and four targets.
Creation divides the speed by 30, measures each leg with the integer square
root of the squared distances, derives the two jump times as length / 30 and
the run time as length / speed, the `<< 4` velocities by truncating division
and the sine steps as 2048 / time; zero times are rejected at setup, as is a
squared distance that wraps the source 32-bit sum negative, which frozen
`SquareRoot0` would read as unsigned. A negative or over-65535 run time never
matches the unsigned count, so such a rat runs forever, and each jump ends
short of its target because the last sine sample precedes the increment and
the step truncates; both follow the source. The rat
restarts at the start target with scale colours 0x80 and white ambient, holds
one idle tick selecting the one-shot JUMP action, jumps along a sine arc of
height 250 subtracted from the integrated Y, selects the one-shot ROLL action
for 24 ticks, runs with the looping RUN action, jumps again and restarts.
During the second jump the first tick at or above Y -255 sets the splash flag
and magenta ambient, and the splash sprite draws from the splash event.
Rats die to the frog with FLOP and their script plays a random distance sound.

Slugs (`SWP_SLUG`) are immortal generic path movers whose payload adds a
motion type; type 1 selects the curvy flipbook action at creation. The weir
(`SWP_STAT_WEIR`) is an immortal matrix static whose creation replaces the
authored rotation with a 1024-unit Z rotation before the model is built, and
whose script rotates it about X forever. The green Swamp drowning tint from
frozen `FROG.C` is committed by `FrogTint` and drawn as [effects](../rendering/effects.md).
Independent facts and deliberate-break checks are in the
[entity golden specification](../../../tests/golden/specs/entities.md#swamp-entities).

## Sky whole-map behavior

SKY1–SKY4 use whole-map setup. SKY5 and SKYM are dummy rows with no map. The
executable enables all four Sky attract demos, each gated on SKY1 being
unlocked, so the fresh-boot native export never reaches them; see the
[testing guide](../testing/README.md#diagnostics-demo-playback-and-native-comparison) for the
baselines obtained from a scratch store. Every Sky map fits the 2500-polygon
budget, so source allocation stays off.

Sky forms are driven by their frozen scripts through existing machinery. Jets,
biplanes, birds, the little bird, the popping bird, flocking birds, the small
bird, the tornado object and the cloud platform are `MOVING` path followers
whose scripts play moving sounds and random frenzied calls; helicopters, rubber
balloons, the helium balloon, the hawk and the birdhawk are `DYNAMIC` matrix
entities whose scripts read two or three registers after the matrix (the
helicopter's deviation distance and speed, the hawk's homing speed and range,
the balloons' unused operands), deviate on Y, pop and eject the frog into
freefall; clouds, the cloud patch, the banner and the modelless cloud platform
are statics. The hawk's script switches its entity type to PATH, so its homing
translation accumulates instead of resetting to the authored matrix each tick.
The map sets `ALIGN_TO_WORLD` on the SKY3 cloud platforms, which path movers
honour. The low-poly WAD slot for `SKY_CLD_PATCH` is a dummy, and the low-poly
maps place none.

The SKY3 squadron (`SKY_SQUADRON`) is a `MOVING_PLATFORM` with a plain
12-byte `PATH_INFO` payload; frozen `ENTSTR_MOVING` has no initial-movement
field, which belongs to the 16-byte Volcano platform record consulted only by
the colour switch, so the decoder accepts both widths and the chain sound
stays Volcano-only. The squadron is authored with `NO_MOVEMENT` and starts
paused.

The magical popping balloon (`SKY_FROGGERS_MAGICAL_POPPING_BALLOON`) is the
only retail `TRIGGER` entity: a 56-byte record holding the matrix, a u32
trigger type (0 FREEZE, 1 REVERSE, 2 START, 3 BEGIN) and ten s16 target
unique ids (−1 unused); the authored frame count that follows in frozen
`ENTSTR_TRIGGER` is never read and FrogLord does not save it. It is immortal
and resets on death and checkpoint. On its first update after creation every
listed live target gets `NO_MOVEMENT` and its path runner is deactivated;
targets not yet created are skipped. Its collision primitive is a FORM
primitive running `TriggerEntityCallback`: FREEZE and START toggle the targets'
movement, BEGIN clears `NO_MOVEMENT` and reactivates the runner only where it
was set, and REVERSE clears the runner's BACKWARDS flag in both branches of the
frozen source, so it never reverses (recorded as a source disagreement with the
intent FrogLord names; retail uses only BEGIN, with the SKY3 balloon releasing
the squadron). A missing target is a frozen assertion and a transaction error
here. The callback then forbids the balloon for frog collision and sets
`JUMP_FROM_COLLPRIM`. The balloon's own script pops it and plays the helium pop
when the frog hits it, and the poly-piece pop draws from `pop_allocated`
([effects](../rendering/effects.md)). Target flags live on the map entity, so a squadron
released before a death stays released until the recreated trigger's first
update pauses it again.

Frozen `UpdateSkyLand` drifts the sky backdrop from the shared `MRrand` stream
every 128 frames of the global `Game_timer`; the port owns that drift in
gameplay state, as described under
[simulation](simulation.md#sky-drift-and-the-global-frame-timer). Independent
facts and deliberate-break checks are in the
[entity golden specification](../../../tests/golden/specs/entities.md#sky-entities).
