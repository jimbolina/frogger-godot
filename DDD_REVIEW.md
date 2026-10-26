# Domain-driven design review: frogger-godot

Reviewed at commit `60cd252` plus the uncommitted ORG1 scripted-visibility work.
Scope: `src/`, `docs/`, `tests/` layout, `tools/support/architecture_scanner.gd`.
Not reviewed: numeric fidelity against the C reference, rendering output.

## 1. What is already strong

These are genuine DDD practices, and they are rarer than they sound. Keep them.

- **Explicit bounded contexts with a documented dependency direction.**
  `src/legacy` (source compatibility), `src/convert` (rendering resources),
  `src/game` (live play), `src/presentation` (host, input, drawing). The
  direction is written down in `docs/reference/architecture.md` and enforced
  mechanically by `tools/support/architecture_scanner.gd` as part of the test
  wrapper. Most projects only aspire to this.
- **A real ubiquitous language with disambiguation.** `docs/reference/domain.md`
  has a glossary that separates look-alike terms (map entity vs live entity,
  path vs path runner, archive resource vs Godot Resource, tick vs frame vs cel).
- **An anti-corruption layer between the original formats and the game.**
  The `*Setup` adapters copy decoded `MapFile`/`MofFile`/`FormBookEntry` facts
  into detached `*Definition` objects. Nothing in `src/game` imports a legacy
  type. This is exactly how a port should isolate itself from the source data.
- **Transactional aggregate semantics.** `TerrainRun.step` works on candidate
  copies (camera, RNG, animation, entities, frog) and commits only on success.
  A failed phase publishes nothing. Determinism is explicit: `SourceRandom`
  carries a seed, a draw count and labelled consumers; no wall clock, no
  engine physics.
- **Pure domain services.** `GridQueries`, `ZoneQueries`, `FormReaction`,
  `EntityContactOrder`, `MapGroupVisibility`, `TerrainModifiers` are
  side-effect-free static modules over value inputs. Easy to test, easy to read.
- **Independent oracles and text-only goldens**, with a deliberate-break rule
  for every new family. The verification culture is the project's biggest asset.
- **Documentation discipline**: one home per fact, size caps, no phase reports.

## 2. Where the model is drifting

Ordered by how much they will hurt at P9 (remaining themes) and P10 (game flow).

### 2.1 The vocabulary is becoming a verification vocabulary, not a Frogger vocabulary

Identifiers, diagnostics and reference docs are saturated with proof-process
words: *admitted*, *admission*, *guarded*, *proof*, *closure*, *excluded
neighbor*, *all-attached lifetime*, *obligation*, *slice*, *audited*.
Examples: `EntityDefinition.background_admitted`,
`ExplorationGuard.scripted_visibility_admitted`,
`FormContactDefinition.admission_exclusion`, `Org1ExplorationSetup`,
and five JSON "admission manifests" totalling 5,400 lines under
`src/presentation/setup/`.

None of these are Frogger concepts. A Frogger developer talks about forms,
entities, scripts, checkpoints, turtles diving, the baby frog. The current
words describe *how much of the C reference has been proved so far*. That is a
legitimate concern, but it belongs to a separate **verification/inspection
context**, not inside the gameplay model. Today it is woven into the aggregate:
`TerrainRun.step` consults `_exploration_guard` at five separate points, and
`ExplorationGuard` lives in `src/game/zones/` as if it were a game rule.

Suggestion:

- Name the thing honestly: an `inspection` (or `verification`) module that
  owns guards, presets and manifests, and that the finished game does not load.
  Either `src/inspection/` or keep it under tests/tools.
- Give `TerrainRun` one optional hook (a `TickObserver`/`TickGuard` interface
  with a single `check(phase, candidate)` call) instead of five inline checks,
  so the aggregate's phase order reads as game rules only.
- Rename `background_admitted` and friends to what they mean in the game
  (see 2.3: the behavior kind).
