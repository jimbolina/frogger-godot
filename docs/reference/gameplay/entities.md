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
are retained as flags; the default component attaches every supported
record. The opt-in visibility lifetime below narrows that set. Script and callback
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
default does not reproduce.

## Visibility lifecycle

`EntityCollisionDefinition.lifecycle` opts an integrated run into bounded
single-player live-entity creation. Null preserves all-attached inspection.
Setup admits zero-zone maps and script-free generic STATIC/MOVING entities.
Script-bearing records retain source identity and inspection poses but never
enter the supported live set. Custom/immortal behaviors, scripts, zones and
selective checkpoint/death resets remain deferred. Existing FORM/model and
collision-callback exclusions still govern collision; bonus callbacks remain
unexecuted diagnostics.

`TerrainRun` advances persistent paths, culls/updates live entities, runs frog
and camera/animation phases, then selects and expands visible groups before
the aggregate commit (`gamesys.C:1322–1350`). Reset has no ordinary live
instances and does not prewarm visibility. End-of-tick creation first becomes
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
conservative guard proves `CreateMapGroups` visits the whole list without
reproducing renderer allocation history; equality is unsupported. Selection or
budget failure rejects the entire tick rather than approximating the live set.
`mapdisp.c:413–435,454–478,962–977` owns this boundary.

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
integrated run. General inspection excludes nonzero scripts from reaction
execution because frozen `ENTITY.C` runs scripts before frog collision.
The guarded ORG1 adapter supplies its verified script closure instead.
Geometry remains inspectable.
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
DEADLY, SLIPPY, then BOUNCY in that order. The default mode implements POPDEATH and
DEADLY with form-book death type POP. Higher-priority unsupported branches never
fall through to POP. Other deaths, checkpoint and bounce reactions are diagnosed
and omitted; SAFE requires the platform capability below. Unusable squares do
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
the next tick completes the jump with terrain-style grid-flag reaction order.
Usable no-op and existing POP destinations remain supported; they are not
reclassified as SAFE. The special count-one path reasserts HIT outside the FORM
reaction, even if that reaction rejects a now-vertical SAFE surface.

Departure searches terrain using camera controller directions; NO_ENTITY_ANGLE
uses a world target. Angled departure without terrain retains the entity frame
until jump completion, whereas NO_ENTITY_ANGLE detaches immediately. Departure
caches the forbidden identity; terrain landing clears it. The
[camera contract](gameplay-camera.md) owns projection and correction behavior.

The high-detail JUN1 inspection starts explicitly on water cell `(18,5)`, facing
NORTH and pressing NORTH at command tick zero. It is not a verified route from
safe terrain. Its independently predicted first JUN_LOG contact is command tick
3 / advanced entity tick 4 and is verified through the complete ordered scan.
The [golden specification](../../../tests/golden/specs/entities.md) owns the
retail facts and reproduction. Runtime evidence is specifically v3.0e.

Outside the opt-in visibility mode above, this inspection still assumes
all-attached lifetime. Scripts, active zones, primitives, checkpoints,
entity-specific sliding/bouncing, callback dispatch and multiplayer stacking
remain outside this slice. Bonus callbacks remain unexecuted diagnostics without
independently blocking collision. This does not complete P8 or make a level playable.

## Guarded JUN1 bank route

The opt-in `jun1-log-bank` preset uses audited high-detail v3.0e resource 656.
It starts safely at cell `(22,10)`, world `(2176,-324,-4992)`, facing west.
The independently calculated route uses logical WEST mask 8 at command tick 0
and EAST mask 2 at tick 12. Contact at tick 3/entity tick 4 mounts JUN_LOG
authored index 24, unique ID 11, offset 13532, FORM 45/grid 1. Eight ticks of
centring/carry lead to departure and a detached, alive terrain landing at
`(22,9)`, height -180, on tick 17. Observation continues through tick 59.
The original PC input masks are LEFT 1/RIGHT 2; `TickCommand` uses its existing
normalized cardinal encoding. The camera mapping is independently verified.

World admission is X `[1900,2304)`, Z `[-5376,-4864)`. The initially proposed
west edge 1856 is unsafe: hippo 23 can contact `(1856,-256,-4924)` at advanced
entity tick 27. Exhaustive integer path/FORM evaluation bounds hippo contacts
in this Z band at X 1888. The revised boundary excludes them without changing
retail collision. Complete path cycles, transformed FORM extents, sphere and
primitive precedence, shared FORM writers and custom movement determine the
other exclusions. Only logs 16,24,25,26,27,31 can contact this rectangle.
All 18 zones are decoded; the demonstrated cells activate none.

