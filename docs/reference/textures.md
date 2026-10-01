# Textures

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](sources.md).

| Fact | Value |
|---|---|
| Texture banks | 46, all stored directly in the archive |
| Images | 3,477 |

- Decoding is fast enough that no cache of converted textures is needed yet.
- Every image has a padded size (what the game uploads) and an in-game size (what FrogLord exports as PNG). The golden files record a hash of each.
- **In the original, black-is-transparent is a colour key over a whole 256x256 texture page**, not a per-image rule. Rendering has to apply it per page.
- **Texture ids repeat across banks**: the five language banks, the general bank and its high-poly variant, and the low-poly variants. The lookup checks the preferred bank first; otherwise the most recently loaded bank wins, which matches how the game overwrites its pointer table.

## Format differences

Follow FrogLord for these format rules; they agree on retail values.

| Subject | FrogLord | Reference engine |
|---|---|---|
| Black-is-transparent test | A pixel is black when the top five bits of each channel are zero | Exact zero |

## Map texture contract

- A map polygon's texture number is local to the map. The map's remap table turns it into a global texture id (`TextureRemap.global_id()`), and `TextureLibrary.image_for_id()` finds the image. Sky-land polygons use the sky-land remap.
- The theme's texture bank comes from the theme book (`ThemeBookEntry.vlo_id(multiplayer, low_poly)`).
- A polygon's stored UV bytes are normalized 0–255 coordinates. Frozen C `ResolveMapPolys` converts each to an integer pixel with `coordinate * image size / 255`, then adds the image's page position. Map animation deltas are pixel offsets. The map cache reconstructs padded uploads in physical 256x256 pages; sample the final wrapped page bytes rather than clamping to an image's padded rectangle. FrogLord's `SCByteTextureUV` and the frozen C map oracle agree on the normalized conversion. See [map sampling](maps.md#rendering) for runtime colour keying and linear sampling.

Map seam inspection is recorded in [P6 validation](../validation/p6.md). Model edge inspection is in [P4 validation](../validation/p4.md); decode timings are in [P3 validation](../validation/p3.md).
