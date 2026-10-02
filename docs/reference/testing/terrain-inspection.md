# Terrain inspection

`TerrainScenario` resolves setup outside the rules. Built-ins are authored
synthetic inputs, not expected outputs. A JSON file may replace `grid`, `level`
and `start`, and supply explicit tick commands. `TerrainScenarioJson` rejects
malformed scalar/vector records; `TerrainRun.create` checks detached rule
definitions. Commands contain logical pressed and held masks, never host keys. Optional
`start_timer_context` and `start_sequence_complete` carry explicit external
startup milestones. Detached command copies preserve every typed field. Seeds
and square flags accept the full unsigned 32-bit range; coordinates and other
scalar fields use signed 32-bit bounds.

Grid JSON contains `dimensions`, `base`, `[first_square,count]` stacks and
squares with flags and four integer `[x,y,z]` vertices. Optional square source
offsets and polygon identities remain diagnostics. Level inputs include spawn,
collision bounds, theme, camera offsets and action lengths. Start inputs include
seed, controller mapping, modifiers, lives and explicit startup mode/timer.
`--seed` and `--tick-limit` overrides use the same decoder in both drivers.

Player data optionally supplies the high-detail frog and real action lengths.
`--level` resolves the selected map's GRID, spawn, camera and theme through
existing `GameData` APIs. By default entities, forms, platforms, zones and
authored entity boundary markers are omitted. `--entity-reactions=pop` opts into
the bounded entity mode below. Neither mode is a complete playable level.

The viewer borrows injected `GameData` unless ownership is transferred.
Replacement closes an owned source once; reattaching the same source retains
ownership. Detaching or replacing a data-derived level clears its scene, run
and displayed source identity before loading another source. Synthetic detached
definitions may remain. Frog resources are loaded once per attachment and shared
between setup and drawing.

Drawing consumes copied snapshots. Interpolation, overlays and projection never
advance rules. Completion pauses the viewer and ends automated capture. The
overlay shows destination, layer flags, source identity, camera, death and
ordered outcomes. Projection scaling reaches terrain, frog and animated texture
frame materials after resize; see [gameplay projection](../rendering/gameplay-projection.md).

`tools/run_terrain.py` runs either driver with an isolated profile, hidden awaited
processes and external logs. `--viewer --render-rate=30|60|144` uses explicit
scheduled presentation deltas with one awaited draw per frame. These are render
schedule tests, not measurements of host FPS. JSONL records initial start/camera metadata, complete typed commands and every
represented phase/snapshot, ordered outcome and RNG consumer. Full trace equality checks
headless/render parity; the independent C comparator checks its explicitly
defined field scope. `tools/verify_terrain_schedules.py` runs the four independent
fixtures against all three render schedules sequentially.

Captures and traces must be outside this checkout and frozen `froggy`.
Generated resources are released on reset/replacement rather than accumulated.

## POP entity inspection

`--entity-reactions=pop` attaches copied STATIC/MOVING definitions and FORM
reaction facts to the same `TerrainRun`. Entity paths, frog, camera and animation
advance through one commit; the viewer consumes its snapshots. Cactus models,
FORM outlines, contacted cells, authored indices and death requests make the
reaction visible. Particle effects are requested, not rendered. Support and
all-attached lifetime assumptions are defined in the
[entity contract](../gameplay/entities.md#bounded-pop-reactions).

With `--data-dir <game-folder> --level DES2 --entity-reactions pop`, the scenario
uses an explicit safe inspection start and one east hop into the first cactus.
This is not the map's normal player spawn. The airborne hit precedes the
destination terrain's own lethal reaction. Golden inputs and source facts are
specified [beside the tests](../../../tests/golden/specs/entities.md).

Integrated traces use `entity-pop-v1`, retaining ordered phase snapshots, entity
transforms/path cursors, contact/reaction outcomes, per-tick hits and the first
lethal entity identity. Failed ticks publish none of those candidate outcomes.
The terrain-only `terrain-run-v1` and fixed-probe `entity-contact-v1` modes remain
available. Render interpolation never changes contact decisions.

```powershell
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --data-dir <game-folder> --level DES2 --output-directory <external-output>
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/integrated_entities.json --case-index 0 --output-directory <external-output>
```

The verifier runs headless and rendered 30/60/144 schedules serially through
completion. `--case-index` selects an authored case from the grouped synthetic
fixture; a standalone scenario needs no index. Inspect the pre-contact, hit,
POP-animation and death-camera images,
including the full controls at 640x480. All evidence stays outside both repos.

## Reproducing schedule comparisons

Generate the independent integrated fixtures with
`tools/make_golden_integrated_terrain.py --scenario-dir <external-scenarios>`;
see the [integrated corpus specification](../../../tests/golden/specs/integrated-terrain.md)
for the full generator invocation and C reference requirement. Then run:

```powershell
python tools/verify_terrain_schedules.py --godot <godot-executable> --scenario-directory <external-scenarios> --reference tests/golden/synthetic/integrated_terrain.csv --output-directory <external-output>
```

The complete-trace comparator requires ticks starting at zero and Control,
Move, Collision, Camera and Final in order. A trace must reach `tick_limit` or
end in explicit completion; a zero limit permits metadata only. Missing,
reordered, truncated, error and post-completion records fail comparison.