The exclusion proof covers ordinary inspection controls from a fresh run, with
no tongue pickup or external outro transition. `ENTITY.C:1018–1056` land
projection changes Y/orientation, preserving the rhino/monkey path XZ. Scorpion
creation delegates generic movement (`ent_jun.c:1149`). Hippo dive/rise changes
only Y (`ent_jun.c:354–367,372+`); all five share the same primitive-free model,
FORM and repeat path. All 17,398 integer path poses bound flat-pose contact X
at 1888; the 932 nearby tilted poses have Y-independent local X, bounded at
1789. Crocodile 0 has no primitives in any animated component; its action,
timer and sound script does not move the root (`ent_jun.c:542–557`). All 6,105
path poses bound its FORM Z below -5632.28. Crocodile 19 is sphere-excluded.

Plants change animation/timer/audio only (`ent_jun.c:59–179`); bridge collapse
changes animation/collision enablement, retaining the root. Plinths, stone
frogs and doors have null updates (`ENTlib.C:415–461`). Outro gold frogs start
SITTING, whose update is a no-op (`ent_jun.c:783–794,841–870`). Checkpoints and
markers stay at authored origins. Those fixed records are sphere-excluded;
tree 109 and mushroom 110 instead have identity roots, no primitives and
strict FORM minimum X of 2561 and 2570. Animated primitives are tested only
after the bounding sphere, so excluded models need no primitive simulation.
Shared FORM writers resolve to the audited matching models.

Every NO_MODEL record has a null collision callback, taking the early skip in
`COLLIDE.C:272–286`; the flag alone is insufficient. Bonus flies bob only in Y
and cannot collect themselves (`ent_gen.c:257,329`). Complete path and fixed
origin checks keep XZ differences within signed16 and their squared sum at
most 152,901,121. Adding any signed16 Y square remains below signed32 overflow
(1,226,642,945), making sphere exclusions valid even for wrapped source Y.

The frozen adapter retains all 115 authored scan identities. Six potentially
contacting logs execute normally; other identities are explicit proof-excluded
null-live shells, justified by the exhaustive geometry/behavior proof. This
does not simulate their custom scripts or RNG/audio. The runtime still scans
every admitted generic entity in source order. Its independent admission
manifest pins determining map, form/behavior, script and model facts, including
WAD mappings and incomplete-model counterparts. Changed dependencies reject
this preset; ordinary inspection remains available for mods.

All-attached lifetime is explicit and visibility mode is rejected. Guards
roll back and pause attempts to leave the world rectangle or activate a zone.
R restores the entire inspection; it does not implement checkpoint/death reset.
Scripts, active zones, custom/immortal behavior, verified form callbacks,
selective reset, additional reactions, primitives and broader lifecycle work
remain P8 work. Scoring, progression and win conditions are not part of this
demonstration. Reproduction belongs to the existing
[golden specification](../../../tests/golden/specs/entities.md).

## ORG1 admission

The independent proof admits high-detail v3.0e ORG1 (resource 658) within
X `[-512,512)`, Z `[-128,480)` for a single unpowered frog and uninterrupted
all-attached lifetime. The guarded `org1-turtle-log-bank` preset validates the
proof before enabling scripts or excluding contact. The proof pins map, source-ordered form/behavior rows, script
streams, model mappings, counterpart models and the selected frog resource in
`src/presentation/setup/org1_exploration_admission.json`.

Starting at cell `(10,7)`, world `(128,-256,-128)`, north, normal NORTH commands
at ticks 0 and 12 and SOUTH commands at 34 and 46 connect turtle 1, small log
13 and turtle 2. Contacts occur at 3, 18 and 39; the frog returns detached and
alive to the starting bank cell at 51. Observation through 729 includes
repeated dive/rise cycles. A separate bank wait and NORTH at 1230 attaches to
diver 0 at 1233; its depth callback kills the carried frog at 1254, before
that tick's control phase. Neither route edits paths or forces attachment.

All four first-lane turtles and six small logs remain contact candidates.
Complete integer path/FORM bounds exclude second-lane turtles and larger
logs. Shared FORM writers agree; THICK_FORM precedes UNIT_FORM. Static
neighbors have explicit sphere, NO_COLLISION or null-callback NO_MODEL
exclusions. The baby frog's actual creation and first update leave it hidden
in WAIT_TO_SEARCH_AGAIN with search count 1. Its parent log remains live
forever under this lifetime contract. The five checkpoints remain outside
the 512-unit croak trigger and 640-unit tongue radius. Their complete-model
counterparts supply their real flipbook lengths.

