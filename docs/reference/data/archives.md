# Archives

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](../sources.md).

| Fact | Value |
|---|---|
| Index entries | 746 |
| WADs | 84 |
| Compressed resources | 210 |
| Resources stored directly in the archive | 312 |
| WAD children | 2,890, of which 434 are distinct |

- No WAD child is compressed on its own.
- The index inside the executable is the authoritative one. FrogLord writes the index back into the executable; the standalone `.MWI` file is a copy.
- Always resolve archive offsets through the loaded index. FrogLord moves and resizes files when it saves.

Schemas and regeneration: [archive golden specification](../../../tests/golden/specs/archives.md).
