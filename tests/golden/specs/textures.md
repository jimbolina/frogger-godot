# Texture banks (`pc-retail-v3.0e/vlo_*`)

Every PC texture bank (VLO, signature `2GRP`) in the archive: 46 banks,
3,477 images, all stored directly in the MWD (none of the retail banks is
inside a WAD, though both the generator and the Godot side can read one there). No
pixel data is stored: each image is described by its header fields and two
SHA-256 digests of its decoded pixels.

**Decoded pixels, by specification** (both implementations follow this text,
which restates FrogLord's reading of the PC format):

- bytes R, G, B, A per pixel (8 bits each), rows top to bottom, pixels left
  to right, no row padding;
- the file stores each pixel as the bytes A, B, G, R; R, G and B are copied;
- A is 255, except 0 when the image's flag bit 5 ("black is transparent")
  is set and R, G and B are all below 8, i.e. `(R | G | B) & 0xF8 == 0`.
  The stored A byte is ignored (the game never reads it; it is 0 in every
  retail image);
- the **padded** digest covers the whole stored image (padded width x
  height), the texture the game uploads;
- the **unpadded** digest covers only the in-game region, width x height
  starting at `left = (padded width - width) / 2`,
  `top = (padded height - height) / 2`. This is what FrogLord's image
  export writes to PNG (its "no padding" export setting, transparency on).

| File | One row per | Columns |
|---|---|---|
| `vlo_files.tsv` | texture bank (46) | resource id, file name, where it is stored (`mwd` or `wad <id>`), image count, number of FrogLord texture renames |
| `vlo_images.tsv` | image (3,477) | resource id, position in the bank, texture id, VRAM x and y, padded width and height, width and height, u, v, flags, blend mode (bits 8-9 of the page word), page (VRAM y / 256), padded digest, unpadded digest |
| `vlo_summary.txt` | fact | bank and image counts, images with bit 5, fully transparent texels, stored non-zero alpha bytes (0), texels that are near-black but not exactly black (0: the "below 8" and "exactly 0" rules give identical results on retail data), banks inside WADs, renamed textures |

### How it was generated

```
python3 tools/golden/make_golden_vlo.py <folder with FROGGER.EXE and FROGPSX.MWD> tests/golden/pc-retail-v3.0e
```

(Python 3, standard library only; about 15 s.) Written from FrogLord's
`vlo2/VloFile`, `VloImage` and `VloUtils` Java sources, sharing only
`make_golden_manifest.py`'s archive readers. It stops with an error unless
every header passes FrogLord's own load-time checks: headers start at byte
12; every image's pixels start at the next 4-byte boundary with zero bytes
in between; the texture page word equals `page | blend mode << 8`; the
stored u/v equal the image's position in its page plus its padding; and the
padding is the same horizontally and vertically.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.
