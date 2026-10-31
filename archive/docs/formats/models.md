# Models

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](../../../docs/reference/sources.md).

| Fact | Value |
|---|---|
| Model files | 434, all inside WADs: 1 placeholder, 355 static, 78 animated |
| Static models, counting those inside animated files | 433 |
| Incomplete models | 22 |
| Parts | 1,009 |
| Polygons | 15,456, of which 6,425 textured |
| WAD slots | 2,890: 2,023 placeholders, 731 static, 136 animated |

- **What a file is shows in its first bytes, never in its name.** The four `.XMU` files are ordinary static models.
- **A model id is a position in a WAD, and placeholders count.** A level's WAD has a slot for every model of its theme. The slots the level does not use hold the same 4-byte placeholder (resource 188), which fills 2,023 of the 2,890 slots.
- Forms in the general theme, and any form whose model id is 128 or more, use model `id - 128` from the general WAD. Other forms use the level's own WAD from the map book. A multiplayer level uses the multiplayer general WAD. Maps set bit 15 on a form id that refers to the general theme.
- Three general forms (`GEN_BONUS_FROG`, `GEN_BONUS_FLY_GRE`, `GEN_LADYFROG`) have model id 0 and so no model, though only the second is flagged as having none.
- **There are 22 incomplete models, not only the checkpoints.** Checkpoints 2 to 5, multipoints 2 to 5 and the multiplayer frogs 2 to 4, each in a high-poly and a low-poly version. Each takes its shape from the nearest earlier complete model in the index, and differs only in the colours and textures of its polygons.
- **Every static model inside an animated file states its own length, and it equals the distance to the next one.** FrogLord's rule and the reference engine's give the same result on retail data.
- Only two models store matrices for their collision shapes: `JUN_PLANT.XAR` and its low-poly version. Each stored `MR_MAT` is 32 bytes: nine signed 16-bit rotation entries row by row, a pad short and three signed 32-bit translations. They are decoded; collision uses only the rotation.
- Only polygon types 0 to 7 occur. There is no environment-mapped polygon and no line.
- **A quad is stored going round its edge.** Its triangles are corners (0, 1, 3) and (1, 2, 3). Texture coordinate k and normal k belong to corner k. FrogLord swaps the last two entries of each list when loading; this project keeps the stored order.
- **A polygon has one colour whatever its type**, and its normals are only for lighting.
- A texture coordinate is 0 to 255 across the in-game part of the image, with v counted from the top. The game turns it into a whole pixel, `coordinate * size / 255`.
- Each level's high-poly models find all their textures in the general bank and the theme's bank, with one exception: the multiplayer jungle WAD carries the eight plinths of the single-player levels, and some of their textures are not in the multiplayer jungle bank. Such polygons are drawn untextured.
- Dark models are often dark on purpose. The lower half of each log has polygon colour (7, 22, 51).

## Format differences

Follow FrogLord for these format rules; they agree on retail values.

| Subject | FrogLord | Reference engine |
|---|---|---|
| Which model is incomplete | The first part's partcel pointer is 0x40 | The same, and the model has one part |
| Where a static model inside an animated file ends | At the start of the next one; the last at the model table | At the length the model states |
| How many matrices a part stores | As many as fit before the next section | The highest matrix number its collision shapes use, plus one |
| What a hilite is attached to | A number: 1 vertex, 2 polygon | Flag bits with the same values |

## Open behavior question

FrogLord selects the multiplayer general WAD for multiplayer levels, and this project follows it. Runtime verification remains open. See [animation](animation.md) for inherited playback data.
