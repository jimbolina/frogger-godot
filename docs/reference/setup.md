# First-run setup

`scenes/setup.tscn` is the main scene. It either goes straight to the front
end or shows the setup pages, where the player points the game at their own
copy of `pc-retail-v3.0e`, imports it, chooses settings and plays.

## Opening

`SetupFlow.opening` decides at start from the launch arguments, a held Shift,
whether `AssetLocation` found a usable root ([asset location](assets.md#asset-location))
and the launcher settings:

| Condition, first match | Result |
|---|---|
| Shift held, or `--setup` after `--` | the pages open |
| No usable root, and an import is recorded | the pages open: the import is gone |
| No usable root otherwise | the pages open: the first run |
| `show_setup_on_start` is true | the pages open |
| Otherwise | the front end opens |

A source checkout with the committed `assets/` and no launcher file therefore
goes straight to the front end, as before. When the screen would skip, it
first waits 0.3 s for Shift: a held key is seen through `Input.is_key_pressed`
or through any key or mouse event that carries the Shift modifier. On macOS a
key held before launch may reach the game only once the mouse moves over the
window; `--setup` always works.

## Pages

Each concern is one page model under `src/application/setup/` (a `SetupPage`:
title, blocker, may go back) and one view under `src/presentation/setup/` (a
`SetupPageView`). `SetupFlow` holds them in order; Next is enabled when the
shown page has no blocker, Back when it allows. A new concern adds a model, a
view and an entry in both orders.

1. **Game files** (`SetupGameFiles`). A folder field with Browse, which opens
   `DisplayServer.file_dialog_show` where the display server has native
   dialogs and otherwise a `FileDialog` asking for the native one. The folder
   goes through `AssetImporter.detect`; a missing folder, unknown build or
   other build is shown as the blocker. An optional `.mds` disc image (with its
   `.mdf` beside it) brings the music. When the launcher records no folder,
   the archive locator's remembered one (`user://settings.cfg`,
   `[game_data] directory`) is read as a plain `ConfigFile` and suggested. The
   page may be left without files only when a root is already usable.
2. **Import** (`SetupImport`). Files with the fingerprint, disc image and root
   the launcher recorded, whose root still holds `catalog.tres`, are kept and
   may be imported again; other files start importing when the page appears.
   The page shows progress, Cancel, Retry and the child's log path. A finished
   import is saved to the launcher settings at once, with
   `show_setup_on_start` true until Play, so a setup left halfway opens again.
3. **Settings** (`SetupOptions`). Language (automatic or one of the five) and
   the music and effects volumes (0 to 8) go to `progress.cfg` through
   `ProgressStore`; windowed or fullscreen, the windowed size and vsync go to
   `graphics.cfg` through `GraphicsStore`, keeping every other field; the
   [texture pack](assets.md#texture-packs) goes to the launcher settings. The
   list offers "None (original textures)" and each pack
   `TexturePackReader.list` finds in `SetupScreen.texture_pack_folders`
   (`user://texture_packs/`, and beside an exported executable), by name with
   its author, read again each time the page shows; a saved pack that is no
   longer installed is shown as none.
4. **FrogLord** (`SetupFrogLord`). An on/off switch and an existing save
   folder, stored in the launcher settings. The folder goes through
   `AssetImporter.detect_froglord`, and the page says what it holds: a
   FrogLord save (`modded_FROGGER.EXE` and `modded_FROGPSX.MWD`) of
   `pc-retail-v3.0e` with its FrogLord version, the retail pair (followed
   until FrogLord saves), or nothing yet. Only a pair of another or an unknown
   build blocks Next. The page also states what happens
   [while playing](#froglord-while-playing).
5. **Play** (`SetupPlay`). A summary, the "show this setup every time"
   choice, the desktop shortcut, how to reopen the setup and a **Credits and
   licences** window ([packaging](#packaging)). Play saves the
   three files, replaces the live `GraphicsProfile`, applies the window
   through `GraphicsApplier.apply_window` and opens the front end.

`ViewerArguments.texture_set` names the pack from `--texture-pack=` after
`--` (an empty value draws none), else the launcher's `texture_pack`, so every
scene draws the chosen pack.

## Import process

The importer stalls on a worker thread while saving model meshes
([archive](../../archive/README.md#runtime-import)), so the setup screen runs
it in a child process of the same executable, headless, where it runs on the
main thread. `ImportProcess` starts

```text
<executable> --headless [--path <project>] --log-file <user>/logs/setup_import.log
  res://scenes/setup.tscn -- --setup-import --data-dir=<folder> [--disc=<image>]
  --target=user://assets/<fingerprint> --progress=<user>/setup/import_progress.txt
  --user-dir=<user>
```

`--path` is passed when the engine is not an export template, so a run from
source shares the project's settings, `override.cfg` included, and therefore
its `user://`. `ImportCommand` builds and reads this line. In import mode the
setup scene calls `ImportChild.run`, which refuses to run when its own
`user://` is not `--user-dir`, runs `AssetImporter.run` and quits with 0, 1
(failed) or 2 (no progress file).

The progress file is text, one tab-separated record per line
(`ImportProgress`): `progress <fraction> <label>`, `note <text>`,
`problem <text>`, and last `done ok` or `done failed`. The child truncates it,
then appends each line with the file opened and closed around it; progress
lines are written when the label changes, the fraction moves by 0.005 or
0.25 s has passed. The parent reads it ten times a second and parses complete
lines only. A child that ends without the `done` record fails the import with
its exit code and log path. Cancel kills the child with `OS.kill`; before each
start and after a cancel, `ImportProcess.clean_up` removes `<root>.partial` and
restores a `<root>.old` that was moved aside but not replaced. Closing the
screen during an import cancels it.

## FrogLord while playing

With FrogLord on, the front end and the game scene start the process's one
`FrogLordWatcher` over the base root `AssetLocation` chose; it lives under the
tree's root for the session and runs in no other scene. Once a second it
reads the save folder's source state (each file's name, modification time
and size). A state that differs from the one the current overlay was
imported from and stays the same for one more second starts an overlay
import of the save's name lists, tables, demos and maps into
`user://froglord/` (overlays over the committed assets) or
`user://froglord/over-<key>/` (over any other base root, keyed by its path),
each save in a folder named by its fingerprint, with an index that names the
base root for everything else. The import runs on a worker thread, so the
menu and the level keep running. A clean import rewrites
`user://froglord/current.cfg`; a level that follows FrogLord reopens from its
start when it changes, F5 reopens it by hand, and a level-complete page
waits for the next level. At start, a pointer of the same files over the same
base counts as imported, so nothing is imported again.

Levels started from the menu, and direct launches, open the overlay when the
pointer names one of the chosen folder over this base root; otherwise they
play the base root until the first import. The menus and the attract demos
always draw from the base root: the demos are recordings of the retail
levels. A save the import is not ready for (an unfinished write, another
build) is tried again when its files change or after five seconds; a failed
import is not repeated until they change. A missing folder, a folder without
a save, each import, the save's unmapped support-report rows and any problem
show as a line at the bottom of the window for eight seconds and are printed;
none stops play. When a level opens from an overlay, the rows of its own
`LevelSupportReport` the port cannot play show the same way.

`--froglord` and `archive/import/froglord_watch.sh` stay the developer path:
the external watch imports over the committed assets and a `--froglord`
launch follows whatever overlay the pointer names.

## Desktop shortcut

`DesktopShortcut` builds the content and commands as pure functions and
writes for the running platform. From source the shortcut starts the engine
with `--path <project>`; an exported game starts its own executable.

- **Windows:** a PowerShell script creates `Frogger.lnk` on the desktop
  through `WScript.Shell` (target, arguments quoted for `CommandLineToArgvW`,
  working folder, the program's icon). It travels as `-EncodedCommand`
  (base64 UTF-16LE), so no quoting of the script itself is involved.
- **Linux:** `frogger.desktop` in `$XDG_DATA_HOME/applications` (or
  `~/.local/share/applications`) and on the desktop, with `Exec` quoted per
  the desktop entry specification, marked executable, with the icon
  `DesktopShortcut.linux_icon` names (`frogger.png` beside an exported
  executable, `icon/frogger_icon.png` from source) when it exists; some
  desktops ask the player to trust the file.
- **macOS:** no button; the page says to drag the app to Applications or the
  Dock, or to use `tools/launch_macos.command` from source.

Only the macOS path has been run; the Windows and Linux content is checked by
the game suite's builder tests.

## Packaging

`export_presets.cfg` holds three release presets that export everything in
the project except their exclude filters, into `build/` (git-ignored):

| Preset | Output | Notes |
|---|---|---|
| macOS | `build/macos/Frogger.app` | Universal (x86_64 and arm64), ad-hoc signed by Godot's built-in signer with the hardened runtime, not notarised; `icon/frogger.icns`. Universal export needs `rendering/textures/vram_compression/import_etc2_astc`. |
| Windows | `build/windows/Frogger.exe` and `Frogger.pck` | x86_64; `application/modify_resources` writes `icon/frogger.ico`, the version and the names into the executable with Godot's own resource editor, so no rcedit or Wine is needed, on a macOS host too. Not code-signed. |
| Linux | `build/linux/Frogger.x86_64` and `Frogger.pck` | x86_64; `tools/export.sh` adds `frogger.png` and a `frogger.desktop` that starts the game from its own folder. |

`tools/export.sh [preset ...]` (`tools/export.ps1` on Windows, which exports
macOS as a `.zip`) imports the project, exports each preset, fails when the
export log stores any file under `assets/` or `.godot/imported/` other than
the shippable ones below, and zips each build as
`build/Frogger-<version>-<platform>.zip`; logs go to `build/logs/`.
The version is `config/version` in `project.godot`; the release pull request
writes it, never a hand edit.

Releases come from `.github/workflows/release.yml` and release-please
(`release-please-config.json`, `.release-please-manifest.json`, release type
`simple`). On every push to `main`, release-please reads the Conventional
Commits since its bootstrap commit and keeps one release pull request open,
titled `chore(main): release X.Y.Z`, which updates `CHANGELOG.md` and the
manifest. A second job writes the same version into `config/version` on that
pull request's branch, because Godot strips comments from `project.godot` and
release-please cannot annotate it. `feat:` raises the minor version and `fix:`
the patch; below 1.0 a breaking change (`!` or `BREAKING CHANGE`) also raises
only the minor. Other types (`docs:`, `chore:`, `ci:`, `refactor:`, `test:`)
and untyped summaries neither bump the version nor appear in the changelog.

A release happens only when the owner merges that pull request. release-please
then tags `vX.Y.Z` and creates a draft GitHub Release, and the same workflow
builds it: an Ubuntu runner runs `tools/export.sh Windows Linux` and a
`macos-latest` runner runs `tools/export.sh macOS` natively, signed ad hoc by
Godot's built-in signer. Both use the pinned Godot of
[hosted CI](testing/README.md#hosted-ci) with export templates extracted from
the official `.tpz`, checksummed and cached. A build fails when
`config/version` differs from the release version; otherwise it attaches its
`Frogger-<version>-windows-x86_64.zip`, `-linux-x86_64.zip` or `-macos.zip`
with `gh release upload`, and a last job publishes the draft. Dispatching the
workflow by hand is a dry run: it builds the same zips as workflow artifacts
(`packages-<runner os>`, kept 30 days) and makes no release. Export logs are
kept as `export-logs-<runner os>` for 14 days.

A packaged build carries no retail-derived file. It ships `src/` (shaders
included), `scenes/`, `archive/import/` with `disc_tracks.tsv`,
`archive/source/`, FrogLord's configuration files with their `LICENSE.md`,
the icon, and from `assets/` only `fonts/angular/frogger_angular.ttf` and
`rendering/emissive_images.tres`. It excludes `tests/`, `tools/`, `addons/`
(GUT), `docs/`, `archive/tests/`, `archive/docs/` and every retail-derived
asset: the index, tables, textures (with the lettering images, which trace
the alpha's letter models over retail ink boxes), models, materials, maps,
audio, demos, the `newfont` page and its `.fnt`, and the angular font's
sources. The game suite's `test_export_presets` checks every committed
asset against the filters of every preset.

The catalog serves such a build without the missing shippable files
([ImportedAssets](../../src/application/loaders/imported_assets.gd)):
`newfont` is built at runtime by `NewfontFont` around a `NewfontPage` page
from the player's imported texture 310 (a texture pack's, when it redraws
it), with the glyph layout of the committed `.fnt`; the `.fnt` is not
shipped because Godot's imported font embeds the page's retail pixels, and
its layout follows from the page geometry alone.
`test_asset_newfont_runtime` checks that the built font stores every property
the imported one does and the same page. Without lettering images every
texture draws its retail image, silently.

The app icon is a placeholder: `icon/frogger_icon.svg`, an original frog on
a lily pad, until an artist replaces it. `godot --headless --path . -s
res://tools/make_icons.gd` renders it into `icon/frogger_icon.png` (256 px:
`config/icon`, the window icon and the Linux icon), `icon/frogger.ico` (16
to 256 px) and `icon/frogger.icns` (16 to 1024 px), PNG images in both;
`-- --check` compares instead, and `test_app_icons` checks the files against
the source.

The setup's last page opens **Credits and licences**: `ThirdPartyNotices`
joins the game's line, the importer's notice
(`AssetImporter.third_party_notice`: FrogLord's credit and MIT licence, read
from the shipped `LICENSE.md`), Godot's licence (`Engine.get_license_text`)
and the engine's components and their licences.

The exported macOS app was checked with an isolated user folder: an
`override.cfg` beside the executable in `Contents/MacOS/` (where Godot reads
it; it breaks the bundle's seal, so only on a copy) naming a custom user
folder. The setup screen opened, detected the game folder, ran the child
import from inside the app as an export template without `--path`, opened
the front end on Play and played ORG1 with `newfont` text and the retail
lettering; the next launch went to the menu. The Windows and Linux builds
were exported but not run.

## Verification

The game suite checks the opening rules, page transitions, import outcomes,
the progress protocol, the command line, the child entry function with a
fake importer, the shortcut builders, the launcher migration and the screen
with a fake importer and process, and for FrogLord the page's detection
text, the watch's state machine, the watcher with a fake importer inline and
on a thread, the overlay a level chooses and a pointer change in menu-started
play. The archive suite's `test_retail_setup_import` starts a real child on
`FROGGER_DATA_DIR`, follows it to a complete root under
`user://setup_child_import/` and cancels a second one part way;
`test_retail_froglord_overlay_import` imports the synthetic FrogLord save
through the seam over a runtime-imported `user://` root and plays ORG1 from
it.
