# Static terrain grid

GRID is decoded source data. `TerrainGridSetup` makes detached gameplay
definitions; `GridQueries` operates only on integer game units. No frog movement,
collision response, clock or input behavior is implemented by this slice.

## Format and setup

FrogLord `FroggerMapFilePacketGrid.loadBody`, `FroggerGridStack.load` and
`FroggerGridSquare.load` define the final PC format: four 16-bit header fields,
row-major four-byte stacks (unsigned count, authored cliff byte, unsigned first
layer index), then ordered eight-byte layers (32-bit flags, map-relative polygon
offset). Stack indices must be contiguous, including empty cells. References
must identify an exact polygon start; bounds remain within the GRID packet.
All flags, offsets, layer order and triangle fourth vertex words are retained.
No gameplay meaning is inferred from flag combinations.

Odd dimensions and cell lengths other than 256 decode with warnings. Gameplay
setup requires positive dimensions and 256-unit cells because frozen C
hardcodes shifts and interpolation lengths. Odd dimensions remain supported:
FrogLord warns but continues loading, and frozen C defines their centred base.
Its world-bitmask interpolation retains the resulting half-cell offset; gameplay
does not replace that behavior with grid-relative interpolation. Setup validates all four corners
of referenced terrain polygons, rejects G2 and invalid fourth words, and copies
coordinates and flags. Inactive fourth words on unreferenced triangles remain
legal for inspection/rendering. Definitions are treated as immutable after setup.

## C query behavior

`mapload.C` sets base X/Z to `-(length * count) >> 1`; `GRID.H` converts world
coordinates with signed32 `(coordinate - base) >> 8`. Coordinate arguments
are narrowed to the source signed32 domain; subtraction wraps before shifting. Bounded queries return null for
outside or empty cells, instead of C's assertion/unsafe access or `0xbabe`
sentinel. `GetGridStackHeight` shifts the unsigned authored byte by six; it is
not recomputed from terrain corners.

`GetGridSquareHeight` averages four stored corners with `>> 2`.
`GetGridSquareCentre` uses that Y, snapping the four-corner XZ average to the
containing cell centre, then narrows every component to signed16 (`MR_SVEC`).
An odd centred base can snap X/Z 32767 to 32768, which wraps to -32768.
`GetGridInfoFromWorldXZ` chooses the first layer and
uses world `x & 255`, `z & 255`. Its diagonal includes equality in the top-left
triangle. Each signed interpolation product is shifted separately; slopes are
normalized to length 4096. `GetHeightFromWorldXYZ` searches layers backwards,
choosing the first with any corner Y greater than or equal to the supplied Y,
or the lowest layer if none match. Authored layers are never reordered.

`GetGridSquareAverageNormal` calculates two scaled cross products, normalizes
each, averages with signed shifts, and normalizes again. A repeated third/fourth
corner uses only the first triangle. Normalization matches the frozen portable
engine's `mr_stub_math.c/VectorNormal`: explicit double inputs, square root and
4096/length scaling, nearest integer with
ties away from zero. OuterProduct12 products/subtractions wrap to the compared WIN95 signed32
`long` before shifting by12. Valid extreme signed16 terrain can therefore
produce a nearly flat normal rather than its mathematical steep normal.
The width corpus checks this behavior and queries outside the board observe
only source coordinate macros, avoiding C's unsafe stack access. It does not
claim bit equivalence with PSX GTE math.

## Differences from editor calculations

FrogLord's grid helpers divide signed averages/products, which truncate toward
zero; frozen C shifts round negative values down. Gameplay follows C. The
editor's triangle calculations substitute the last active vertex after checking
padding; C reads all four stored words directly. We preserve and use the fourth
word. FrogLord calls the stored byte a cliff-height value; frozen C declares
it unsigned and scales it without changing sign. Both meanings remain visible.

Independent synthetic Python facts checked against frozen C cover averages,
centres, normals, both triangles, negative values, diagonal equality, multilayer
selection, empty cells, odd dimensions and signed16 centre wrapping. See the [golden index](../../tests/golden/README.md).
