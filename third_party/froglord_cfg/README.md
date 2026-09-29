# FrogLord configuration files (third-party, unmodified)

These files come from **FrogLord**, the Frogger modding toolkit by Kneesnap and
the Highway Frogs community:

- Repository: https://github.com/Kneesnap/FrogLord
- Commit: `5416ae4f0a1e2fd322527e67f01172563b6086e1` (committed 2026-07-26)
- Source folder in that repository: `resources/games/frogger/`
- Licence: MIT, see `LICENSE.md` in this folder (copied from the repository root).

They are copied **unmodified** (byte-identical to the Git blobs at that commit,
LF line endings). Only a subset is included:

| Folder | What was copied |
|---|---|
| `versions/` | the eight `pc-*.cfg` build descriptions (this project supports the PC data family only) |
| `forms/`, `entities/`, `scripts/`, `sounds/`, `images/`, `vlo/`, `anims/` | every `.cfg` name list, since version files refer to them by name and some builds use FrogLord's PlayStation-era lists as defaults |

The game reads these files at run time: the version file tells it where the
tables are inside the player's `FROGGER.EXE`, and the name lists give the
game's numbered things (sounds, forms, entity types, scripts, textures) their
names. Keeping them unmodified means a FrogLord update can be dropped in as-is.

To refresh: check out the wanted FrogLord commit and copy the same files with
Git's line-ending conversion turned off, for example

```
git -C FrogLord -c core.autocrlf=false archive HEAD LICENSE.md resources/games/frogger | tar -x -C /tmp/fl
```

then update the commit hash above.
