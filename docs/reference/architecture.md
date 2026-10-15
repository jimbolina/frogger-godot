# Architecture and ownership

## Dependencies

- `src/legacy/` decodes source facts, with file I/O where needed. Classes derive
  from `RefCounted` and depend on neither Nodes/tree access nor conversion,
  gameplay, scenes or presentation.
- `src/game/` contains `RefCounted` definitions and exclusively owned terrain,
  path, entity, camera, animation-control and RNG state.
  It receives validated definitions and tick commands from setup adapters;
  it does not depend on legacy readers, conversion or presentation, open files,
  poll input, consult wall time or access Nodes. Godot math types are allowed.
- Setup adapters belong with their first real consumer. They resolve source
  names and supply concrete dependencies; no container or global world is needed.
- Conversion builds render resources from decoded data. Presentation owns
  scene lifetimes, input translation and drawing. `MapSceneData` is a rendering
  dependency bundle, not the future world's authoritative state.
- Simulation uses direct calls for ordered updates. Notifications follow
  state changes; subscriber order must not decide collision outcomes or RNG use.
  Rendering interpolation cannot feed back into authoritative state.

The [domain glossary](domain.md) gives semantic boundaries. Existing
[simulation](gameplay/simulation.md), [coordinates](rendering/coordinates.md) and topic references
remain authoritative for detailed rules.

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
Snapshots are detached, including nested entity/path and camera/animation state.
Component fixtures explicitly omit unrelated systems; integrated inspection
supplies camera defaults and copied high-detail frog action lengths. Entity
paths/transforms advance before frogs; eligible FORM reactions run after terrain
collision and before camera/animation. A terrain collision early return suppresses
the entity phase too. Only the final aggregate commit publishes matching frog and
entity ticks, per-tick hits and requests. Failed reset or tick preserves every
owned component and returns no partial phase snapshots or outcomes.

Optional visibility lifecycle adds a final camera-to-group selection and live
creation/renewal phase after animation, before commit. Its pure selector and
owned live-list state depend only on detached group facts and camera snapshots.
Late selection or polygon-budget rejection rolls back the same aggregate.
Persistent paths outlive live instances. Authored slots never compact when
instances disappear; live membership gates collision and attachment lookup.
The [entity contract](gameplay/entities.md#visibility-lifecycle) owns eligibility,
source ordering, attachment retention and reset semantics. Presentation consumes
generations to allocate/release instances; it cannot select the authoritative
live set. Existing all-attached inspection remains the default.

Opt-in platform execution requires an integrated camera. The order is entity
paths/transforms, frog control, movement, modifiers, terrain collision,
sequential FORM reactions, camera, animation scripts, pose, then aggregate commit.
The scan caches its neighborhood and forbidden authored identity; each candidate
uses the current attachment and position, so a SAFE transfer affects later
candidates. Camera transitions and fall requests belong to that same candidate
transaction. Missing attachment identities, invalid matrices and unsupported
commanded destinations fail without publishing contacts, carries or requests.
Reset clears current/forbidden links and transient observations. Detached
platform helpers retain no legacy objects or live scene references.

`LevelDefinition.exploration_guard` is nullable; null preserves existing runs.
`TerrainRun` validates and deep-copies its world rectangle and zone definitions.
Spawn/reset must satisfy both guards. During a tick, the zone query uses the
source grid cell after movement and before modifiers/collision. World X/Z is
checked there, before each FORM query, after each FORM reaction/correction and
before aggregate commit. A rejection discards the frog, entity/path, camera,
animation, RNG and every candidate outcome. It neither clamps nor publishes a
partial contact. `ZoneSetup` converts legacy records; pure `ZoneQueries` owns
matching. No mutable active-zone state exists. The JUN1 setup adapter verifies
the independent admission manifest before enabling this all-attached preset.
The viewer pauses on rejection. R reconstructs the whole inspection, including
input buffers and presentation clocks, while retaining the selected input mode.

`RunSnapshot.entity_cell` and `entity_offset_16` are platform-local. `target_16`
is local while attached or jumping within the entity frame, and world-space
for a terrain target; derived inspection destinations convert it accordingly.
After departure into freefall, the inactive local target remains a source fact
while inspection reports the frog's current world cell.
Attachment, forbidden, hit and carry identities use authored indices with `-1`
for absent links. Relative matrices and camera modification state are copied.

`TerrainGridSetup` copies decoded geometry, flags and scalar source identities
into grid definitions; those definitions retain no legacy or rendering objects.
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
integrated `TerrainRun` owns its own independent copy.
`FormContactSetup` copies FORM flags and resolved model bounds into one
definition per supported base entity, after considering every authored model
writer in source order. `FormContactQuery` consumes that definition, an entity
snapshot and one world point without changing run state. The viewer owns the
selected probe and drawing resources. `EntityCollisionSetup` composes these
definitions with copied map-group facts and reaction eligibility. Pure
`EntityContactOrder` and `FormReaction` select traversal and outcomes; the run
applies those outcomes to its candidates. No legacy object, callback address,
scene object or subscriber controls rule execution. Fixed-point contact inspection
remains independently available without affecting the frog.
See [paths](gameplay/paths.md) and [entities](gameplay/entities.md).

## Extending behavior

The planned ORG1 script transaction keeps per-entity cursors, registers,
callback slots, deviations, action/colour state and logical moving-sound
ownership in `EntityRun`. `TerrainRun` owns the shared RNG, frog reactions,
checkpoint covered bits required by the bonus fly, and aggregate commit.
Setup supplies decoded programs/callback names, checkpoint positions and an
explicit live-update order; snapshot order and contact-scan order stay separate.
The [entity contract](gameplay/entities.md#org1-admission) owns the
expanded behavior closure and source proof. This interface is planned, not
implemented by the current script-free run.

Clone the frog and shared state before entity updates. Visit each entity in
live order, execute its script/custom update, apply callback frog effects and
shared-state writes before advancing to the next entity, then clear transient
flags at the source point. Ordered requests and logical resource ownership
are candidate state, even with playback/rendering deferred. A failed later
contact or guard must discard them alongside script timers, animation clocks,
colours, checkpoint flags and RNG. Never approximate excluded entities with
fixed RNG draws or dispatch script callbacks after the entity pass. Preserve
the existing script-free API behavior while adding this explicit dependency.

1. Find the source rule under the [source policy](sources.md).
2. Name its inputs, owned state, units and observable outcomes.
3. Add an asset-free example to the owning feature's unit tests.
4. Connect the setup adapter and named supported implementation.
5. Compare independent reference facts/traces and expose actionable diagnostics.

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

This is a conservative static check, not a complete GDScript parser or proof of
runtime purity. It does not resolve local type scopes, inner-class aliases or
dependencies embedded in serialized resources. Identifier shadowing and reflective
code require human review; comments and unrelated strings are excluded. Ordinary
data methods such as `FrogLordConfig.add_child()` are allowed. Keep dependencies
explicit instead of obscuring them to pass the check. Hosted CI remains deferred.
