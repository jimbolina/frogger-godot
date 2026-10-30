# Golden data

These are text facts only: names, sizes, flags, counts, IDs and digests.
Never commit retail bytes or excerpts. Tests load the owner's retail files
through `FROGGER_DATA_DIR` and compare decoded values with these facts.

`synthetic/.gdignore` keeps raw fixtures out of Godot's asset importer. Tests
read them with `FileAccess`; CSV columns are not translation locales. Importing
these tables as translations can crash Godot 4.5.1's threaded Mac importer.

Generators in `tools/` independently implement FrogLord's formats and the
C reference's playback calculations in Python. They share no GDScript
implementation. Never regenerate expected results from Godot output.
Every new family requires a deliberate-break check: corrupt one fact,
observe the intended failure, then restore it.

The [keyboard replay inputs](../../docs/reference/testing/terrain-inspection.md#whole-map-keyboard-playthrough)
under `fixtures/` are stimuli rather than expected-state goldens.

## Specifications and reproduction

Read only the specification for the format being changed. Each lists the
files, columns, generator command, and independent cross-checks. All
commands run from the repository root; generated facts live in
`pc-retail-v3.0e/` or `synthetic/`, as specified for each family.

| Format | Specification |
|---|---|
| MWI, MWD, WAD, PowerPacker | [Archives](specs/archives.md) |
| Executable tables | [Executable tables](specs/executable-tables.md) |
| PC sound metadata and logical voice timing | [Sound](specs/sound.md) |
| Sound pitch, distance volume and pan, PCM slices, loop modes and voice diffs | [Sound playback](specs/sound.md#sound-playback) |
| Recorded demo headers and decoded-input summaries | [Demos](specs/demos.md) |
| VLO images | [Textures](specs/textures.md) |
| Static models and stored MOF facts | [Models](specs/models.md) |
| XAR, flipbooks and animated textures | [Animation](specs/animation.md) |
| Maps, animation counters, cave falloff, projection and SkyLand | [Maps](specs/maps.md) |
| Gameplay ordering-table depth biases for terrain, frog, pickups and fireflies | [Depth ordering biases](specs/maps.md#depth-ordering-biases) |
| Final-PC PATH records and source path updates | [Paths](specs/paths.md) |
| Final-PC entity identities, FORM grids, transforms, POP/SAFE/SQUISHED, animated probes/cuboids, guarded JUN1/ORG1 routes and visibility lifecycle | [Entities](specs/entities.md) |
| Animated-part cuboids, decoded primitive matrices and the collision rotation cache | [Animated primitive contacts](specs/entities.md#animated-primitive-contacts) |
| Scripted visibility, immortal initialization, pink frog pickup/riding/death and guarded ORG1 gameplay | [Scripted visibility](specs/entities.md#scripted-visibility) |
| Tongue, rewards, start clocks, custom entities and verified FORM callbacks | [Gameplay flow](specs/entities.md#tongue-rewards-and-level-flow) |
| Forest hive, branch, animal, visibility and terrain-projection behavior | [Forest entities](specs/entities.md#forest-entities) |
| Volcano switch, controlled-platform and falling-platform behavior | [Volcano entities](specs/entities.md#volcano-entities) |
| Cave light radii, fade, firefly pickups, fat fire fly bob and retail light payloads | [Cave entities](specs/entities.md#cave-entities) |
| Desert rocks, tumbleweed, snake, vulture, croc head, crack and retail payloads/action lengths | [Desert entities](specs/entities.md#desert-entities) |
| Jungle plant, rope bridge, mushroom bounce, outro door bounce-back, hippo script and retail payloads/plinths/action lengths | [Jungle entities](specs/entities.md#jungle-entities) |
| Swamp squirt, crusher, press, crusher callback, rat, slug, weir, barrel script registers, LOCAL_ALIGN and retail payloads/FORMs/admission | [Swamp entities](specs/entities.md#swamp-entities) |
| Sky triggers, PATH_INFO platforms, backdrop drift, Game_timer cadence, balloon/helicopter/hawk registers and retail payloads/FORMs/callbacks/admission | [Sky entities](specs/entities.md#sky-entities) |
| Particle generators, shadows, hop trail, poly-piece pop, splash, pop ring, score popups, frog tint/croak, glows and retail hilites/effect textures/generator records | [Effects](specs/effects.md) |
| Front-end level flags, completion and gold-frog unlocks, JUN1 rewrite and page-flow requests | [Front end](specs/frontend.md) |
| Level-select stack layout, camera, lights, gold-frog quads and scripted motion, glow, spin and fade traces | [Level-select stack](specs/frontend.md#level-select-stack) |
| Front-end water and riverbed mesh, wave heights, prim colours, draw order and options camera presets | [Front-end water](specs/frontend.md#front-end-water) |
| Locale-to-language detection, language banks and localized front-end image names | [Languages](specs/frontend.md#languages) |
| Options page layout, volume steps and levels, log cels, hop, fly and camera timing and scripted page traces | [Options page](specs/frontend.md#options-page) |
| Options page model matrices on the water surface, title sprites, frog motion, actions and shadow, log polygon cels | [Options page models](specs/frontend.md#options-page-models) |
| Controller-page records, defaults, bindable scancodes, Godot key mapping, capture rules and scripted page traces | [Controller page](specs/frontend.md#controller-page) |
| Synthetic bounded entity script updates and requests | [Entity scripts](specs/entities.md#entity-script-components) |
| Combined camera zones and visibility: synthetic gameplay and JUN1 log probes | [Zone/lifecycle integration](specs/entities.md#combined-camera-zones-and-lifecycle) |
| Synthetic grid surface and layer queries | [Grid queries](specs/grid.md) |
| Synthetic frog controller/mover, collision and terrain callback records | [Terrain components](specs/terrain-components.md) |
| Default camera and active-zone transition/control records, including JUN1 probes | [Camera components](specs/camera-components.md) |
| Synthetic gameplay projection and source-rendered geometry | [Gameplay projection](specs/gameplay-projection.md) |
| Synthetic frog animation catalog and component records | [Frog animation](specs/frog-animation.md) |
| Synthetic ordered terrain/camera/animation component records | [Integrated terrain](specs/integrated-terrain.md) |

## Digest convention

A **list digest** is the SHA-256 of the list's decimal values joined by
commas, with no spaces: `sha256(",".join(str(v) for v in values))`. Both the
generator and the Godot tests compute it from decoded values, never from raw
bytes.

Format-specific geometry/pixel ordering, padding and hash algorithms are
specified in the linked documents. Do not assume every digest hashes raw bytes.

[Logical sound and generic pickup facts](specs/sound.md) cover supplied sound
tables, Windows bank lengths, voice lifetime/RNG and generic pickup behavior.
