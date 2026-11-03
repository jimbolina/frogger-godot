# Paths

`paths_retail.tsv` holds one row for each final `FROG` map in the supported
v3.0e archive. Columns are resource ID, archive name, path count, spline/arc/line
segment counts, metadata digest, segment digest and entity-list digest. Metadata flattens each
source-ordered path as `(path_index, path_offset, entity_list_pointer,
segment_count)`. Segment data flattens each source-ordered segment as
`(path_index, segment_index, segment_offset, end_offset, type, length)` followed
by spline matrix (12), smoothing knots (4), smoothing coefficients (12); arc
start/centre/normal triples, radius and pitch; or line start/end triples.
Entity lists flatten `(path_index, member_count, authored_entity_indices...)`
in their stored order, decoded as signed16 values through the `-1` terminator.
This ordering supplies the beaver's neighbor walk. Zero pointers mean empty
lists; negative indices other than the terminator and missing terminators are
rejected. A deliberate-break check alters one entity-list digest, requires the
retail path test to fail, then restores the generated fact.
All values are signed decimal except source offsets and pointers, which are
unsigned decimal. Nonempty lists use the [list digest convention](../README.md#digest-convention);
empty lists use `-`. The TSV stores count facts and digests of map metadata and
geometry, without retail geometry bytes or scalar excerpts.

The format source is FrogLord at
`../froggy/resources/FrogLord/src/net/highwayfrogs/editor/games/sony/frogger/map/`:
`packets/FroggerMapFilePacketPath.java`, `data/path/FroggerPath.java`, and
`data/path/segments/FroggerPathSegment{Spline,Arc,Line}.java`. The generator
reads the owner's EXE/MWD through the independent Python archive reader and
decodes PATH offsets and final record layouts independently of Godot. The
entity-list pointer is only a metadata value; FrogLord reads that list later,
outside the PATH record sequence. To regenerate:

```powershell
python -B tools/make_golden_paths.py --data-dir $env:FROGGER_DATA_DIR --out-dir tests\golden\pc-retail-v3.0e
```

`fixtures/paths.json` contains invented geometry and runner starts. Each case
has `name`, ordered `segments`, `start` with segment index, distance, speed and
flags, and `tick_limit`. Segment types are spline `0`, arc `1`, line `2`; unused
fields are omitted. `synthetic/paths_trace.tsv` records the initial state at
tick `0`, then full position, tangent and runner state after each tick. Its
expected rows come from `tools/make_golden_paths.py`'s independent Python
implementation of frozen `PATH.C`, `API.SRC/MR_SPLIN.C`, and backend vector/trig
math. Before writing, the generator requires every Python row to equal the
output of `tools/path_oracle_adapter.c`, which calls unchanged frozen objects.
The C adapter only provides test geometry and prints state. It is never loaded
by the game. Build provenance and raw logs remain outside the repositories.

```powershell
& tools/build_path_oracle.ps1 -OutputDirectory (Join-Path $env:TEMP 'frogger-path-oracle')
python -B tools/make_golden_paths.py --oracle (Join-Path $env:TEMP 'frogger-path-oracle/path_oracle.exe') --out-dir tests\golden\synthetic
```

The synthetic cases cover exact segment boundaries, both one-shot endpoints,
repeat and bounce events, a paused runner, nonlinear spline smoothing sections,
tilted arc normals, mixed spline/arc/line travel in both directions, source
single-segment overshoot, signed 32-bit line multiplication, signed 16-bit
curve narrowing, and defined zero-direction line and zero-basis arc sampling.
A new golden family requires one deliberate wrong fact in each
TSV, an observed focused test failure, restoration and a passing focused test.
