extends GutTest
## A [code]--froglord[/code] launch over the local import plays and reloads the
## overlay its pointer names, and falls back to the base root with a warning.

const FROGLORD_FOLDER: String = "user://gameplay_screen_froglord"

var _screen: GameplayScreen

func before_each() -> void:
	FrontEndSession.cheats = CheatState.new()
	FrontEndSession.pause_cheats = PauseCheats.new()
	_screen = GameplayScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)

func _reset_front_end_session() -> void:
	FrontEndSession.active = false
	FrontEndSession.board = null
	FrontEndSession.score = 0
	FrontEndSession.level = -1
	FrontEndSession.start_page = FrontEndPage.Page.MAIN_MENU
	FrontEndSession.final_score = 0
	FrontEndSession.game_quit = false
	FrontEndSession.cheats = CheatState.new()
	FrontEndSession.pause_cheats = PauseCheats.new()

func _remove_froglord_folder(path: String = FROGLORD_FOLDER) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove_froglord_folder(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_froglord_without_a_pointer_opens_the_committed_assets_and_warns() -> void:
	_remove_froglord_folder()
	_screen.froglord_flag = true
	_screen.froglord_pointer_path = FROGLORD_FOLDER.path_join("current.cfg")
	var data: ImportedAssets = _screen.open_froglord_assets()
	assert_true(data.is_valid(), data.error)
	assert_eq(data.index_root, "res://assets")
	var warned: bool = false
	for warning: String in data.warnings:
		warned = warned or warning.begins_with("No FrogLord overlay pointer")
	assert_true(warned, "\n".join(data.warnings))
	assert_ne(_screen.reload_assets(), "")
	data.close()

func test_froglord_opens_the_pointer_overlay_and_reloads_the_level_from_a_new_catalog() -> void:
	_remove_froglord_folder()
	var overlay: String = FROGLORD_FOLDER.path_join("0123456789abcdef")
	assert_eq(DirAccess.make_dir_recursive_absolute(overlay), OK)
	assert_eq(DirAccess.copy_absolute("res://assets/catalog.tres", overlay.path_join("catalog.tres")), OK)
	var pointer := FrogLordPointer.new()
	pointer.index_root = overlay
	pointer.fingerprint = "0123456789abcdef"
	_screen.froglord_flag = true
	_screen.froglord_pointer_path = FROGLORD_FOLDER.path_join("current.cfg")
	assert_eq(pointer.write(_screen.froglord_pointer_path), OK)
	var data: ImportedAssets = _screen.open_froglord_assets()
	assert_true(data.is_valid(), data.error)
	assert_eq(data.index_root, overlay)
	assert_eq(data.warnings.size(), 0, "\n".join(data.warnings))
	assert_eq(_screen.open_data(data, "ORG1", true), "")
	_screen.watch_froglord()
	assert_not_null(_screen._reload_watcher)
	assert_eq(_screen._reload_watcher.pointer_path, _screen.froglord_pointer_path)
	assert_eq(_screen.reload_assets(), "")
	var reloaded: ImportedAssets = _screen._data as ImportedAssets
	assert_ne(reloaded, data)
	assert_eq(reloaded.index_root, overlay)
	assert_true(_screen._owns_data)
	assert_eq(_screen.level_code, "ORG1")
	assert_not_null(_screen.run)
	DirAccess.remove_absolute(_screen.froglord_pointer_path)
	assert_ne(_screen.reload_assets(), "")
	assert_eq(_screen._data, reloaded, "a failed reload keeps the current catalog")
	assert_not_null(_screen.run, "a failed reload keeps the current level")
	_screen.close_data()
	_remove_froglord_folder()

func _follow_froglord_in_setup(fallback_root: String) -> String:
	_remove_froglord_folder()
	var overlay: String = FROGLORD_FOLDER.path_join("0123456789abcdef")
	assert_eq(DirAccess.make_dir_recursive_absolute(overlay), OK)
	assert_eq(DirAccess.copy_absolute("res://assets/catalog.tres", overlay.path_join("catalog.tres")), OK)
	var settings := LauncherSettings.new()
	settings.froglord_enabled = true
	settings.froglord_dir = FROGLORD_FOLDER.path_join("save")
	_screen.launcher_path = FROGLORD_FOLDER.path_join("launcher.cfg")
	assert_eq(LauncherStore.save(settings, _screen.launcher_path), "")
	var pointer := FrogLordPointer.new()
	pointer.index_root = overlay
	pointer.fingerprint = "0123456789abcdef"
	pointer.data_dir = settings.froglord_dir
	pointer.fallback_root = fallback_root
	_screen.froglord_pointer_path = FROGLORD_FOLDER.path_join("current.cfg")
	assert_eq(pointer.write(_screen.froglord_pointer_path), OK)
	return overlay

func test_a_menu_started_level_opens_the_overlay_when_froglord_is_on_in_the_setup() -> void:
	var overlay: String = _follow_froglord_in_setup("res://assets")
	FrontEndSession.active = true
	var choice: FrogLordOverlay = _screen.froglord_overlay()
	assert_true(choice.follows)
	assert_eq(choice.index_root, overlay)
	var data: ImportedAssets = _screen.open_overlay_assets(choice)
	assert_true(data.is_valid(), data.error)
	assert_eq(data.index_root, overlay)
	assert_eq(data.root, "res://assets", "the overlay reads over the base root")
	assert_eq(_screen.open_data(data, "ORG1", true), "")
	_screen.watch_froglord()
	assert_true(_screen.follows_froglord(), "F5 and pointer changes reload in menu-started play")
	assert_eq(_screen.support_warnings(data).size(), 0, "the committed index plays every ORG1 form")
	var before: AssetCatalog = _screen._data
	_screen._on_pointer_changed()
	assert_ne(_screen._data, before, "a pointer change reopens the level from a new catalog")
	assert_eq((_screen._data as ImportedAssets).index_root, overlay)
	assert_not_null(_screen.run)
	_screen._session_finished = true
	var finished: AssetCatalog = _screen._data
	_screen._on_pointer_changed()
	assert_eq(_screen._data, finished, "a finished level waits for the next one")
	_screen._session_finished = false
	assert_false(_screen.froglord_overlay(true).follows, "attract demos keep the base root")
	_screen.close_data()
	_reset_front_end_session()
	_remove_froglord_folder()

func test_froglord_on_without_an_overlay_over_this_base_plays_the_base_root() -> void:
	_follow_froglord_in_setup("user://assets/fedcba9876543210")
	FrontEndSession.active = true
	var choice: FrogLordOverlay = _screen.froglord_overlay()
	assert_true(choice.follows, "it still reloads once the game imports one")
	assert_eq(choice.index_root, "")
	var data: ImportedAssets = _screen.open_overlay_assets(choice)
	assert_true(data.is_valid(), data.error)
	assert_eq(data.index_root, "res://assets")
	var warned: bool = false
	for warning: String in data.warnings:
		warned = warned or warning.begins_with("No FrogLord overlay of")
	assert_true(warned, "\n".join(data.warnings))
	assert_eq(_screen.open_data(data, "ORG1", true), "")
	var before: AssetCatalog = _screen._data
	_screen._on_pointer_changed()
	assert_eq(_screen._data, before, "a pointer over another base is ignored")
	assert_eq(_screen.last_error, "", "and does not stop play")
	_screen.close_data()
	_reset_front_end_session()
	_remove_froglord_folder()

func test_froglord_off_in_the_setup_plays_the_base_root_and_does_not_follow() -> void:
	_follow_froglord_in_setup("res://assets")
	assert_eq(LauncherStore.save(LauncherSettings.new(), _screen.launcher_path), "")
	var choice: FrogLordOverlay = _screen.froglord_overlay()
	assert_false(choice.follows)
	assert_eq(choice.index_root, "")
	_remove_froglord_folder()

func test_an_overlay_that_does_not_open_falls_back_to_the_base_root_with_a_warning() -> void:
	var choice := FrogLordOverlay.new()
	choice.follows = true
	choice.index_root = FROGLORD_FOLDER.path_join("absent")
	var data: ImportedAssets = _screen.open_overlay_assets(choice)
	assert_true(data.is_valid(), data.error)
	assert_eq(data.index_root, "res://assets")
	assert_string_contains("\n".join(data.warnings), "cannot be opened")
	data.close()