- Scope the verification language to `tests/golden/specs/` and the testing
  guide. The gameplay references should describe rules, not proofs.

### 2.2 Level-specific knowledge is hard-coded into generic layers

- `Org1ExplorationSetup`, `Jun1ExplorationSetup`,
  `TerrainScenario.apply_des2_inspection_defaults`,
  `TerrainScenario.apply_jun1_inspection_defaults`.
- Authored indices as magic numbers: `setup.definitions[53].pink_frog_pickup`,
  `definitions[61]`, `definitions[60]` in `org1_exploration_setup.gd`.
- `terrain_viewer.gd:829` branches on `level_code == "DES2"`.
- `terrain_scenario.gd` maps theme numbers to names inline
  (`&"JUN" if theme == 4 else &"VOL" if theme == 10 else &"SUB"`), knowledge
  that belongs in one theme catalog.
- `apply_arguments` is a combinatorial matrix of booleans
  (`entity_reactions`, `platforms_enabled`, `entity_lifecycle`,
  `exploration_preset`, `authored_fixture`, `tick_limit_override`...).

The project needs 9 themes and ~50 levels. One preset class plus one
1,500-line manifest per proven corridor cannot be the path to "load any level".
Treat the presets as scaffolding with a planned retirement, and say so in
`PORTING.md`. Replace the boolean bag with a small explicit value
(`InspectionMode` or a `ScenarioOptions` value object with validation in one
place). Move theme/level identity mapping into a single catalog in the source
context (`FroggerIds` is the natural home).

### 2.3 Behavior is dispatched on raw entity-name strings, duplicated across layers

The same literal lists appear in at least ten places:

| Layer | File | Form |
|---|---|---|
| game | `entity_definition.gd:70,74` | `is_immortal`, `is_group_moving` name lists |
| game | `entity_run.gd:69,73,175,283,388-394` | create/step/update/initialize branches |
| game | `entity_background.gd` | `match definition.entity_name` |
| setup | `entity_setup.gd:62,69,71` | payload decoder selection |
| setup | `entity_script_setup.gd:17,30` | payload register layout |
| setup | `form_contact_setup.gd:89` | contact support |
| setup | `entity_collision_scenario_json.gd:91,97` | fixture decoding |
| setup | `org1_exploration_setup.gd` | one-shot animation, checkpoint |

Two layers each hold a copy of "which names are static / moving / immortal /
custom", and they must stay in sync by hand. `EntityBackground.update` is a
switch on name that will grow to hundreds of cases across themes.

The C original resolves each form to a behavior record (per-theme `ent_*.c`
tables with create/update/kill callbacks). That record is the domain concept
that is missing here. AGENTS.md already states the rule: *resolve
types/forms/callbacks by FrogLord names, warn/fall back/report unknown
entries*. Resolution should happen **once**, in the anti-corruption layer,
producing a typed value the game layer dispatches on.

Suggestion:

- Introduce an `EntityBehavior` descriptor (value object): kind
  (`STATIC`, `PATH_FOLLOWER`, `TURTLE`, `BABY_FROG`, `BONUS_FLY`,
  `CHECKPOINT`, ...), payload layout, immortality, group-moving, animation
  policy, custom update module. Resolve it in setup from the FrogLord name
  through a single `EntityBehaviorCatalog`. Unknown name → documented fallback
  plus diagnostic, in one place.
- `EntityDefinition` carries the resolved `behavior`, not booleans like
  `background_admitted`/`pink_frog_pickup`.
- `EntityRun` and `TerrainRun` dispatch on `behavior.kind` and call the
  behavior's update module. `EntityBaby` is already the right shape (one
  behavior, one static module, private state object); make that the pattern
  and retire the `match` in `EntityBackground`.
- Add an architecture-scanner rule: no `entity_name ==`/`in [` string
  dispatch in `src/game`. The scanner already exists; this keeps the fix from
  regressing.

