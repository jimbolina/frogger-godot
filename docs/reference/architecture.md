# Architecture and ownership

## Dependencies

- `src/source/` decodes source facts, with file I/O where needed. Classes derive
  from `RefCounted` and depend on neither Nodes/tree access nor conversion,
  gameplay, scenes or presentation.
- `src/game/` contains `RefCounted` definitions and exclusively owned terrain,
  path, entity, camera, animation-control and RNG state.
  It receives validated definitions and tick commands from setup adapters;
  it does not depend on source readers, conversion or presentation, open files,
  poll input, consult wall time or access Nodes. Godot math types are allowed.
- `src/application/` owns source-to-game adapters. They resolve source names
  and supply concrete dependencies. Direct environment access is restricted to
  explicit loader adapters; source readers retain ownership of file I/O.
- `src/inspection/` owns scenarios, validated options, corridor guards, presets
  and manifests. Presentation translates CLI/environment inputs into explicit
  options. Gameplay and application never depend on inspection.
- Conversion builds render resources from decoded data. Presentation owns
  scene lifetimes, input translation and drawing. `MapSceneData` is a rendering
  dependency bundle, not the future world's authoritative state.
- Simulation uses direct calls for ordered updates. Notifications follow
  state changes; subscriber order must not decide collision outcomes or RNG use.
  Rendering interpolation cannot feed back into authoritative state.

The [domain glossary](domain.md) gives semantic boundaries. Existing
[simulation](gameplay/simulation.md), [coordinates](rendering/coordinates.md) and topic references
remain authoritative for detailed rules.

## Gameplay state

`RunSnapshot` composes `FrogState` (movement, control, timers and collision pose),
`AttachmentState` (platform-local coordinates and contact identities),
`TickRequests` (logical requests and counters) and `TickDiagnostics` (provenance
and observations). Each value has a complete detached copy contract. Systems,
entity state, the RNG seed and the tick identity remain at the transaction level.
Lives are a frog state value; applying life-decrement requests remains game-flow work.
`TerrainTrace` flattens this structure into the existing wire schema, including
the historical `fixture_lives` key. Runtime consumers use the composed records.

## Current lifetimes

`GameData` owns its archive, decoded executable tables and caches. Treat shared
decoded objects as read-only after construction. Closing it closes its archive;
retained decoded records do not make later archive reads valid.

Viewer `open_data(game_data, take_ownership = false)` borrows by default. The
caller must keep borrowed data open until every consumer has detached. A viewer
that opens its own data passes `true`, closes it when replaced or exiting, and
releases its drawing resources. Reattaching the same object never closes it or
silently relinquishes ownership. Do not transfer ownership to multiple viewers.

Meshes/materials belong to their rendering bundle or instance according to the
existing conversion APIs. Instance animation clocks are separate from shared
model definitions. Source replacement clears selections, caches and drawing
references before another source is shown. Standalone viewer entry points and
synthetic injection remain supported.

`TerrainRun` copies setup definitions and owns frog, camera, animation and RNG
state, plus an optional `EntityRun` supplied through `EntityCollisionDefinition`.
Each command operates on private candidate copies and commits only on success.
Entity/path advancement builds its next independent state directly. The entity aggregate exposes `begin_candidate`, detached snapshots and ordered
update methods; the gameplay aggregate never accesses its private state.
`commit_candidate` consumes the successful candidate only after all phases pass.
Intermediate observations and public results deep-copy mutable state. Prepared script
definitions detach caller inputs and validate animation/form/path dependencies
once, retaining bounded runtime cursor and instruction-budget checks. Standalone
script calls validate supplied definitions on every call. A dependency mismatch
uses that safe validation path. Private candidate script execution may update its
owned state and RNG directly; any subsequent failure discards the whole candidate.
Interactive playback assigns the run to a dedicated `TerrainTickWorker`.
The scene host retains the 30 Hz input pacer and original stall policy, permits
one outstanding command, and consumes only detached completed results. Drawing
uses the last completed samples while a transaction runs. Pause/step drains the
pending command; reset, source replacement and exit join the worker before
replacing or releasing the run. Deterministic trace captures execute synchronously.
Timing instrumentation belongs to this presentation worker, never gameplay classes.
`TerrainMotion` converts previous/current committed transforms once per tick.
Frog, entities and camera use one render fraction; a rider retained on one
platform interpolates in that platform's local frame. Transfers use continuous
world transforms. Identity or generation changes collapse entity history and
the history of a retained rider and camera. Reset, source
replacement, pause/step, rejection and explicit `reset_interpolation()` for
seek/teleport collapse all histories. Rendering never mutates committed samples.
Part transforms and compatible morph cels share this fraction; texture frames,
visibility and action changes use the current tick. Environment UVs and sky
translation follow the interpolated camera while gameplay retains its integer camera.
Snapshots are detached, including nested entity/path and camera/animation state.
Component fixtures explicitly omit unrelated systems; integrated inspection
supplies camera defaults and copied high-detail frog action lengths. Entity
paths/transforms advance before frogs; eligible FORM reactions run after terrain
collision and before camera/animation. A terrain collision early return suppresses
the entity phase too. Only the final aggregate commit publishes matching frog and
entity ticks, per-tick hits and requests. Failed reset or tick preserves every
owned component and returns no partial phase snapshots or outcomes.
`TerrainRun.step` captures diagnostic phases by default. Interactive playback
disables that capture: it still commits the same detached final state, contacts,
requests and RNG, but omits intermediate snapshots and ordered entity-update
observations. Trace recording always enables them. Retail tests compare both
paths over the complete source-verified ORG1 routes.