Traffic requires animated collision-point exclusion. The old research
minimum Z `-224` is not admitted. For the narrower rectangle, every integer
orientation on both support paths generates a finite closure of 36 frog
roots, including terrain normals, four headings, inherited up axes, snapping,
centring/carry and linked departures. All generating transitions match frozen
`UpdateFrogMatrix`, `SnapFrogRotationToMatrix` and projection operations.
Every hilite on every collision-bearing part and reachable action cel of
`GEN_FROG.XAR` (214), including initial action 0/cel 0, is composed with those
roots using source fixed-point and short stores. The southernmost world probe
is -294; the nearest cuboid accepts points only through -316. Expanded probe
XZ differences and squared-distance sums stay within source widths even
with any signed16 Y difference. Croak's imported throat part has no hilites.
SAFE landing-height differences stay below the stun threshold; death and
MUST_DIE return before primitive scans. No nearby collectable can introduce a
powerup or tongue scaling. Stored root origins must stay inside the rectangle
at every collision scan; escaping candidates must reject before contact.

Geometric exclusion never removes a global update. All 64 identities retain
their paths and logical custom/script state, with descending live updates
from ascending all-attached creation. Contact scans retain every authored
identity in source group order, with hidden moving records unlinked. The ten
admitted FORMs are collision-live in
the C transport; other identities are explicit contact exclusions.

Traffic indices 24–47 execute their five root and five named `_SFX` programs.
`SCRIPT_IF RANDOM` consumes shared RNG before its branch; NEW_SCRIPT preserves
the original root for RESTART and clears loop pointers. The linked port's
ENDLOOP yields, unlike the vendored reconstruction's CONTINUE. STOP retains
callbacks and unsigned16 timer increments; ONCE never gains an invented
called write. Resolve script callbacks by FrogLord names, separately from
form-callback executable addresses. The closure adds SCRIPT_IF and
SCRIPT_CB_FROG_TRAFFIC_SPLAT to the turtle/log subset.

The bonus fly retains its 61-update wait, random checkpoint selection,
121-update appearance, position, visibility/collision flags and covered-bit
writes. Static noises retain logical moving-sound allocations. The real
allocation component verifies suppression, reuse, owner clearing and
recreation without RNG draws. Audio playback and splash rendering remain
ordered requests, with sound IDs/radii and sprite offsets/flags verified.
They do not claim full engine voice/effect RNG equivalence.

The route adapter executes unchanged path, script, custom creation/update,
frog, collision, camera and animation functions. Decoded model metadata
replaces renderer allocation; distinct sprite storage prevents fly/splash
aliasing. A mesh instance records actual colour writes. Retail action lengths
replace synthetic animation lengths. Independent Python compares the six
frog phases and every ordered entity update, including previous-tick HIT/
CARRY flags, callback slots, deviations, requests, colours, animation and RNG.
Root/probe math is checked separately; no GDScript output defines expectations.
[Golden reproduction](../../../tests/golden/specs/entities.md#org1-route-proof)
owns commands and schemas. Active zones, selective reset, primitive execution,
checkpoint collection and full-level flow remain outside this slice.

## Bounded script components

`EntityScriptSetup` resolves supplied programs and the `CallbackNames` bank,
copies only the supported branch closure and validates both the authored
turtle script and its named non-diving replacement. Turtle register payloads
retain their three words after PATH_INFO; static noise retains two words after
the matrix. Neither callback numbers nor executable addresses dispatch code.
`SUB_TURTLE` keeps its identity while sharing the generic path transform.

`EntityScriptDefinition` validates instruction widths, operand modes, register
indices, action indices, callback names, branch targets and balanced single
loops. The supported closure is the turtle/log programs plus the five traffic
program/SFX pairs and two noise programs. Unsupported instructions and malformed
or non-yielding programs fail explicitly. Definitions retain no legacy data.

`EntityRun` owns `EntityScriptState` and `EntityAnimationState`, including
cursors, six registers, callback slots, signed16 deviations, unsigned16 timer,
colour/ambient state and logical moving-sound ownership. SET_ACTION resets cel
to -1 even for the current action; pose advancement uses supplied lengths.
`EntityScriptRunner` returns private state/RNG copies, ordered request parameters
and a drowning effect. A failure returns none of those candidate changes.
Existing script-free APIs remain available. Audio and splash rendering stay
deferred. [Component goldens](../../../tests/golden/specs/entities.md#entity-script-components)
cover interpreter edge cases independently of the retail route.

The aggregate runs admitted custom/script updates before frog control, using
previous-tick hit/carry flags. Drowning reaches that tick's control phase.
Ordered observations retain each visit before transient flags clear; entity
animation advances after frog animation scripts. Failed later phases discard
requests, clocks, colours, RNG and checkpoint covered bits together. The bounded
background branches preserve bonus-fly timing/RNG and the baby frog's permanent
live-parent invariant; checkpoint croak/contact and parent retirement reject.
Presentation reads committed entity actions/cels and hidden state.
ORG1 draws the diving callback's blue tint through the bounded
[model lighting](../rendering/README.md#model-lighting) path.
Dying attached frogs retain source platform
carry before death velocity; they do not reassert live carry flags.
