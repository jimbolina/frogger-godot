# Domain language

The core domain is faithful Frogger behavior played from the imported assets.
Frozen C is the behavior authority, checked against retail observations; the
committed assets are the content authority; FrogLord is the format authority
for the archive readers ([source policy](sources.md),
[domain model](domain-model.md#authority)). Record disagreements in the
relevant technical reference; do not invent rules.

## Subject index

| Area | References |
|---|---|
| Source data | [Build recognition](../../archive/docs/formats/build-detection.md), [archives](../../archive/docs/formats/archives.md), [executable tables](../../archive/docs/formats/executable-tables.md), [textures](../../archive/docs/formats/textures.md), [models](../../archive/docs/formats/models.md), [model animation](../../archive/docs/formats/animation.md), [maps](../../archive/docs/formats/maps.md) |
| Gameplay | [Simulation](gameplay/simulation.md), [PC timing](gameplay/pc-timing.md), [grid](gameplay/grid.md), [paths](gameplay/paths.md), [entities](gameplay/entities.md), [terrain movement](gameplay/terrain-movement.md), [camera](gameplay/gameplay-camera.md), [frog animation](gameplay/frog-animation-control.md), [front end](gameplay/front-end.md) |
| Rendering | [Coordinates](rendering/coordinates.md), [shaders and lighting](rendering/README.md), [lighting](rendering/lighting.md), [single-player HUD](rendering/README.md#single-player-hud), [gameplay projection](rendering/gameplay-projection.md), [effects](rendering/effects.md) |
| Model and assets | [Domain model](domain-model.md), [architecture](architecture.md), [assets](assets.md), [archive](../../archive/README.md) |
| Verification | [Testing and inspection guide](testing/README.md), [golden specifications](../../tests/golden/README.md), [sandbox](architecture.md#sandbox) |

## Contexts and identities

**Archive** describes the retail files and the readers and importer that
decode them; **data** is the typed records imported from them, which the game
plays from; **live play** is one running game's state and rules. Application
adapters translate data records into gameplay definitions. Inspection owns
scenarios, presets and supported-scenario restrictions; presentation owns host
input and drawing. The [domain model](domain-model.md) maps these contexts,
their aggregates, events and asset identities; see
[architecture](architecture.md) for dependencies and ownership.

Gameplay definitions are detached copies of data records. Terrain grids are
copied by `TerrainGridSetup` from the imported map records; pure `GridQueries` uses these
definitions without files or scene resources; see [grid](gameplay/grid.md).
`PathSetup` likewise copies supported paths into definitions. Each moving entity
owns a separate runner, including when paths share geometry. See
[paths](gameplay/paths.md) and [entities](gameplay/entities.md).

| Term | Meaning and authoritative contract |
|---|---|
| Source / build | The retail files the importer read versus the recognized build they belong to. `AssetIndex` records the build name and the files' digests; build-specific identities such as callback addresses are keyed by it. See [build detection](../../archive/docs/formats/build-detection.md). |
| Archive resource / Godot Resource | An original indexed file versus an engine resource object. The resource id (its MWI position) keys the imported asset in `AssetIndex`; see [archives](../../archive/docs/formats/archives.md) and [asset identities](domain-model.md#asset-identities). |
| Map / level | A decoded map resource versus a level selected through the executable map book and its dependencies; see [maps](../../archive/docs/formats/maps.md). High/low detail use different resources. |
| Path / path runner | Authored map geometry and its source index versus one mutable cursor over a detached definition. A path can serve multiple entities with separate cursors; see [paths](gameplay/paths.md). |
| Form book entry / form grid | A named object kind selecting behavior, model and script versus a map's indexed collision grid. Form-book ids are scoped to a theme (or GENERAL); bounded contact inspection reads the grid without running frog reactions. |
| Map entity / live entity | A persistent authored record/path cursor versus a run-owned live instance. Optional visibility lifetime can destroy and recreate instances without changing authored identity; the array index remains the identity even with gaps. See [entities](gameplay/entities.md). |
| Entity script / GDScript | Original opcode data versus this project's implementation language. Decoding a script does not execute it; see [executable tables](../../archive/docs/formats/executable-tables.md). |
| Tick / rendered frame / animation frame / cel | A logic update, displayed image, animation clock position and authored pose selection. See [simulation](gameplay/simulation.md) and [animation](../../archive/docs/formats/animation.md). |
| Game position / grid cell / render position | Distinct units. Conversion belongs to `GameSpace`; see [coordinates](rendering/coordinates.md). |

## Following a form

`GameTables.theme_book()` on the catalog's tables gives the `ThemeBook`. A
map's theme and form-book id select `ThemeBook.get_form()`, a `FormBookEntry`;
the GENERAL bit changes the owning theme. `GameNameLists` supplies the form
name and `entity_name_for()` applies FrogLord's named entity overrides.
`AssetCatalog.model_resource_for()` picks the form's model through the level
or GENERAL WAD; `EntityModelSelection` substitutes behavior-selected level WAD
slots (Volcano switch colours, Jungle plinth `op_id`). Table examples live in
`tests/unit/data/tables/`; retail facts live in the archive suite's goldens.

Entity setup resolves FrogLord names through `EntityBehaviorCatalog` into
typed implementation and payload capabilities. Unknown names retain the
diagnostic-and-omission fallback.
The [FORM contact contract](gameplay/entities.md#form-contact-inspection) copies
the selected grid and checks one detached entity pose against a world point.
Bounded POP and SAFE-platform reactions use source map-group order and a shared
run transaction. Whole-map play additionally resolves supported custom reactions. Form callback
addresses need verified per-build name mappings before callback execution; the script
list's `CallbackNames` is a separate opcode callback namespace. Unknown entries
must retain their source identity and diagnostics and use a documented fallback;
the owning behavior must define that fallback before execution is added.

Mods may select supported original behavior; player data never introduces
executable code. The owner selected frozen C port behavior at 30 Hz; the
separate original-executable discrepancy is recorded in the simulation contract.