This single change is also what makes "mods may repoint existing behaviors"
real: a mod changes the name→behavior mapping; code never changes.

### 2.4 `TerrainRun` is becoming a god aggregate and reaches into another aggregate's privates

`terrain_run.gd` is 1,320 lines with 40 fields. It owns frog control,
movement, landing, reactions, death, terrain collision, entity contact scans,
platform mount/detach/jump, camera input assembly, animation, visibility, zone
selection, guards and the commit. It also reads `_candidate_entities._state`
directly in seven places, so `EntityRun`'s encapsulation is nominal.

`RunSnapshot` (about 70 fields) is the single mutable record every phase writes
to. It mixes: frog kinematics, attachment/platform state, camera and animation
snapshots, RNG state, request counters, game-flow requests (`life_decrement_requested`,
`game_mode_request`), and pure diagnostics (`rng_draw_count`,
`square_source_offset`, `polygon_source_offset`, `fixture_lives`). It is in
effect a tick-scoped global.

Suggestion (incremental, no big-bang):

1. Give `EntityRun` a proper candidate API: `candidate_snapshot()` /
   `commit()` or similar, and delete every `._state` access from `TerrainRun`.
2. Split `RunSnapshot` into `FrogState` (kinematics, mode, flags, timers),
   `AttachmentState` (current/forbidden entity, local offset, transform),
   `TickRequests` (outbox: animation, sound, score, life, game-mode, particles)
   and `TickDiagnostics` (source offsets, RNG draws, square/polygon ids).
   `RunSnapshot` can remain as a composite for a while.
3. Extract a `Frog` component (control, jump, move, land, react, kill) out of
   `TerrainRun`. The C already separates `FROG.C`/`froguser.C` from entities.
   `TerrainRun` then becomes what it already behaves as: the **tick unit of
   work** that sequences phases and commits.
4. Rename accordingly: `TerrainRun` → `GameplayRun`/`LevelRun` (it stopped
   being about terrain several phases ago), `RunSnapshot` → `GameplayState`.

### 2.5 Primitive obsession: magic modes and flags

Across `src/game` there are roughly 190 raw bit tests and mode assignments:
`flags & 4` (27×), `flags & 2` (21×), `flags & 8` (14×), `mode = 269`,
`mode == 265`, `mode not in [265, 266]`, `flags & ~0xDFFF`. The reader must
know the C headers by heart. `FrogAnimationCatalog` proves the project already
knows the cure.

Suggestion: `FrogMode`, `FrogFlags`, `GridSquareFlags`, `EntityLiveFlags`,
`PowerupFlags` constant catalogs named after the C `FROG_MODE_*`,
`FROG_FLAG_*`, `GRID_*` macros, generated the same way the animation catalog
is (independent transcription, no retail bytes). Cheap now, expensive later.

### 2.6 Domain events are stringly typed

`events: Array[String]` and `EntitySnapshot.requests: Array[String]` carry
formats like `"entity:%d:death_pgen"`, `"sound:19:0:0:0"`,
`"moving:27:768:1536"`, `"create:..."`, `"sprite:0:-64:..."`. Presentation
already parses them (`terrain_viewer.gd:747-754` splits on `:`). These are
the outbox that P10–P12 (HUD, particles, audio) will consume; they are domain
events in all but type.

Suggestion: a `TickEvent`/`GameRequest` value (kind + typed payload) with a
`to_trace_line()` projection so the golden traces keep their exact text.
Consumers then switch on a kind, the event catalog becomes discoverable, and
a typo cannot silently drop a sound.

### 2.7 Thirty-six hand-written `copy()` methods

Every state and definition class has a field-by-field `copy()`;
`RunSnapshot.copy` alone is ~75 lines. A new field that is forgotten in
`copy()` is a transaction-leak bug that no compiler catches, and the project's
whole correctness story rests on copies being complete.

