# Domain model

This is the map of the game's model: who decides what, which folder owns
which concept, the aggregates that hold mutable state, the values passed
between them, the events they publish and the identities that tie the
imported assets together. The [glossary](domain.md) defines the terms;
[architecture](architecture.md) holds the detailed transaction, lifetime and
copy rules; topic references own the rules themselves.

## Authority

- **Frozen C decides behaviour.** The `../froggy` C port at 30 Hz is the
  behavioural reference ([sources](sources.md)). A rule is ported from it and
  checked against independent facts; a disagreement with retail observation or
  FrogLord is recorded in the owning topic reference, not resolved by guessing.
- **The imported assets are the source of truth for content.** The game
  plays only from an import of the player's copy through `ImportedAssets`
  ([assets](assets.md)): the developer's local `assets/` or a player's import
  under `user://`, with the port's own files from `content/`. Nothing re-reads
  the retail files at run time; content changes go through the importer, a
  FrogLord overlay or a texture pack. `AssetIndex` records the build name and
  the SHA-256 of the executable and archive the assets came from, as provenance.
- **FrogLord is the format authority for the archive readers only.** The
  readers under `archive/source/` follow FrogLord's formats
  ([archive](../../archive/README.md)). FrogLord's name lists were imported with
  the assets (`GameNameLists`) and remain the vocabulary through which setup
  resolves entity behaviours and form names.
