# Frogger (1997) in Godot

[![Tests](https://github.com/jimbolina/frogger-godot/actions/workflows/tests.yml/badge.svg)](https://github.com/jimbolina/frogger-godot/actions/workflows/tests.yml)

A rewrite of **Frogger** (Hasbro Interactive / Millennium Interactive, 1997,
the PC release also known as *Frogger: He's Back*) in
[Godot 4](https://godotengine.org) for Windows, Linux and macOS. It aims for
the original game's feel on a modern desktop: the same 30 Hz movement,
collisions and camera as the original code, with real lighting and shadows.

The repository holds none of the original game. The port plays from **your
own copy of the retail PC game**, which it imports on the first start. The
file formats were decoded following [FrogLord](https://github.com/Kneesnap/FrogLord),
the community's Frogger editor, and the port plays FrogLord's saves as mods.

The accepted levels are ORG1–ORG5, SUB1–SUB5, FOR1–FOR2, VOL1–VOL3,
CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4, with the
single-player HUD, high-score tables, options, attract demos, pause and
game-over pages, sound effects and the CD music.

## Play it

1. Download the zip for your system from the
   [releases page](https://github.com/jimbolina/frogger-godot/releases):
   `Frogger-<version>-windows-x86_64.zip`, `-linux-x86_64.zip` or `-macos.zip`.
2. Unzip it and start the game. The builds are not code-signed, so Windows
   SmartScreen and macOS Gatekeeper warn on the first start; the
   [install notes](docs/reference/developer-setup.md#packaged-builds) say how
   to get past each.
3. On the first start, point the setup screen at the folder of your Frogger
   PC game (version `pc-retail-v3.0e`, holding `FROGGER.EXE` and
   `FROGPSX.MWD`) and, for the music, at its Alcohol 120% disc image (`.mds`
   with the `.mdf` beside it). The import takes about twenty seconds.
4. Choose a language, window mode, volumes and optionally a texture pack or
   a FrogLord save folder, then press Play. Later starts go straight to the
   main menu.

Hold Shift while the game starts, or start it with `--setup`, to open the
setup again. Settings, scores and the imported game live in the user folder:
`%APPDATA%\Godot\app_userdata\Frogger` on Windows,
`~/.local/share/godot/app_userdata/Frogger` on Linux and
`~/Library/Application Support/Godot/app_userdata/Frogger` on macOS. The
[first-run setup reference](docs/reference/setup.md) describes every page.

## Controls

The retail keys apply in a level. Options on the main menu rebinds them.

| Key | Action |
|---|---|
| Arrow keys | Hop |
| Return | Super hop in the facing direction, or skip the checkpoint bonus |
| Right Ctrl | Tongue |
| Right Shift | Croak (the nearest baby or gold frog within sixteen squares answers) |
| `'` and `;` | Turn the camera |
| Escape | Pause (Continue or Quit) |
| 0 (top row) | Debug graphics panel: display, quality, shadows, bloom, effects and look |

Menus use Up/Down, Enter or Space and Escape. Name entry hops the frog over
letter lilies with the arrows and picks with Enter. Score, lives and level
unlocks carry between levels and are saved. Left alone, the main menu plays
the attract demos.

Useful launch flags, given after `--` when running from the editor:
`--language=en|it|de|fr|es` overrides the menu language, `--no-audio` mutes
everything, `--attract` starts the first demo at once and `--level=ORG1`
launches a level directly.

## Texture packs and mods

A **texture pack** replaces some or all textures with redrawn, higher-resolution
images. Copy the pack's folder into `texture_packs` in the user folder (or
beside the executable) and choose it on the setup screen. Textures a pack
leaves out keep their original look. Making a pack is described under
[texture packs](docs/reference/assets.md#texture-packs).

A **FrogLord save** (`modded_FROGGER.EXE` and `modded_FROGPSX.MWD`) is played
as an overlay on your import: name its folder on the setup screen. Mods may
repoint levels to behaviour the port already implements; they cannot add
code. Editing a level while it runs is covered under
[FrogLord while playing](docs/reference/setup.md#froglord-while-playing).

## Build from source

You need Git LFS, Python 3, [uv](https://docs.astral.sh/uv/), Godot 4.5.1 and
your own copy of the game:

```sh
git lfs install && git clone https://github.com/jimbolina/frogger-godot.git
cd frogger-godot
export FROGGER_DATA_DIR=/path/to/FROGGER     # holds FROGGER.EXE and FROGPSX.MWD
export FROGGER_DISC=/path/to/FROGGER.mds     # optional, for the music
tools/setup_dev.sh --download-godot --import
tools/play.sh --level=ORG1
tools/run_tests.sh
```

PowerShell users run `tools/setup_dev.ps1`, `tools/play.ps1` and
`tools/run_tests.ps1`. Without an import the game still runs from source and
sets itself up like a packaged build. The
[developer setup](docs/reference/developer-setup.md) page covers macOS,
the test suites, the repository layout and packaging; the
[inspection tools](docs/reference/testing/inspection-tools.md) page covers
the sandbox and the model, map and terrain viewers.

## Documentation

| For | Start here |
|---|---|
| Players | [First-run setup](docs/reference/setup.md), [texture packs](docs/reference/assets.md#texture-packs) |
| Contributors | [Developer setup](docs/reference/developer-setup.md), [testing guide](docs/reference/testing/README.md), [architecture](docs/reference/architecture.md), [domain index](docs/reference/domain.md) |
| Agents | [AGENTS.md](AGENTS.md), then [the current checkpoint](docs/CURRENT.md) and the [roadmap](docs/PORTING.md) |
| Formats and sources | [Archive and importer](archive/README.md), [reference sources](docs/reference/sources.md) |

Documentation describes current behaviour. Git holds the history.

## Licence

The repository holds none of the original game's files: levels, models,
textures, sounds and music come from the player's own copy. A licence for the
project's own code has not been chosen yet. The test facts in
`tests/golden/pc-retail-v3.0e/`, decoded from the retail files, stay until
the owner decides on them. Third-party material keeps its own licence:
FrogLord's configuration files (MIT, `archive/third_party/froglord_cfg/LICENSE.md`)
and GUT (MIT, `addons/gut/LICENSE.md`).

## Credits

- **FrogLord** by Kneesnap and the [Highway Frogs](https://highwayfrogs.net)
  community: the file-format research this project builds on, and the
  configuration files it ships.
- The Highway Frogs community's documentation of Frogger's formats and the
  released original PlayStation source code.
- **StarmanUltra**: the traced letter outlines of the 1997 alpha's letter
  models, from which the angular lettering font and images are drawn.
- **GUT** by Butch Wesley, for testing.

Frogger is a trademark of Konami. This is an unofficial fan project, not
affiliated with or endorsed by the rights holders.
