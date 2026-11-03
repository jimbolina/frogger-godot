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
   texture set goes to the launcher settings. Only sets whose images exist
   under the root the game will play from are offered
   (`ImportedAssets.installed_texture_sets`): retail always, `x4` only over the
   committed assets.
4. **FrogLord** (`SetupFrogLord`). An on/off switch and an existing save
   folder, stored in the launcher settings. The in-game watch is phase L4;
   until then only `--froglord` launches follow a save.
5. **Play** (`SetupPlay`). A summary, the "show this setup every time"
   choice, the desktop shortcut and how to reopen the setup. Play saves the
   three files, replaces the live `GraphicsProfile`, applies the window
   through `GraphicsApplier.apply_window` and opens the front end.

`ViewerArguments.texture_set` reads the launcher's texture set after
`--texture-set=` and before the `frogger/textures/default_set` project
setting, so every scene draws the chosen set.

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
  the desktop entry specification, marked executable. It has no icon until the
  game has one (L5); some desktops ask the player to trust the file.
- **macOS:** no button; the page says to drag the app to Applications or the
  Dock, or to use `tools/launch_macos.command` from source.

Only the macOS path has been run; the Windows and Linux content is checked by
the game suite's builder tests.

## Verification

The game suite checks the opening rules, page transitions, import outcomes,
the progress protocol, the command line, the child entry function with a
fake importer, the shortcut builders, the launcher migration and the screen
with a fake importer and process. The archive suite's
`test_retail_setup_import` starts a real child on `FROGGER_DATA_DIR`, follows
it to a complete root under `user://setup_child_import/` and cancels a second
one part way.
