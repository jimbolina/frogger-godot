# Architecture and ownership

## Dependencies

The [domain model](domain-model.md#context-map) maps the contexts; this list
states what each layer may use.

- `src/data/` holds the typed `Resource` records the game plays from (maps,
  models, textures, tables, sound banks, demos, names), the abstract
  `AssetCatalog`, `AssetIndex` and `FroggerIds`. It depends on nothing
  game-side. Large map sections are stored as packed columns and rebuilt lazily.
- `src/game/` contains `RefCounted` definitions and exclusively owned run
  state and rules. It receives validated definitions and tick commands; it does
  not depend on data records, application, rendering, inspection or
  presentation, open files, poll input, consult wall time or access Nodes.
  Godot math types are allowed.
- `src/application/` owns the adapters from data records to gameplay
  definitions and the behavior and callback catalogs. Only `loaders/`
  (`ImportedAssets`, `FrogLordPointer`) and `storage/` (`ProgressStore`,
  `HighScoreStore`, `GraphicsStore`, `LauncherStore`) may touch files or the
  environment. `setup/AssetLocation` chooses the assets root from the launch
  arguments and the read `LauncherStore` it is given, checking folders through
  `ImportedAssets.has_index`, so it touches no files itself.
- `src/rendering/` builds render resources (meshes, materials, shaders, texture
  pages, effect geometry) from data records and committed gameplay state.
- `src/inspection/` owns scenarios, validated options, corridor guards, presets
  and their manifests, and the sandbox. Presentation translates CLI and
  environment inputs into explicit options. Gameplay and application never
  depend on inspection.
- `src/presentation/` and `scenes/` own scene lifetimes, input translation,
  drawing and audio playback. `MapSceneData` is a rendering dependency bundle,
  not authoritative state.
- `archive/` holds the retail readers (`source/`, which depend only on
  `src/data`), the retail-backed `GameData`, the importer and the retail
  goldens. Nothing outside `archive/` depends on it.
- Simulation uses direct calls for ordered updates. Notifications follow
  state changes; subscriber order must not decide collision outcomes or RNG use.
  Rendering interpolation cannot feed back into authoritative state.

The [domain glossary](domain.md) gives semantic boundaries. Existing
[simulation](gameplay/simulation.md), [coordinates](rendering/coordinates.md) and topic references
remain authoritative for detailed rules.

## Presentation hosts

`GameplayHost` owns the gameplay period accumulator, source-style held/pressed
sampling and one outstanding worker command. It returns completed results to
the presentation host. `GameplayScreen` owns the dedicated game input and HUD;
`TerrainViewer` retains inspection overlays and trace capture. Both use
`GameplayWorldView` for map, frog and entity drawing from committed snapshots. Long host stalls
retain at most one fractional period. Pause, reset and explicit stepping join
pending work before changing the run.
`PathInspectionSession` and `EntityInspectionSession` own independently seekable
map timelines. The map viewer retains its separate catch-up clock and backward
seek behavior. `MapCaptureSession` owns external image/metadata capture and
benchmark scheduling; it consumes rendering facts supplied by the viewer.

### Graphics settings

`GraphicsProfile.current()` is the one live `GraphicsSettings` record; a
replacement emits its `changed` once. `SceneLighting` and the world views read
it and update in place when it changes. The project's single autoload,
`GraphicsDebug` (`debug/GraphicsPanel`), loads `GraphicsStore` into the profile
at startup and, when the file exists, applies the window, root viewport and
global shadow settings through `GraphicsApplier`; without one, command-line
window and vsync options stand. Under the headless display server it does nothing.
The 0 key shows its panel unless player 1 has bound it. Viewport anti-aliasing and scaling reach only the root
viewport; the map viewer's `SubViewport` keeps its own.

## Tick coordination

`GameplayRun` is the transaction coordinator. It prepares independent system
candidates, sequences entity updates, frog control/movement, contacts, camera,
animation and visibility, checks optional guards, and commits only on success.
`Frog` owns reset preparation, input, jumps, movement, terrain reactions and death.
`FrogContacts` owns ordered FORM/primitive scans and platform mount, carry,
departure and landing. Contact methods receive the frog component explicitly;
they do not retain a back-reference or another mutable owner.
The first lethal contact identity belongs to attachment state because later
contact arbitration reads it. Diagnostics contain provenance and observations.

## Gameplay state

`GameplayState` composes `FrogState` (movement, control, timers and collision pose),
`AttachmentState` (platform-local coordinates and contact identities),
`TickRequests` (logical requests and counters) and `TickDiagnostics` (provenance
and observations). Each value has a complete detached copy contract. Systems,
entity state, the RNG seed and the tick identity remain at the transaction level.
Lives are a frog state value; applying life-decrement requests remains game-flow work.
`TerrainTrace` flattens this structure into the existing wire schema, including
the historical `fixture_lives` key. Runtime consumers use the composed records.

## Current lifetimes

`ImportedAssets` loads its index, tables and name lists on open and every other
record through Godot's resource cache, so records are shared: treat them as
read-only. In the archive suite and the importer, `GameData` owns its archive;
closing it closes the archive, and retained records do not make later archive
reads valid.

Viewer `open_data(catalog, take_ownership = false)` borrows by default. The
caller must keep borrowed data open until every consumer has detached. A viewer
that opens its own data passes `true`, closes it when replaced or exiting, and
releases its drawing resources. Reattaching the same object never closes it or
silently relinquishes ownership. Do not transfer ownership to multiple viewers.

Meshes/materials belong to their rendering bundle or instance according to the
existing rendering APIs. Instance animation clocks are separate from shared
model definitions. Source replacement clears selections, caches and drawing
references before another source is shown. Standalone viewer entry points and
synthetic injection remain supported.

`GameplayRun` copies setup definitions and owns frog, camera, animation and RNG
state, plus an optional `EntityRun` supplied through `EntityCollisionDefinition`.
Each command operates on private candidate copies and commits only on success.
Recorded demo commands follow the same transaction: only a committed result
reports consumed input. `DemoPlaybackSession` owns duration/cursor state and
accepts that result after synchronous or worker completion. `DemoSetup` resolves
the demo's resources and initial state without relaxing a preset's guard. See
[recorded control](gameplay/simulation.md#recorded-demo-control).

The attract cycle's `AttractCycle` lives in `FrontEndSession` for the session
and keeps its place across the main menu and the game scene. Each attract demo
gets its own `DemoPlaybackSession` and `AttractTimer` in `GameplayScreen`; both
end with the demo, and a death reset inside the run never touches the session's
cursor.

Entity/path advancement builds its next independent state directly. The entity aggregate exposes `begin_candidate`, detached snapshots and ordered
update methods; the gameplay aggregate never accesses its private state.
`commit_candidate` consumes the successful candidate only after all phases pass.
Intermediate observations and public results deep-copy mutable state. Prepared script
definitions detach caller inputs and validate animation/form/path dependencies
once, retaining bounded runtime cursor and instruction-budget checks. Standalone
script calls validate supplied definitions on every call. A dependency mismatch
uses that safe validation path. Private candidate script execution may update its
owned state and RNG directly; any subsequent failure discards the whole candidate.
The [host contract](#presentation-hosts) defines scheduling and worker ownership.
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
`GameplayRun.step` captures diagnostic phases by default. Interactive playback
disables that capture: it still commits the same detached final state, contacts,
requests and RNG, but omits intermediate snapshots and ordered entity-update
observations. Trace recording always enables them. Retail tests compare both
paths over the complete source-verified ORG1 routes.

Optional visibility lifecycle adds a final camera-to-group selection and live
creation/renewal phase after animation, before commit. Its pure selector and
owned live-list state depend only on detached group facts and camera snapshots.
Late selection or polygon-budget rejection rolls back the same aggregate.
Persistent paths outlive live instances. Supported scripted lifetimes initialize
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
add teleport commands or bypass gameplay validation in `GameplayRun`.

Opt-in platform execution requires an integrated camera. The order is paths,
source-ordered entity transforms and supported custom/script updates, frog
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
Empty active definitions preserve existing runs. The JUN1 and ORG1 presets
are supported scenarios: each checks its manifest's provenance (build, resource
mappings, books, scripts and behavior names) against the supplied assets before
it enables its guard and updates, and refuses to start when any of them differ.
The ORG1 guard also limits the frog to the supported actions, collision roots
and unpowered state before contacts and commit; contacts it excludes still run
their logical updates.
The viewer pauses on rejection. R reconstructs the whole inspection, including
input buffers and presentation clocks, while retaining the selected input mode.

The ORG1 road preset additionally owns detached frog collision definitions and
`FrogCollisionPose` in `GameplayState`. Previous stored probes are read during
collision; action/actual-cel changes refresh them at the final pose phase.
Definitions, cached samples and primitive diagnostics are deeply copied across
publication boundaries. Late failure discards them with every other candidate
field. Rendered and interpolated model transforms never drive collision.

`GameplayState.attachment.entity_cell` and `entity_offset_16` are platform-local. `target_16`
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
integrated `GameplayRun` owns its own independent mutable state. Transaction
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
`GameplayRun` owns frog reactions, shared checkpoint covered bits and commit.
Supported pink frog updates receive the candidate frog pose/mode and previous HIT;
their owned carrier/timer/death state commits with the same aggregate. Presentation
consumes the resulting pose and hides the dead frog without deciding pickup.
Snapshot and contact-scan order stay
separate from the source live-update order.
The [entity contract](../../tests/golden/specs/entities.md#org1-route-proof) owns the
expanded behavior set and its source provenance. General inspection remains
script-free; supported definitions opt into these updates.

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
checkpoint updates have separate modules behind the typed dispatcher. Shared
cave light radii belong to the entity environment, written by the immortal
light before the first tick and read by rewards, callbacks and the per-visit
fade.

Implementing another original behavior is a code change. A mod only repoints
data to already supported behavior. Keep raw identifiers for diagnostics;
never dispatch executable addresses directly.

`LevelSupportReport` (`src/application`) is the inventory of that support for
any `AssetCatalog`: per playable level it runs every placed form through the
theme book, `EntityBehaviorCatalog`, `FormCallbackCatalog`, `EntityScriptSetup`
with `validate` and `EntitySetup`, and every used remap slot through the level's
banks, and also checks the unplaced forms of the used themes. Rows are mapped
(empty reason), unmapped (a selected level uses them and the port cannot play
them) or unplaced. The importer prints it after the catalog step and
`tools/asset_report.sh` prints it on demand; the archive suite's round trip
requires a FrogLord save to add exactly its deliberate probe
([golden](../../tests/golden/specs/imported-assets.md#froglord-round-trip)).

`AssetLocation` resolves the base root in the order the
[assets reference](assets.md#asset-location) gives and opens `ImportedAssets`
over it with the shippable root beside it; scenes reach it through
`GameplayScreen.asset_location` or `ViewerArguments.open_assets`, which read
`LauncherStore` from `user://launcher.cfg` into a `LauncherSettings` record.
An unusable location yields a catalog whose error lists the rejected
candidates. `MusicPlayer.folder_of` takes the music folder from the catalog's
base root.

`FrogLordPointer` (`src/application/loaders`) reads and atomically writes the
file naming the overlay the FrogLord watcher imported last;
`AssetLocation.resolve_overlay` reads it beside the base root, and
`AssetReloadWatcher` (`src/presentation`) polls it and signals `GameplayScreen`
under `--froglord`.
A reload opens a new `ImportedAssets` over the new overlay folder, whose
records lie at new paths, and hands it to `open_data` with ownership, which
releases the previous catalog; loaded records are never replaced in place.

## Sandbox

The [sandbox](../../README.md#sandbox) is an owner play-check scene layered on
the normal run; it adds no gameplay rules.

- `src/inspection/`: `SandboxLevel` builds the data-free arena `LevelDefinition`
  (zones, camera zone, spawn, timer, rewards). `SandboxSpawner` places catalog
  entities with static/line/loop/speed paths and rebuilds a validated
  `EntityCollisionDefinition` and component `RunStart`. `SandboxEntityTemplates`
  borrows resolved entities from `GameplaySetup` whole-map setups of the
  supported levels, so scripts, forms, payloads and rewards come from the
  executable's tables. `SandboxPresets` holds the named layouts.
- `src/rendering/`: `EntityModelOrigins` records each slot's source theme and
  level; `MaplessEntityResources` builds entity meshes from those origins
  without a decoded map.
- `src/presentation/`: `sandbox/SandboxScreen` extends `GameplayScreen` and
  reopens runs through `open_run`; `sandbox/SandboxPalette` is its panel.
  `GameplayWorldView.build_mapless_entities` draws the models, and
  `EntityPlaceholderView` draws footprints for slots without one.
  `tools/GameplayStateFacts` supplies overlay lines shared with `TerrainViewer`.

Gameplay and application never depend on these classes; inspection may use
application setup, and presentation only translates input into spawner and
preset calls. To cover a new mechanic, append a `Layout` with
`Layout.add(entity, cell, path, speed, form)` entries in `SandboxPresets.all()`,
using FrogLord names. Entries the current data cannot supply are skipped and
reported; the archive suite's preset test requires every entry to apply with the
retail data.

Limitations:

- Every add, remove and clear reopens the run, so all entities restart from
  their initial path and script state.
- Zones are identified by colour and the panel legend; there are no in-world labels.
- Map-less models are unlit: no map supplies lights.
- With the complete data, five kinds stay unspawnable: `ORG_BABY_FROG` (needs a parent
  log and visibility lifecycle), `ORG_LOG_SNAKE` (needs a parent log),
  `GEN_TOP_LEFT` and `GEN_BOTTOM_RIGHT` (level fade bounds markers) and
  `FOR_SWAYING_BRANCH` (no supported level places it).
- The level timer keeps the source 2250 ticks; when a run ends, the screen
  restarts the sandbox instead of extending time.
- Speed and cell spin boxes change only through their arrow buttons; typing is
  disabled so keys keep reaching the game.

## Automated checks

Both test wrappers compile scripts, check architecture, then run tests and
validate their results; see [testing](testing/README.md). The architecture scanner
checks protected code and its statically discoverable dependencies, including
project class names, literal script paths and inherited bases. It reports
computed loads and dynamic calls for review. Gameplay runtime resource loading
is file I/O; literal preloads of permitted script definitions are allowed.

The scanner also enforces archive isolation. No script under `src/`, `scenes/`,
`assets/`, `tests/` or `tools/` may depend on anything under `archive/`, directly
or through other scripts, by class name, literal load path or base. Scene and
resource files under `scenes/` and `assets/` must not reference `res://archive/`;
these are found by a line scan. Archive scripts are scanned so their class names
resolve, but they are not restricted themselves.

`src/data/` is a protected layer for imported data schemas. Its scripts inherit
`RefCounted` or `Resource`. They may hold `Texture2D`, `Mesh`, `ArrayMesh`,
`AudioStream`, `AudioStreamWAV`, `Animation`, `AnimationLibrary` and
`PackedScene` fields, but may not use other node or tree types or calls,
environment I/O, runtime loads or dynamic calls. Data may not depend on gameplay,
application, rendering, presentation, inspection or scenes. Application and
source code may use data; gameplay may not. Application loaders and storage are
the only application code allowed file and environment access, including
computed resource loads.

The scanner also rejects entity-name comparisons, membership tests and match
dispatch in gameplay, while permitting raw names in diagnostics.

Light and environment nodes belong to presentation: under `src/`, the types
`Light3D`, `DirectionalLight3D`, `OmniLight3D`, `SpotLight3D`,
`WorldEnvironment` and `Environment` may appear only in `src/presentation/`
(`lighting-ownership`). `src/rendering/` computes node-free lighting and tint
specifications that `SceneLighting` applies through the light nodes it
owns: glow points in its `GlowLightPool` and lava clusters in its
`EmissiveLightSet`, each created on first use. A scanner test also checks that
every folder under `src/` is either protected or forbidden to the protected
layers, so a renamed folder cannot silently leave the rules.

This is a conservative static check, not a complete GDScript parser or proof of
runtime purity. It does not resolve local type scopes, inner-class aliases or
dependencies embedded in serialized resources beyond archive path references. Identifier shadowing and reflective
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
