# Grid queries

`synthetic/grid.json` contains authored geometry, stack membership and world
queries, followed by independent expected integer facts. No retail data is
stored. Six squares cover off-centre snapping, signed height averaging,
asymmetric slopes, flat normals, a degenerate triangle and two stacked layers.
Forty queries cover the diagonal equality and both interpolation branches,
negative positions, exact tile edges, reverse layer selection with `>=`,
lowest-layer fallback, first-layer slope information and the empty-stack
`0xbabe` height result. Empty queries have selected index -1.

Inputs: `base` is X/Z, `dimensions` is X/Z count, `stacks` is row-major
`[square_count, first_square_index]`; `squares` holds four XYZ vertex words in
stored C order; `queries` is XYZ. Expected rows are:

* S, square index, average height, centre XYZ, average normal XYZ.
* Q, query index, selected height, selected square index, first-layer height,
  first-layer X slope XYZ, first-layer Z slope XYZ. Empty rows stop at index.

`tools/make_golden_grid.py` independently implements the frozen C formulas in
Python. Every generation or verification must compare all answers with a thin
external adapter calling the already compiled frozen GRID.C object and its
compiled math dependency. The adapter neither replaces grid functions nor
derives expected values. Its zero trig table satisfies an unused symbol from
the math object: queried normalization, cross product and square root routines
do not read it. Bounds validation is the caller's responsibility; the corpus
never makes an out-of-grid C query.

Reproduce on Windows, supplying an output folder outside any repository:

```powershell
tools/build_grid_oracle.ps1 -OutputDirectory <external-folder>
python tools/make_golden_grid.py --c-oracle <external-folder>/grid_oracle.exe --verify
```

The build reads `../froggy/engine/build/compile_commands.json` for the existing
GRID compiler/includes/object. It compiles only this project's transport and
links the frozen GRID and math objects; it never rebuilds or writes froggy.
The build prints SHA-256 provenance for sanitized GRID source, GRID object,
math object and adapter binary. These checks prove the frozen engine's current
normalization semantics, including its libm rounding; they do not resolve the
PC gameplay tick rate or enable movement.

The same provenance is saved as `provenance.json` beside the external binary.

`pc-retail-v3.0e/grid_facts.tsv` exhaustively records 78 retail GRID packets.
Header scalars include dimensions, authored cell lengths and C-derived centred
base. List digests hash row-major stack count/cliff byte/first-layer index;
each square's flags/polygon pointer/resolved global polygon index; four stored
vertex indices followed by their four XYZ corners; every average Y; and every
snapped XYZ centre. The fourth triangle word is retained rather than replaced
by the renderer's three-corner list. No source bytes are stored. FrogLord's
`FroggerMapFilePacketGrid` and `FroggerGridStack`/`FroggerGridSquare` define
the packet, unsigned cliff byte and pointer layout. Python independently
decodes these facts; the frozen C overlap above proves query formulas on the
synthetic fixtures, rather than claiming exhaustive retail C query comparison.

Generate retail facts by appending `--retail-data-dir <owner-data-folder>` to
the Python command (omit `--verify` only when regenerating synthetic facts is
also intended). The retail test compares all five digest families and header
scalars; its only approved skip is an unset `FROGGER_DATA_DIR`.

Deliberate break: increment the first S average-height fact, run `--verify`,
require `Grid golden differs`, restore the file, then require verification to
pass. The Godot query test also compares the independently authored facts.
