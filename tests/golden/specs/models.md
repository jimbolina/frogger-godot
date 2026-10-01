# Models (`pc-retail-v3.0e/mof_*`)

Every model file (MOF) of the archive: 434 files, all of them inside WADs.
One is a 4-byte placeholder (`DUMY`), 355 are static models and 78 are
animated models holding 78 static models between them. 22 of the static
models are incomplete: they store their own polygons and take their shape
from another model. No model data is stored: each part is described by its
counts and by digests of its value lists.

Rows describe **what the file itself holds**. An incomplete model's rows
give the counts in its own headers and its own polygons; what it borrows is
in the rows of the model it borrows from. Nothing that FrogLord adds or
changes for display is included.

**Value lists, by specification** (both implementations follow this text).
Each uses the [shared list-digest convention](../README.md#digest-convention);
an empty list is written `-`.

- vertices, normals: x, y, z of each vector of the part's first partcel, as
  signed 16-bit values, in stored order;
- bounding box: x, y, z of the 8 corners of the first partcel's box;
- indices: for each polygon in stored order, its type number, then its vertex
  indices, its environment normal indices and its normal indices, each **in
  the order the file stores them** (FrogLord swaps the last two of a quad
  when it loads; the digests do not);
- uvs: for each textured polygon, u then v of each corner in stored order;
- image ids: for each textured polygon, its image id;
- colours: for each polygon, red, green, blue and the code byte;
- hilites: for each hilite, its type, what it is attached to (1 vertex,
  2 polygon) and the index;
- texture animation image ids: the image id of every frame of every texture
  animation of the part, in stored order.

| File | One row per | Columns |
|---|---|---|
| `mof_models.tsv` | model file (434) | resource id, file name, type id, size, kind (`dummy`, `static`, `animated`), first four bytes in hexadecimal, flags, incomplete (0/1), the resource it borrows from (-1 = none), static models, model sets, then totals over its parts: parts, partcels, vertices, normals, polygons, textured polygons, hilites, collision primitives, matrices, flipbook animations, polygons with animated textures, texture animations; number of different image ids, digest of those ids in rising order |
| `mof_parts.tsv` | part (1,009) | resource id, static model inside the file, part, flags, partcels, vertices and normals per partcel, polygons, hilites, collision primitives, matrices, flipbook animations, polygons with animated textures, texture animations, different bounding boxes, polygons of each of the 16 types (comma separated), then the digests in the order listed above |
| `mof_forms.tsv` | form of a level (1,550) | level number and code (`GENERAL` and `GENERAL_MULTIPLAYER` with level -1 stand for the GENERAL forms on their own), theme, form number in its theme, form name, model id, the form's "no model" flag, whether the model comes from the GENERAL WAD, position in the WAD, then for high-poly and for low-poly: the WAD, the resource at that position (-1 = none) and its kind (`none`, `dummy`, `static`, `animated`) |
| `mof_summary.txt` | fact | counts of each kind, totals, polygons of each type, WAD slots of each kind |

Three GENERAL forms (`GEN_BONUS_FROG`, `GEN_BONUS_FLY_GRE`, `GEN_LADYFROG`)
have model id 0, which gives position -128 and so no model. FrogLord
computes the same position.

### How it was generated

```
python3 tools/make_golden_mof.py <folder with FROGGER.EXE and FROGPSX.MWD> tests/golden/pc-retail-v3.0e
```

(Python 3, standard library only; about 3 s.) Written from FrogLord's
`mof2` Java sources (`MRModel`, `MRBaseModelData`, `MRStaticMof`,
`MRMofPart`, `MRMofPartCel`, `MRMofPolygonBlock`, `MRMofPolygon`,
`MRAnimatedMof`, `MRMofHilite`, `MRCollprim`), `SCUtils.makeModel` for which
model an incomplete one borrows from, and `FroggerFormEntry` for which model
a form uses. It shares `make_golden_manifest.py`'s archive readers and
`make_golden_exe_tables.py`'s readers of the level, theme and form tables,
and no code with the Godot project.

### Why the facts can be trusted

The script stops with an error unless every file passes the checks FrogLord
makes when it loads a model:

- the signature fits the kind the flags state;
- the length a model states equals where its last polygon ends and the
  number of bytes present; for an animated file, where its model table ends;
- a static model inside an animated file runs exactly from its own start to
  the start of the next one (FrogLord's rule), and that span equals the
  length the model states for itself (the reference engine's rule);
- the flags of a model and of each part equal what the model holds
  (animated textures, flipbook); an animated file's flags are 0x110008;
- every word the game fills in while running is zero in the file, as are
  the clut and texture page words and the padding of every polygon;
- polygon types are below 16; every hilite and texture animation names a
  vertex or polygon that exists, of the stated type;
- every block of vertices and normals lies inside the model's vector pool,
  on an 8-byte step.

Its totals agree with those the C port of the game documents for this
build, found there independently: 731 static and 136 animated models
counted per WAD slot, and no polygon of the environment-mapped or line
types.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.
