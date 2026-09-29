# Frogger (1997) in Godot

A rewrite of **Frogger** (Hasbro Interactive / Millennium Interactive, 1997;
the PC release, also known as *Frogger: He's Back*) in
[Godot 4](https://godotengine.org) with statically typed GDScript. The aim is
the original game's feel on modern desktops (Windows, Linux, macOS), running
on the data from the player's own copy of the PC game, and staying compatible
with levels and changes made in [FrogLord](https://github.com/Kneesnap/FrogLord),
the community's Frogger editor.

This is an early stage: the project can find and identify the game files,
read every file in their archives (the MWI index, the MWD archive, WAD
bundles and PowerPacker compression) and decode the game tables held in the
executable (levels, themes, forms, texture remaps and pointers, entity
scripts, music, level select, demos, bugs). There is no gameplay yet.

## No game data is included

This repository contains **no part of the original game**: no executable, no
archives, no textures, models, sounds, music or video. You need your own copy
of the retail PC game. The project reads everything it needs at run time from
your files; nothing from them is ever copied into this repository, and tests
that need them only store facts about them (file sizes, counts, checksums).

Supported data: the PC retail builds FrogLord knows as `pc-retail-v3.0e`
(the common worldwide release, the reference for this project),
`pc-retail-v1.0` and `pc-retail-v3.0e-vogons`. PlayStation data is not supported.

## Pointing the game at your files

The game needs the folder holding `FROGGER.EXE` and `FROGPSX.MWD` from the
installed game (or FrogLord's saved `modded_FROGGER.EXE` and
`modded_FROGPSX.MWD`; when both kinds are in one folder the modded files are
used). It looks, in this order, at:

1. the command line: `godot --path . -- --data-dir=<folder>`
2. the environment variable `FROGGER_DATA_DIR=<folder>`
3. the folder remembered from the last successful start.

The build is recognised the way FrogLord recognises it: by the build
information FrogLord writes into a modded executable, or else by the CRC-32
checksum of the executable, which FrogLord's version files list.

Running the project currently opens a screen saying which files and which
build were found (with a summary of the archive index and counts of the
tables read from the executable), or how to set the folder.

## Running the tests

Tests use [GUT](https://github.com/bitwes/Gut) and run headless:

```
GODOT=/path/to/godot tools/run_tests.sh              # bash (Linux, macOS, Git Bash on Windows)
$env:GODOT="C:\path\to\Godot.exe"; tools\run_tests.ps1   # PowerShell
```

Set `FROGGER_DATA_DIR` to also run the tests that need the retail files
(`tests/golden/`); without it those are listed as `SKIPPED` by name. The
last line is a summary such as `SUMMARY: PASS=70 FAIL=0 SKIP=3 EXIT=3`.

| Exit code | Meaning |
|---|---|
| 0 | every test ran and passed |
| 1 | a test failed, or a script does not compile |
| 2 | Godot was not found |
| 3 | nothing failed, but some tests were skipped (a skip is never a pass) |

Every script is compiled before the tests run (`tools/check_scripts.gd`),
with the project's strict typing warnings treated as errors.

## Layout

| Path | What |
|---|---|
| `src/legacy/` | Readers for the original data formats and executable: `io/` (byte reading, PowerPacker), `config/` (FrogLord configs and name lists), `source/` (finding the game files), `formats/` (MWI, MWD, WAD), `exe/` (the game tables in the executable). `game_data.gd` puts them behind one object. Pure data classes with no scene tree, testable headless. |
| `src/presentation/` | Screens. |
| `scenes/` | Godot scenes (`boot.tscn` is the start scene). |
| `tests/unit/` | Tests that need no game files. |
| `tests/golden/` | Tests against the retail files, and the committed facts they compare with. |
| `tools/` | Test runners, a script compile check, and the golden-data generators `make_golden_*.py` (see `tests/golden/README.md`). |
| `third_party/` | FrogLord's configuration files, unmodified (see `third_party/README.md`). |
| `addons/gut/` | The GUT test framework, unmodified. |

## Licence

The licence for this project's own code is **to be decided by the project
owner**; until then, no licence is granted. Third-party material keeps its own
licence: FrogLord's configuration files (MIT, `third_party/froglord_cfg/LICENSE.md`)
and GUT (MIT, `addons/gut/LICENSE.md`).

## Credits

- **FrogLord** by Kneesnap and the [Highway Frogs](https://highwayfrogs.net)
  community: the file-format research this project builds on, and the
  configuration files it ships.
- The Highway Frogs community's documentation of Frogger's formats and the
  released original PlayStation source code.
- **GUT** by Butch Wesley, for testing.

Frogger is a trademark of Konami. This is an unofficial fan project and is not
affiliated with or endorsed by the rights holders.