Suggestion:

- Decide, per class, whether it is a **value/definition** (immutable after
  setup, shared by reference, no copy needed) or **state** (copied). The docs
  already say definitions are immutable after setup, yet `*Definition.copy()`
  is called defensively everywhere, costing lines and time.
- For state classes, either a single reflective copier
  (`get_property_list()`-based, in one helper) or a unit test that, for every
  state class, instantiates with randomized fields and asserts the copy is
  field-complete. One test guards all 36.

### 2.8 The setup layer is the application layer, filed under presentation

`src/presentation/setup/` is the legacy→game translation layer plus scenario
assembly, which is application/ACL work, not presentation. `TerrainScenario`
also parses CLI flags and reads `FROGGER_DATA_DIR`. Suggest
`src/application/` (or `src/setup/`) for adapters and scenario assembly, with
argument parsing staying in `presentation/tools`. The architecture scanner can
then forbid `OS`/`FileAccess` in the application layer except in the loader
adapters that need them.

### 2.9 Viewer god-nodes hide the reusable host

`map_viewer.gd` (1,618 lines) and `terrain_viewer.gd` (901 lines) each own
input, pacing, worker scheduling, drawing, captures, entity visuals and
overlays. `TerrainTickWorker` is a clean, reusable piece; the 30 Hz pacer,
pressed-edge sampling and command/result plumbing in `TerrainViewer._process`
are also exactly what the real game loop needs. Extract a `GameplayHost`
(pacer + worker + command sampling + result acceptance) that both the viewer
and the eventual game scene use. Keep captures and overlays in the viewer.

### 2.10 Reference docs are carrying proof narrative

`docs/reference/gameplay/entities.md` is 5,100 words and much of it is route
narrative (contacts at ticks 3, 18 and 39; indices 24–47; 36 frog roots).
That is verification history, which the project's own rules say belongs beside
the goldens (`tests/golden/specs/`) or in commit messages. The gameplay
reference should say what the rules are. Trimming it will also make the
glossary terms easier to hold onto.

### 2.11 Naming nits

- `legacy/` suggests "to be removed"; this layer is permanent (it reads the
  player's files forever). `source/` or `original/` says what it is.
- `EntityBackground` → the behavior kind it is (custom update / per-form update).
- `fixture_lives` in authoritative state: either lives are game state or they
  are a fixture parameter; the name admits it is both.
- `TerrainRun`, `RunSnapshot`, see 2.4.

## 3. Suggested order of work

Each step is self-contained and keeps every golden green.

1. **Cheap, immediate**: named mode/flag catalogs (2.5); typed tick events
   with a string projection (2.6); `EntityRun` commit API and removal of
   `._state` access (2.4 step 1); one copy-completeness test (2.7).
2. **Before P9 (more themes)**: `EntityBehavior` + catalog resolved once in
   setup; per-behavior modules; scanner rule against string dispatch (2.3).
   Move guards/presets/manifests into a named inspection module with a single
   hook into the run (2.1). Replace scenario boolean bag with an options value
   (2.2).
3. **Before P10 (game flow)**: split `RunSnapshot`; extract `Frog` from the run;
   extract `GameplayHost` from the viewer (2.4, 2.9). P10 will otherwise bolt
   score/timer/lives onto a 70-field snapshot.
4. **Housekeeping**: `presentation/setup` → `application` (2.8); trim
   `entities.md` to rules (2.10); renames (2.11).

## 4. Things not to change

- Do not introduce a DI container, service locator or global "World". The
  current explicit-dependency style and the architecture scanner are the right
  call for a deterministic simulation.
- Do not move domain state onto Godot Nodes. `RefCounted` plus detached
  snapshots is what makes the worker thread and the golden traces possible.
- Do not relax the independent-oracle rule to speed up the above refactors.
  Every step here is behavior-preserving and the goldens are the safety net.
