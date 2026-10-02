# Terrain component records

`synthetic/terrain_components.csv` contains 96 text fact rows: three authored
scenarios, 16 ticks, two components per tick. It contains no retail bytes.
The [component oracle contract](../../../docs/reference/terrain-trace-oracle.md)
owns fixture setup, represented fields, omitted systems and C linkage.

Columns exactly match `compare_terrain_trace.FIELDS`: scenario/tick/component,
16.16 XYZ position/velocity, current cell, remaining move count, flags/mode,
current direction input/facing, counted animation/audio/score calls, buffered
input counts and logical pressed/held N/E/S/W masks. All values other than
component are decimal integers. Component order is `control`, `move`.

Reproduce independent Python facts and exhaustive compiled frozen C overlap:

```powershell
tools/build_terrain_oracle.ps1 -OutputDirectory <external-folder> -Run
python tools/make_golden_terrain.py --c-oracle <external-folder>/terrain_oracle.exe --verify
python tools/compare_terrain_trace.py tests/golden/synthetic/terrain_components.csv <external-folder>/trace.csv
```

For deliberate-break validation, change one first-hop move Y by one, require
the comparator to report that exact row/component/field, then restore and pass.
Removing the final row must independently fail as missing data. The generator
also fails if a committed fact changes, after all C/Python overlap checks pass.
Godot tests compare gameplay component snapshots with these independently
generated facts. Score request counts do not assert authoritative score state:
the C wrapper deliberately omits score mutation, so any score assertions must
be backed separately by source logic. These traces do not claim full gameplay
loop, camera/collision/RNG-state or retail tick-rate conformance.
