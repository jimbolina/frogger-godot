class_name SetupFlow
extends RefCounted
## The setup screen's pages in order, the page shown, and the launcher
## settings the pages fill.
##
## [method opening] decides at start whether the setup screen opens at all.
## The pages are [SetupGameFiles], [SetupImport], [SetupOptions],
## [SetupFrogLord] and [SetupPlay]; the player moves on only when the shown
## page has no [method SetupPage.blocker] and back only when it allows. The
## flow touches no files: the view reads the saved records into the pages,
## checks folders and runs the import, and saves what [method finish] returns.

## The launch flag that opens the setup screen.
const SETUP_FLAG: String = "--setup"

## Why the setup screen opens, or that it does not.
enum Opening {
	## The game plays at once: an assets root is usable and the setup is complete.
	SKIP,
	## Nothing to play from yet and no import recorded: the first run.
	FIRST_RUN,
	## Shift was held at start or [constant SETUP_FLAG] was given.
	REQUESTED,
	## The launcher settings ask for the setup screen on start, or a setup was
	## left before Play.
	ON_START,
	## An import is recorded but no assets root is usable, for example because
	## its folder was removed.
	UNUSABLE,
}

## Why the screen opened.
var opening_reason: Opening = Opening.FIRST_RUN
## The launcher settings being filled, a copy of the saved ones.
var launcher := LauncherSettings.new()
## The assets root the game could play from when the setup opened, or "".
var base_root: String = ""
## The game-files page.
var game_files := SetupGameFiles.new()
## The import page.
var import_page := SetupImport.new()
## The settings page.
var options := SetupOptions.new()
## The FrogLord page.
var froglord := SetupFrogLord.new()
## The last page.
var play := SetupPlay.new()
## The pages in the order they are shown.
var pages: Array[SetupPage] = []
## The index of the page shown in [member pages].
var index: int = 0


func _init() -> void:
	pages = [game_files, import_page, options, froglord, play]


## Whether and why the setup screen opens: [param arguments] are the launch's
## user arguments, [param shift_held] whether Shift was down at start,
## [param location_usable] whether [AssetLocation] found a usable root,
## [param store_found] whether a launcher file was read and [param saved] its
## settings.
static func opening(arguments: PackedStringArray, shift_held: bool, location_usable: bool,
		store_found: bool, saved: LauncherSettings) -> Opening:
	if shift_held or arguments.has(SETUP_FLAG):
		return Opening.REQUESTED
	if not location_usable:
		return Opening.UNUSABLE if store_found and saved.has_import() else Opening.FIRST_RUN
	if store_found and saved.show_setup_on_start:
		return Opening.ON_START
	return Opening.SKIP


## A sentence for the player about [param why].
static func opening_text(why: Opening) -> String:
	match why:
		Opening.FIRST_RUN:
			return "Welcome. Point the game at your own copy of Frogger to import it."
		Opening.UNUSABLE:
			return "The imported game files cannot be found. Import them again."
		Opening.ON_START:
			return "The setup opens on start; turn that off on the last page."
	return "Change the setup, then choose Play."


## A flow over a copy of the [param saved] launcher settings, opened for
## [param why], with [param root] the usable assets root or "".
static func create(saved: LauncherSettings, root: String, why: Opening) -> SetupFlow:
	var flow := SetupFlow.new()
	flow.launcher = saved.duplicate() as LauncherSettings
	flow.base_root = root
	flow.opening_reason = why
	flow.game_files.base_usable = not root.is_empty()
	flow.play.show_setup_on_start = saved.show_setup_on_start
	return flow


## The page shown.
func page() -> SetupPage:
	return pages[index]


## True on the last page.
func is_last() -> bool:
	return index == pages.size() - 1


## Whether the player may move on from the shown page.
func can_continue() -> bool:
	return not is_last() and page().can_continue()


## Whether the player may go back from the shown page.
func can_go_back() -> bool:
	return index > 0 and page().can_go_back()


## Shows the next page; false when the shown page does not allow it.
func next() -> bool:
	if not can_continue():
		return false
	index += 1
	return true


## Shows the previous page; false when the shown page does not allow it.
func back() -> bool:
	if not can_go_back():
		return false
	index -= 1
	return true


## The root an import of the chosen files writes, or "" when none are chosen.
func import_target() -> String:
	var key: String = game_files.fingerprint()
	return AssetImporter.root_for(key) if not key.is_empty() else ""


## Prepares the import page for the chosen files; [param target_has_index]
## says whether [method import_target] already holds an index.
func prepare_import(target_has_index: bool) -> void:
	var same_disc: bool = game_files.disc_path == launcher.disc_image_path
	import_page.prepare(game_files.fingerprint(),
		launcher.fingerprint if same_disc else "", launcher.imported_root, target_has_index)


## Records a finished import in the launcher settings: the files, the disc,
## the fingerprint and the root. Until Play, the setup screen opens on start,
## so a setup left halfway resumes. False when no import has succeeded.
func record_import() -> bool:
	if import_page.state != SetupImport.State.SUCCEEDED:
		return false
	launcher.game_data_dir = game_files.data_dir
	launcher.disc_image_path = game_files.disc_path
	launcher.fingerprint = import_page.fingerprint
	launcher.imported_root = import_page.target_root
	launcher.show_setup_on_start = true
	return true


## The assets root the game will play from: the import's when it has one,
## otherwise the root usable at the start, or "".
func play_root() -> String:
	return import_page.target_root if import_page.has_root() else base_root


## Whether the game has something to play from.
func can_play() -> bool:
	return is_last() and not play_root().is_empty()


## The launcher settings with every page's choices, to be saved on Play.
func finish() -> LauncherSettings:
	if import_page.has_root():
		launcher.game_data_dir = game_files.data_dir
		launcher.disc_image_path = game_files.disc_path
		launcher.fingerprint = import_page.fingerprint
		launcher.imported_root = import_page.target_root
	options.write_launcher(launcher)
	froglord.write_launcher(launcher)
	play.write_launcher(launcher)
	return launcher