- **Presentation never decides outcomes.** Effects, interpolation and sound
  playback draw from committed state and never consume the gameplay random
  stream ([simulation](gameplay/simulation.md#effects-and-the-random-stream)).

## Context map

| Context | Folder | Owns | May depend on | Must not depend on |
|---|---|---|---|---|
| Import / Archive | `archive/` | Retail readers and `GameData` (`source/`), the importer (`import/`), retail goldens and the archive suite (`tests/`), format references, FrogLord configs | Readers: `src/data` only. Importer: any game-side class it needs to build resources | Nothing game-side may depend on it |
| Data | `src/data/` | Typed `Resource` records, `AssetCatalog`, `AssetIndex`, `FroggerIds` | Engine resource types only | Every other context |
| Gameplay | `src/game/` | Definitions, run state and rules: terrain, frog, entities, paths, camera, animation, sound logic, level flow, rewards, front-end rules (`frontend/`), options (`options/`) | Godot math types | Data, application, rendering, presentation, inspection, scenes; files, input, wall time, nodes |
| Application | `src/application/` | Setup adapters from records to definitions, `EntityBehaviorCatalog`, `FormCallbackCatalog`, `ImportedAssets` (`loaders/`), `ProgressStore` and `HighScoreStore` (`storage/`) | Data, gameplay | Rendering, presentation, inspection, scenes; I/O outside `loaders/` and `storage/` |
| Rendering | `src/rendering/` | Meshes, materials, the lit and unlit shader families, `GameSpace`, scene-lighting and tint specs, effect rules over committed state | Data, gameplay, application | Presentation, inspection; light and environment nodes |
| Presentation | `src/presentation/`, `scenes/` | Screens, `GameplayHost`, views, HUD, audio playback, input, viewers, `FrontEndSession`, `SceneLighting` (the only owner of lights and environments) | Every context above, inspection for the viewers and sandbox | Archive |
| Inspection | `src/inspection/` | Scenarios, `ScenarioOptions`, `ExplorationGuard`, presets and their JSON manifests, the sandbox level, spawner and presets, demo playback | Data, gameplay, application, rendering | Presentation; nothing in gameplay or application may depend on it |

The [architecture scanner](architecture.md#automated-checks) enforces the
archive isolation, every rule for data, gameplay and application, and the
ownership of light and environment nodes by presentation. The other
rendering and inspection columns are conventions it does not check; today
`CameraZoneInspection` uses `TerrainTrace` from `src/presentation/tools/`, the
one inspection-to-presentation dependency.

## From asset to frame

1. `GameplayScreen` opens `ImportedAssets`, the `AssetCatalog` over the
   base root's `catalog.tres`; `MapSceneData.load_level` and `TerrainFrogAssets`
   load the level's `MapFile`, render resources and the frog model.
2. `GameplaySetup.from_data` runs the setup adapters (grid, paths, entities,
   behaviours, contacts, rewards, sounds, zones) and validates whole-map
   dependencies, producing one `LevelDefinition` with diagnostics.
3. A `GameplayRun` copies the definition; `RunStart` supplies the carried
   lives and score and the seed.
4. `GameplayHost` paces 30 Hz ticks, samples a `TickCommand` at each command
   boundary and runs one step at a time on `TerrainTickWorker`.
5. The accepted `TickResult` goes to `GameplayWorldView`, `GameplayHud` and
   `SoundVoiceView`, which draw and play it; rendering classes in
   `src/rendering/` supply their meshes, materials and effect geometry.
6. Level completion and game end reach `FrontEndSession`, which updates
   progress and high scores and saves them through the storage adapters.

## Aggregates

Each aggregate has one root that owns its mutable state, accepts commands only
through its public methods and publishes detached snapshots. Definitions are
immutable after setup and may be shared read-only; state is copied.

### Gameplay run

- **Root:** `GameplayRun`.
- **Members:** the candidate and committed `GameplayState` (`FrogState`,
  `AttachmentState`, `TickRequests`, `TickDiagnostics`, `LevelFlowState`,
  `TongueState`, `LogicalSoundState`, sky drift, `Game_timer`, RNG state), the
  `Frog` component, `EntityRun`, `GameplayCamera`, `FrogAnimationController`,
  `SourceRandom`, the optional `TickGuard` and camera zones.
- **Invariants:** a step commits every member or none; a failed reset or tick
  leaves the previous state intact and publishes no partial outcome. Phases run
  in the frozen order ([tick coordination](architecture.md#tick-coordination)).
  Only gameplay draws from the shared random stream, in source order. Lives
  are a frog value; applying a life decrement is level-flow work.
- **Mutated by:** `reset(RunStart)` and `step(TickCommand)`, called by
  `GameplayHost` on its worker or synchronously; inspection and the sandbox
  reopen a run rather than editing one.
- **Snapshot:** `GameplayState` from `snapshot()`; each step returns a
  `TickResult` with the final state, ordered `TickEvent`s and contacts.

### Frog

- **Root:** `Frog`, with `FrogContacts` as its contact component. It is not a
  separate transaction: it works on the run's candidate state.
- **Members:** `GameplayState.frog`, `.attachment` and the frog collision pose;
  shared grid, rewards and collision definitions.
- **Invariants:** contact methods receive the frog explicitly and keep no
  back-reference; attachment, forbidden, hit and carry links are authored entity
  indices with `-1` for none; the first lethal contact belongs to attachment
  state; collision reads stored model poses, never rendered transforms.
- **Mutated by:** `GameplayRun` during a step (control, jump, movement,
  terrain reactions, contacts, death).
- **Snapshot:** `FrogState`, `AttachmentState` and `FrogCollisionPose` inside
  `GameplayState`.

### Entities

- **Root:** `EntityRun`.
- **Members:** one `EntityDefinition` per authored slot (shared read-only), a
  `PathRunner` per moving entity, script, animation and custom-behaviour state,
  the live list and its generations, plus the shared `EntityEnvironmentState`
  (checkpoint positions and bits, cave light radii) carried in `GameplayState`.
- **Invariants:** the authored index is the identity; slots never compact when
  live instances disappear. Updates follow the source live order, separately
  from snapshot and contact-scan order. `GameplayRun` uses `begin_candidate` and
  `commit_candidate` and never touches private state; a committed candidate is
  consumed.
- **Mutated by:** `GameplayRun` (path advance, ordered updates, frog effects,
  checkpoint collision); `EntityInspectionSession` for standalone timelines.
- **Snapshot:** `EntityRunSnapshot` of `EntitySnapshot`s with nested
  `PathSnapshot`s. See [entities](gameplay/entities.md#visibility-lifecycle).

### Path runner

- **Root:** `PathRunner`.
- **Members:** a shared read-only `PathDefinition` and one mutable cursor.
- **Invariants:** each moving entity has its own runner, even when entities
  share a path; a failed step leaves the prior snapshot; `reset_motion` keeps
  the enclosing tick sequence.
- **Mutated by:** `EntityRun`, and `PathInspectionSession` in inspection.
- **Snapshot:** `PathSnapshot`. See [paths](gameplay/paths.md).

### Gameplay camera

- **Root:** `GameplayCamera`, configured by `GameplayCameraDefinition`.
- **Invariants:** integer state from frozen `CAMERA.C`; a rejected input leaves
  it untouched; a shake takes two ordered draws from the run's stream;
  presentation may interpolate the snapshot but never writes back.
- **Mutated by:** `GameplayRun` on its candidate camera, with turns, fixes,
  death and checkpoint offsets requested by the frog and contacts.
- **Snapshot:** `GameplayCameraSnapshot`. See
  [camera](gameplay/gameplay-camera.md).

### Logical sound

- **Root:** `LogicalSoundState`, held as `GameplayState.sound`.
- **Members:** `LogicalSoundDefinition`s, 24 `LogicalSoundVoice` slots and the
  ordered `LogicalMovingSound` owners.
- **Invariants:** allocation that fails consumes neither a random draw nor an
  identifier; voice generations keep a recycled slot from being confused with
  its previous sound; a moving owner is retained even when it is inaudible;
  the clock advances before input each tick.
- **Mutated by:** gameplay through `GameplaySound.play` and the entity and
  frog rules, inside the run's transaction.
- **Snapshot:** the copied state in `GameplayState`. `SoundVoiceView` compares
  consecutive committed snapshots to start, bend and stop players. See
  [logical sound clock](gameplay/simulation.md#logical-sound-clock).

### Front-end session

- **Root:** `FrontEndSession` in `src/presentation/frontend/`. It lives in
  presentation because it carries one game across scene changes; the rules it
  calls are gameplay classes.
- **Members:** `LevelProgress` with its `LevelStack`, `HighScoreBoard`,
  `KeyBindings`, volumes, language, the lives, score and life-bonus
  threshold carried between levels (handed to the next run through `RunStart`),
  and the pause cheats: a `CheatState` and the `PauseCheats` cursors, never saved.
- **Invariants:** page changes follow `FrontEndFlow`'s table; unlocks change
  only through `LevelProgress` methods; high-score insertion follows
  `HighScoreBoard`'s strict comparisons.
- **Mutated by:** `FrontEndScreen` and `GameplayScreen` (level completion,
  game end).
- **Snapshot:** none; the session is persisted instead. See
  [front end](gameplay/front-end.md).

### Level progress and high scores

- **Roots:** `LevelProgress` and `HighScoreBoard` in `src/game/frontend/`.
- **Persistence:** `ProgressStore` and `HighScoreStore` in
  `src/application/storage/` hold plain values; `LevelProgressSetup` maps
  progress to and from them. A missing file gives defaults; an unreadable or
  other-version file gives defaults and an error; a save writes a temporary
  file and renames it over the target.
- **Mutated by:** `FrontEndSession`, which saves options and progress from the
  options page and level flow, and the high scores after initials and at game
  end. See [saves](gameplay/front-end.md#saves).

## Value objects and catalogs

Values are built by application setup, validated once, and immutable
afterwards. Catalogs name source constants so the code never tests raw bits.

| Value or catalog | Meaning | Built or used by |
|---|---|---|
| `LevelDefinition` | Everything a run needs for one level: grid, entity collision, rewards, sounds, camera zones, spawn, bounds, theme, level time and an optional `TickGuard` | `GameplaySetup`; inspection presets add guards |
| `GridDefinition` | Terrain stacks and squares in integer game units | `TerrainGridSetup`; queried by `GridQueries` ([grid](gameplay/grid.md)) |
| `PathDefinition` | One authored path with its segments and source identity | `PathSetup` ([paths](gameplay/paths.md)) |
| `EntityDefinition` | One authored entity: form, flags, matrix, path start, script, resolved `EntityBehavior` and theme payload definitions | `EntitySetup` and the theme setups |
| `RewardDefinition` | One `SCORE_BOOK` row | `RewardSetup`; applied by `GameplayRewards` |
| `FrogMode`, `FrogFlags`, `GridSquareFlags`, `EntityLiveFlags`, `PowerupFlags` | Named `FROG_MODE_*`, `FROG_FLAG_*`, `GRID_*`, live-entity and power-up values; trace numbers are unchanged | Gameplay |
| `EntityBehavior` | Resolved kind, payload layout, execution level and capabilities (immortal, group-moving, tongueable, one-shot) | `EntityBehaviorCatalog` from FrogLord names; gameplay dispatches on the kind |
| `FormCallback` | Typed FORM reaction kinds and their rules | `FormCallbackCatalog` maps build-specific addresses by build name |
| `FroggerIds` | Fixed numbering of levels, themes, worlds, death types, pickups and CD tracks | Data, application, rendering, presentation and inspection (gameplay keeps its own constants) |
| `TickCommand` | One tick's pressed and held input, recorded demo byte and host start context | `GameplayHost` samples it; `GameplayRun` consumes it |
| `RunStart` | Spawn, power-ups, lives, score, seed and start mode of a reset | Setup, the front-end session and inspection |

Unknown FrogLord names keep their raw identity for diagnostics and fall back
to omission; a mod may repoint data to a supported behaviour but never adds
code ([extending behaviour](architecture.md#extending-behavior)).

## Domain events

`TickEvent` is the typed notification a tick emits: a kind plus typed
parameters, with `trace_lines()` giving the stable text the goldens compare.
Events are collected on the candidate in source order and published only with
the committed `TickResult`; a rejected tick publishes none.

| Kinds | Consumers |
|---|---|
| `REWARD` from entity updates; entity `SOUND` notifications | `GameplayRun` itself: rewards apply through `GameplayRewards`, sounds count in `TickRequests` |
| `REWARD`, `SUPER_HOP`, `QUICK_HOP`, `ROLL` | `GameplayHud` (score sprites and power-up display) |
| `HOP`, `AUTO_HOP`, `QUICK_HOP`, `SUPER_HOP`, `ROLL`, `SPRITE`, `SPLASH`, `SLIDE_PARTICLES_REQUEST`, `SLIDE_PARTICLES_STOP`, `DEATH_FIRE_PARTICLE_REQUEST`, `DEATH_ANIMATION`, `LEVEL_TRANSITION` | `GameplayWorldView` and its effect views |
| `CREATE`, `DESTROY` | `TerrainViewer` instance allocation |
| Every kind | `TerrainTrace`, demo traces and the goldens through `trace_lines()` |

The camera, ouch, pant, crash, falling, stun and other kinds are trace
observations with no runtime consumer. Sound playback consumes the committed
`LogicalSoundState`, not events. Consumers run after commit and only draw or
record: subscriber order never decides collisions, rewards or random draws
([tick notifications](gameplay/simulation.md#tick-notifications-and-named-source-values)).

## Asset identities

| Identity | Meaning | How it is resolved |
|---|---|---|
| Build | FrogLord's name for the imported build (`pc-retail-v3.0e`) and the source digests | `AssetIndex.version_name`, `exe_sha256`, `mwd_sha256`; `FormCallbackCatalog` keys addresses by it |
| Level code / level number | `SUB1` is level 48 | `FroggerIds.level_code` and `level_number`; `AssetIndex.playable_levels` lists the codes the game offers |
| Map book row | A level's high- and low-detail map, WAD and remap | `AssetCatalog.map_book_entry(level)` |
| Resource id | Position in the archive index (MWI) | `AssetIndex.paths[id]` gives the asset file, named after the MWI entry; `wads[id]` lists a WAD's children; `counterparts[id]` gives an incomplete model's shape |
| Theme and form-book id | One form, or a GENERAL form | `ThemeBook.get_form(theme, id)`; `model_resource_for(form, level)` picks its model through the WAD |
| Authored entity index | A map entity and its live instances | The slot in `EntityRun`; generations distinguish re-created instances |
| Texture id | A global texture | `textures/images/tNNNN.png` and `materials/model/tNNNN_*`; a `TextureRemap` maps a map's slots to ids; page sets are keyed by bank names |
| Sound id | One sample-table row with its bank and group | `audio/sfx/<BANK>/NNN_<name>.wav`, NNN being the sound id; `read_sound_bank` by the body's resource id |
| CD track | Music | `audio/music/track_NN.ogg` |

[Assets](assets.md#layout) owns the folder layout.

## Enforcement

- `tools/check/architecture_scanner.gd`, run by both test wrappers, enforces
  the dependency rules above, base classes (`RefCounted`, or `Resource` in
  data), the ban on nodes, tree calls, environment I/O and dynamic calls in
  protected layers, archive isolation including `res://archive/` paths in
  scenes and resources, and the ban on entity-name dispatch in gameplay. See
  [automated checks](architecture.md#automated-checks).
- `tests/unit/game/test_copy_contracts.gd` discovers every gameplay value with
  a `copy()` and checks it copies every field and detaches nested values
  ([copy ownership](architecture.md#copy-ownership)).
- The game suite (`tests/`, asset-free, no skips) and the archive suite
  (`archive/tests/`, with `FROGGER_DATA_DIR`) run before every code commit
  ([testing](testing/README.md#required-commit-gate)); independent oracles
  produce the goldens ([golden index](../../tests/golden/README.md)).
