# Synthetic terrain component oracle

This is offline validation tooling. The game runs in GDScript; these C adapters
are not runtime dependencies and end users do not need a C compiler.

`tools/terrain_oracle_adapter.c` supplies independent movement comparisons.
It calls the existing frozen engine's real `ControlFrog` and then `MoveFrog`,
recording a row after each call. Its component calls have no wall clock.
The owner's selected source-port timing is
documented separately in [PC timing](../gameplay/pc-timing.md).

Three authored scenarios each reset the C random seed to 12345, frog/input/camera
state, a 4x4 flat safe grid and caller-owned frog matrix/trail storage. One north
press at tick zero drives a normal hop; the other marks its destination unusable
and exercises the blocked input path. Six move calls complete the normal hop.
The first update has Y=-40 and forward velocity 2796202 in 16.16 units; the sixth
snaps from (-128,0,-128) to (-128,0,128). Blocked input preserves the initial
position. These independently hand-derived positive controls fail the adapter
if the actual component results disagree. Remaining idle ticks expose the
stationary state. Input is supplied through the real `MRInput` pad fields and
the frozen default control mapping, rather than bypassing its controller.

The third scenario presses east during the north hop at tick 2, holds it
through tick 8 and releases at tick 9. The real jumping controller buffers one
key; the real stationary controller consumes it at tick 6 while east is held,
and the east hop completes on move 11 at (128,0,128). See `FROG.C`'s
`FrogModeControlJumping` and `FrogModeControlStationary` through the
[source locations](../sources.md). This tests input buffering within the two
components, without adding a second input implementation to the adapter.

The adapter links the frozen real-source library and existing common objects.
It does not rebuild or write the frozen reference repository. Actual grid,
movement, internal matrix update, empty-zone query and landing camera rotation
code execute. The synthetic zone header has zero zones and camera modification
matrix starts as identity. The trail effect has real writable effect/trail
storage because `JumpFrog` writes that structure even on a normal hop.

Three explicit GNU linker wrappers count and omit calls:
`FrogRequestAnimation`, `MRSNDPlaySound` and `AddFrogScore`. They do not implement
animation state, audio, authoritative score mutation or score display.
`AddFrogScore` normally changes points and can change lives, lighting, time or
powerups before sprite work; the wrapper suppresses all those mutations.
Its counters record call counts only and make no score-conformance claim.
The frog's initial stationary state is authored directly, rather than produced
by `ResetFrog`, which enters startup camera/bounce and animation/croak setup.
Each scenario explicitly sets recording and cheat control off, and game mode
to level play; the trace does not validate retail boot or reset behavior.
The scenarios do not use rolling, superjump,
powerups, tongue, croak, fall deaths or entities; those paths need separate
fixtures before inclusion. No entity update, `CollideFrog`, or `UpdateCamera`
component tick is called. Therefore these traces prove the flat-grid controller
and mover component sequence only, not the complete gameplay loop or collision
and camera conformance. They are not substitutes for retail timing measurement.

Reproduce with an external output folder:

```powershell
tools/build_terrain_oracle.ps1 -OutputDirectory <external-folder> -Run
```

The script compiles only this transport, copies the frozen SDL runtime DLL to
that external folder, and runs a hidden awaited process with stdout/stderr logs.
The adapter suppresses unattended Windows crash dialogs. Nonzero exit fails;
no exception or partial trace is accepted. It saves clean `trace.csv` and
`provenance.json` containing adapter source/binary hashes and every linked
reference object/library hash. The frozen common-object startup message is
retained in `stdout.log`, outside the CSV. A second identical run must produce
the same CSV digest. Traces use full 16.16 position/velocity integers, cell,
count, flags, mode, input, direction and cumulative omitted request counts.
It also records buffered key/input counts and pressed/held pad fields.
Pad fields are normalized through the frozen control mapping to logical
N/E/S/W bits 1/2/4/8; `input` remains the frozen direction enum (N=0, E=1,
no input=128). `mode` uses stationary=0 and jumping=1.

`tools/compare_terrain_trace.py <reference.csv> <candidate.csv>` requires the
exact represented schema and all 96 records in scenario/tick/component order.
Every numeric field compares as an integer. It fails at the first differing
field with row, scenario, tick and component context; missing, extra or
reordered rows and malformed schemas also fail. Optional `--candidate-command`
adds the reproduction command to diagnostics. It does not compare omitted
animation/audio/score state, full camera state, collision, RNG internals or a
wall-clock schedule. A matching file proves only these represented fields.
`--scenario=0|1|2` explicitly selects 32 records from a fully validated reference
family and requires the candidate to contain exactly that scenario; other
candidate scenarios fail rather than being silently discarded.

`tools/make_golden_terrain.py` independently implements the three declared
flat-fixture scenarios in Python, including integer gravity, six-call hopping,
cell recomputation, snap/flags, input buffering and counted omitted calls.
It cross-checks every expected field with the actual frozen C component trace
before writing `tests/golden/synthetic/terrain_components.csv`. This is a
fixed scenario generator, not a second whole game implementation. It never
reads Godot output. Use `--c-oracle <external-folder>/terrain_oracle.exe` to
generate, or add `--verify` to require the committed text facts to match.

## Separate default camera fixtures

The adapter's `--camera` route calls real `ResetCamera` and `UpdateCamera`
on separate authored fixtures. `tools/make_golden_camera.py` independently
calculates and cross-checks 327 camera records before saving text facts.
See the [camera specification](../../../tests/golden/specs/camera-components.md)
for scenario inputs, field ordering and the narrow world-target reconstruction.
This route supplies caller-owned camera matrix storage and an authored GENE
header for default offsets. It initializes the frozen trig table using
`MRStub_GpuInit(NULL,0)`, which creates no display. Controller/mover and camera
families remain distinct; their isolated matches do not prove the ordering or
state exchange of a complete coupled gameplay step.

## Ordered integration fixtures

The [integrated terrain family](../../../tests/golden/specs/integrated-terrain.md)
executes control, movement, collision, camera, animation scripts and pose in
source order over shared caller-owned state. Independent Python composition
checks the exact represented fields before facts are accepted. The component
boundary still omits score mutations, audio, entity systems, renderer effects
and mainloop setup callbacks. Its five public game phase snapshots match those
facts; complete JSONL replay comparison covers additional game state separately.
