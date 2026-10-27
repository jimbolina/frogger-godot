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

Invalid form/name, matrix or PATH_INFO, missing/unsupported path, bad start,
unknown entity flag bits and `LOCAL_ALIGN` omit only that entity.
`PROJECT_ON_LAND` is supported for whole-map hedgehog updates; other unimplemented
projected transforms remain omitted. Diagnostics include source/build/resource, authored index, form and
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
corners and adds 100, matching frozen `mapload.C`. Default contact supports a static
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
Checkpoint and bounce reactions remain diagnosed and omitted; SAFE requires the platform capability below. Unusable squares do
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
owns the retail probe and source comparisons. Entity-specific sliding/bouncing
and multiplayer stacking remain unsupported. Verified v3.0e FORM callbacks
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
without inventing a grid. General shapes, primitive matrices,
multiple cuboids and bounce reactions reject explicitly.

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
Existing script-free APIs remain available. Audio and splash rendering stay
deferred. [Component goldens](../../../tests/golden/specs/entities.md#entity-script-components)
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

Executable disassembly verifies these five v3.0e identities against frozen C.
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

All other GENERAL/ORIGINAL callback fields are zero in that inventory.
Compatibility verification currently targets v3.0e, including FrogLord-saved
edits based on that build. v1.0 and Vogons verification is outside scope and
does not block ORG1 implementation or P8c acceptance. Do not infer FORM callback
identity from the script CallbackNames bank.


## Tongue and rewards

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

Whole-map setup for ORG1–ORG5, SUB1 and FOR1–FOR2 resolves every authored dependency, including custom contact
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
contact. These broader model cases are opt-in for whole-map setup. Animated collision primitives
remain an explicit unsupported dependency.

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
are included here rather than deferred with decorative particles. Whole-map
setup requires the named `for_swarm` image from the player's general/theme banks.
Presentation draws committed swarm positions with the source camera-plane
orientation and never advances gameplay or consumes gameplay RNG. The existing
renderer uses depth buffering rather than the source ordering-table bias.
Broader particles, pop visuals and audio playback remain separate work.
