# Terrain oracle preparation validation

Validated 2026-10-01. This records oracle preparation only; project compilation
and gameplay tests are recorded by the phase validation, not inferred here.

Independent Python matched all 96 actual frozen C controller/mover records,
including every represented field, in normal, blocked and buffered-hop
scenarios. The committed synthetic CSV passed generation verification and the
strict comparator. Repeated hidden, awaited adapter runs exited 0 and produced
identical CSV SHA-256:
`0ea66d52fea4cb5ad285631d01ab418008e6f5b50c8d654d779fd256ff3d3cc1`.

Comparator deliberate-break probes failed precisely for a first-move Y changed
by one, missing final row, duplicated extra final row and wrong header field.
The restored external copy passed all 96 rows. The one-unit probe reported
row 3, scenario 0, tick 0, component move, field y16, expected -2621440,
actual -2621441, plus the supplied candidate command.

External evidence lives under
`C:/Users/janit/.codex/visualizations/2026/10/01/01a0f9d8-b24e-7b21-a293-7a6edb4cccad/terrain-oracle/`:
`trace.csv`, `stdout.log`, `stderr.log`, `failure-probes.log` and
`provenance.json`. Provenance hashes every linked frozen object/library and
the adapter source/binary. The reference repository was only read; binaries,
SDL runtime copy and logs were written outside both repositories.

See the [component contract](../reference/terrain-trace-oracle.md) for source
symbols, manually authored initial state and omitted animation/audio/score
mutations, entities, collision and camera tick. These records do not settle
retail timing, or prove a full gameplay step or RNG/camera/score-state parity.
