# Domain language

The core domain is faithful Frogger behavior on player-supplied PC data.
The [source policy](sources.md) assigns format authority to FrogLord and
behavior authority to frozen C, checked against retail observations. Record
disagreements in the relevant technical reference; do not invent rules.

## Subject index

| Area | References |
|---|---|
| Source data | [Build recognition](data/build-detection.md), [archives](data/archives.md), [executable tables](data/executable-tables.md), [textures](data/textures.md), [models](data/models.md), [model animation](data/animation.md), [maps](data/maps.md) |
| Gameplay | [Simulation](gameplay/simulation.md), [PC timing](gameplay/pc-timing.md), [grid](gameplay/grid.md), [terrain movement](gameplay/terrain-movement.md), [camera](gameplay/gameplay-camera.md), [frog animation](gameplay/frog-animation-control.md) |
| Rendering | [Coordinates](rendering/coordinates.md), [shaders and lighting](rendering/README.md), [gameplay projection](rendering/gameplay-projection.md) |
| Verification | [Testing and inspection guide](testing/README.md), [golden specifications](../../tests/golden/README.md) |

## Contexts and identities

**Source compatibility** describes the player's selected files and decoded
facts. **Live play** describes one running game's state and rules.
Setup translates between these meanings; presentation and inspection tools
are consumers. `TerrainRun` now owns the first frog component rules and detached
snapshots; entity and complete level play are not implemented. See [architecture](architecture.md)
for dependencies and ownership.

The first gameplay definitions are detached static terrain grids, copied by
`TerrainGridSetup` from decoded map records. Pure `GridQueries` uses these
definitions without files or scene resources; see [grid](gameplay/grid.md).

| Term | Meaning and authoritative contract |
|---|---|
| Source / build | Selected files versus the recognized executable configuration. Identities are scoped to that source/build; see [build detection](data/build-detection.md). |
| Archive resource / Godot Resource | An original indexed file versus an engine resource object. An archive index is meaningful only with its owning source; see [archives](data/archives.md). |
| Map / level | A decoded map resource versus a level selected through the executable map book and its dependencies; see [maps](data/maps.md). High/low detail use different resources. |
| Form book entry / form grid | A named object kind selecting behavior, model and script versus the authored form-grid reference of a map entity. Form-book ids are scoped to a theme (or GENERAL); live form-grid collision is not implemented. |
| Map entity / live entity | An authored map record versus a future run-owned instance with identity and mutable state. Authored record identity is scoped to its map; live identity to its run. Neither implies a particular class hierarchy. |
| Entity script / GDScript | Original opcode data versus this project's implementation language. Decoding a script does not execute it; see [executable tables](data/executable-tables.md). |
| Tick / rendered frame / animation frame / cel | A logic update, displayed image, animation clock position and authored pose selection. See [simulation](gameplay/simulation.md) and [animation](data/animation.md). |
| Game position / grid cell / render position | Distinct units. Conversion belongs to `GameSpace`; see [coordinates](rendering/coordinates.md). |

## Following a form

`ExeTables.theme_book()` decodes forms through `ThemeBook`. A map's theme and
form-book id select `ThemeBook.get_form()`; the GENERAL bit changes the owning
theme. `GameNameLists` supplies the form name and `entity_name_for()` applies
FrogLord's named entity overrides. `GameData` resolves the selected model/WAD
for existing tools. Parser examples live in the executable-table unit tests;
retail facts live in the corresponding golden tests.

Entity setup must select an implemented behavior by the resolved name and create
run-owned state. No runtime behavior registry exists yet. Form callback
addresses need verified per-build name mappings before that step; the script
list's `CallbackNames` is a separate opcode callback namespace. Unknown entries
must retain their source identity and diagnostics and use a documented fallback;
the owning behavior must define that fallback before execution is added.

Mods may select supported original behavior; player data never introduces
executable code. The owner selected frozen C port behavior at 30 Hz; the
separate original-executable discrepancy is recorded in the simulation contract.