Optional visibility lifecycle adds a final camera-to-group selection and live
creation/renewal phase after animation, before commit. Its pure selector and
owned live-list state depend only on detached group facts and camera snapshots.
Late selection or polygon-budget rejection rolls back the same aggregate.
Persistent paths outlive live instances. Admitted scripted lifetimes initialize
immortals before the first tick and run retirement/custom/script visits in live
order, retaining previous parent poses until their own visit. Authored slots never compact when
instances disappear; live membership gates collision and attachment lookup.
The [entity contract](gameplay/entities.md#visibility-lifecycle) owns eligibility,
source ordering, attachment retention and reset semantics. Presentation consumes
generations to allocate/release instances; it cannot select the authoritative
live set. Existing all-attached inspection remains the default.
Active zones can participate in this transaction: visibility consumes the
updated candidate camera, and a late rejection restores the prior zone and
camera along with the entity state. Prescribed retail camera probes use the
same detached camera/entity components with private candidates; they do not
add teleport commands or bypass gameplay admission in `TerrainRun`.

Opt-in platform execution requires an integrated camera. The order is paths,
source-ordered entity transforms and admitted custom/script updates, frog
control, movement, modifiers, terrain collision,
sequential primitive/FORM reactions, camera, animation scripts, pose, then aggregate commit.
The scan caches its neighborhood and forbidden authored identity; each candidate
uses the current attachment and position, so a SAFE transfer affects later
candidates. Camera transitions and fall requests belong to that same candidate
transaction. Missing attachment identities, invalid matrices and unsupported
commanded destinations fail without publishing contacts, carries or requests.
Reset clears current/forbidden links and transient observations. Detached
platform helpers retain no source objects or live scene references.

`LevelDefinition.tick_guard` is an optional `TickGuard`. Its `check(phase, candidate)`
receives detached state at each existing validation boundary. Entity snapshots
are supplied at the entity-update checkpoint; other checkpoints observe frog state. `ExplorationGuard`
in inspection owns corridor rectangles, zones and animated contact restrictions.
The run copies the guard and validates setup before accepting any state.
Spawn/reset must satisfy both guards. During a tick, the zone query uses the
source grid cell after movement and before modifiers/collision. World X/Z is
checked there, before each FORM query, after each FORM reaction/correction and
before aggregate commit. A rejection discards the frog, entity/path, camera,
animation, RNG and every candidate outcome. It neither clamps nor publishes a
partial contact. `ZoneSetup` converts source records; pure `ZoneQueries` owns
matching. Active zones are separately supplied through `LevelDefinition.camera_zones`.
Frog selection (zone and region) and camera-consumed identity are detached
transaction state; selection occurs here once, not again after contact correction.
Empty active definitions preserve existing runs. The JUN1 setup adapter verifies
the independent admission manifest before enabling its all-attached preset.
ORG1 additionally pins supplied behavior names and the animated frog collision
point closure; its guard validates admitted actions, roots and unpowered state
before contacts and commit. Excluded contacts require that guard, while their
admitted logical updates remain live. Setup rejects changed proof dependencies.
The viewer pauses on rejection. R reconstructs the whole inspection, including
input buffers and presentation clocks, while retaining the selected input mode.

The ORG1 road preset additionally owns detached frog collision definitions and
`FrogCollisionPose` in `RunSnapshot`. Previous stored probes are read during
collision; action/actual-cel changes refresh them at the final pose phase.
Definitions, cached samples and primitive diagnostics are deeply copied across
publication boundaries. Late failure discards them with every other candidate
field. Rendered and interpolated model transforms never drive collision.

`RunSnapshot.attachment.entity_cell` and `entity_offset_16` are platform-local. `target_16`
is local while attached or jumping within the entity frame, and world-space
for a terrain target; derived inspection destinations convert it accordingly.
After departure into freefall, the inactive local target remains a source fact
while inspection reports the frog's current world cell.
Attachment, forbidden, hit and carry identities use authored indices with `-1`
for absent links. Relative matrices and camera modification state are copied.

`TerrainGridSetup` copies decoded geometry, flags and scalar source identities
into grid definitions; those definitions retain no source or rendering objects.
Treat definitions as immutable after setup. Grid queries return new result
objects and do not retain or mutate caller state.

`PathSetup` copies source-ordered PATH geometry and source identity into
`PathDefinition`, without retaining the decoded map. It omits unsupported or
unsafe paths with source-located diagnostics while retaining valid neighbors.
`PathRunner` copies its definition and initial settings, owns one mutable
cursor and returns detached snapshots. `PathInspection` owns only sampled
drawing resources. The map viewer frees its overlay and runner on map/source
replacement; the common 30 Hz clock drives map animation and the selected
path. `EntitySetup` resolves supported STATIC/MOVING records into detached
definitions and source-located diagnostics. `EntityRun` owns copies and a path
cursor for each moving entity, with aggregate commit on success and detached
snapshots. Standalone all-attached transform inspection remains available;
integrated `TerrainRun` owns its own independent mutable state. Transaction
copies of `PathRunner` and `EntityRun` share their private, validated definitions
read-only; creation still detaches all caller-owned inputs, and cursors, scripts,
animation, requests and lifecycle state remain independently mutable.
`FormContactSetup` copies FORM flags and resolved model bounds into one
definition per supported base entity, after considering every authored model
writer in source order. `FormContactQuery` consumes that definition, an entity
snapshot and one world point without changing run state. The viewer owns the
selected probe and drawing resources. `EntityCollisionSetup` composes these
definitions with copied map-group facts and reaction eligibility. Pure
`EntityContactOrder` and `FormReaction` select traversal and outcomes; the run
applies those outcomes to its candidates. No source object, callback address,
scene object or subscriber controls rule execution. Fixed-point contact inspection
remains independently available without affecting the frog.
See [paths](gameplay/paths.md) and [entities](gameplay/entities.md).

## Extending behavior

The bounded script components keep per-entity cursors, registers,
callback slots, deviations, action/colour state and logical moving-sound
ownership in `EntityRun`. Each `EntityScriptRunner` update returns detached
script/animation state, RNG, ordered requests and a frog effect; failures
discard all candidate outputs. `EntityScriptSetup` supplies decoded named
programs and callbacks, including turtle creation's script replacement.
`TerrainRun` owns frog reactions, shared checkpoint covered bits and commit.
Admitted pink frog updates receive the candidate frog pose/mode and previous HIT;
their owned carrier/timer/death state commits with the same aggregate. Presentation
consumes the resulting pose and hides the dead frog without deciding pickup.
Snapshot and contact-scan order stay
separate from the source live-update order.
The [entity contract](gameplay/entities.md#org1-admission) owns the
expanded behavior closure and source proof. General inspection remains
script-free; admitted definitions opt into these updates.

The aggregate clones frog and shared state before entity updates. It visits
entities in descending all-attached live order, executes custom/script updates,
applies frog effects and shared writes before the next entity, records the visit,
then clears transient flags at the source point. Ordered requests and logical resource ownership
are candidate state, even with playback/rendering deferred. A failed later
contact or guard discards them alongside script timers, animation clocks,
colours, checkpoint flags and RNG. Entity animation advances in the aggregate
pose phase; presentation consumes committed actions and cels. Existing
script-free APIs retain their behavior.

1. Find the source rule under the [source policy](sources.md).
2. Name its inputs, owned state, units and observable outcomes.
3. Add an asset-free example to the owning feature's unit tests.
4. Connect the setup adapter and named supported implementation.
5. Compare independent reference facts/traces and expose actionable diagnostics.

`EntityBehaviorCatalog` resolves FrogLord names in setup into a detached
`EntityBehavior`. Gameplay dispatches on its kind and uses its layout,
immortality, map-group movement and animation capabilities. Execution selection
keeps transform-only inspection separate from enabled updates and contacts.
Unknown names retain the existing diagnostic-and-omission fallback; recognizing
a supported kind does not enable unsupported interactions. Fly, baby-frog and
checkpoint updates have separate modules behind the typed dispatcher.

Implementing another original behavior is a code change. A mod only repoints
data to already supported behavior. Keep raw identifiers for diagnostics;
never dispatch executable addresses directly.

## Automated checks

Both test wrappers compile scripts, check architecture, then run tests and
validate their results; see [testing](testing/README.md). The architecture scanner
checks protected code and its statically discoverable dependencies, including
project class names, literal script paths and inherited bases. It reports
computed loads and dynamic calls for review. Gameplay runtime resource loading
is file I/O; literal preloads of permitted script definitions are allowed.

The scanner also rejects entity-name comparisons, membership tests and match
dispatch in gameplay, while permitting raw names in diagnostics.

This is a conservative static check, not a complete GDScript parser or proof of
runtime purity. It does not resolve local type scopes, inner-class aliases or
dependencies embedded in serialized resources. Identifier shadowing and reflective
code require human review; comments and unrelated strings are excluded. Ordinary
data methods such as `FrogLordConfig.add_child()` are allowed. Keep dependencies
explicit instead of obscuring them to pass the check. Hosted CI remains deferred.

## Copy ownership

Definitions detach mutable caller inputs at construction. Private definitions
may be shared read-only between candidate runs; publicly mutable definitions
and observations retain defensive copies. State and nested containers are
independently owned. The discovered value-copy contract test populates every
script field and verifies equality and mutation isolation in both directions;
new field types require an explicit test sampler. Runtime owners with contextual
copy semantics retain their component transaction tests.
