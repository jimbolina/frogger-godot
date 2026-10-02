# Paths and inspection

The [map decoder](../data/maps.md) reads final-PC PATH records using FrogLord's
packet and segment layout. `PathSetup` copies valid, supported records into
detached `PathDefinition` values with source, resource, path and byte-offset
identity. Unknown segment types and unsafe geometry produce source-located
diagnostics and omit that whole path; valid neighboring paths stay available.
Structural pointer and payload errors fail the map. The separate path entity
list pointer is metadata only here. Final-PC coordinates are signed 16-bit
source words; stored lengths, arc radius/pitch and spline coefficients are
signed 32-bit words. These are decoded source widths, not a promise that any
arbitrary numeric geometry is safe to evaluate.

`PathRunner` owns one copy of a definition and one mutable cursor. `PathStart`
contains segment index, distance, speed and flags. Reset applies those flags
before the first position evaluation, following the source reset-style path
initialization. The initial snapshot is tick 0, and
`step(0)` creates tick 1. The runner returns copied snapshots, so callers
cannot alter its state. It evaluates line, arc and spline positions and
tangents from stored integer lengths and coefficients. The selected frozen C
behavior makes at most one segment transition per update; high speed can leave
a distance beyond the next segment, which the evaluator extrapolates. Repeat,
bounce and one-shot endpoints follow the source flags. Transient endpoint flags
clear at the start of the next update.

Setup rejects zero or negative segment length, nonpositive arc radius,
arc circumference beyond source signed-32 arithmetic, total path length beyond
signed-32 arithmetic, missing 12/4/12 spline arrays and unknown segment types.
Zero-direction lines and degenerate arc vectors retain the source backend's
defined results. These checks protect the component evaluator while preserving
decoded source facts and diagnostics.

The map viewer optionally draws a sampled path, cursor and tangent, and uses
the same 30 Hz clock as map animation. The initial inspection start is segment
0, distance 0, speed 16, active, forward and repeat. Path controls define an
inspection start; changing one resets the clock. Seeking backward replays from
that start. The overlay is hidden by default and always hidden in the map-slice
reference preset. Its visual samples and marker never drive gameplay state.

`EntitySetup` now attaches authored `PATH_INFO` to independently owned cursors
for supported moving base transforms. The [entity contract](entities.md) defines
this bounded use; moving-platform collision and other entity behavior remain
future work. The independent [golden specification](../../../tests/golden/specs/paths.md)
defines source comparisons.
