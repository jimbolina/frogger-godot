extends GutTest
## SetupScreen over scratch settings files, a scratch texture packs folder, a
## fake importer and a fake import process: the skip to the front end, the
## reopen, the first run, a whole walk from the game folder to Play choosing a
## texture pack, the settings page's pack list, and a cancelled import.

const ROOT: String = "user://test_setup_screen"
const FINGERPRINT: String = "0123456789abcdef"
const PACKS: String = ROOT + "/texture_packs"


class FakeImporter:
	extends AssetImporter
	var detected := PackedStringArray()

	func detect(data_dir: String) -> AssetImporter.Detection:
		detected.append(data_dir)
		var detection := AssetImporter.Detection.new()
		detection.fingerprint = FINGERPRINT
		detection.build = AssetImporter.SUPPORTED_BUILD
		detection.summary = "PC Retail v3.0e in %s" % data_dir
		return detection


class FakeProcess:
	extends ImportProcess
	var started: ImportCommand = null
	var running: bool = false
	var cancelled: bool = false
	var report_text: String = ""

	func start(command: ImportCommand) -> bool:
		started = command
		running = true
		target_root = command.target_root
		return true

	func is_running() -> bool:
		return running

	func poll() -> ImportProgress:
		var report: ImportProgress = ImportProgress.parse(report_text)
		running = not report.finished
		return report

	func cancel() -> bool:
		cancelled = running
		running = false
		return cancelled


var _importer: FakeImporter
var _process: FakeProcess


func before_each() -> void:
	ImportProcess.remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	_importer = FakeImporter.new()
	_process = FakeProcess.new()


func after_each() -> void:
	GraphicsProfile.reset()


func after_all() -> void:
	ImportProcess.remove_tree(ROOT)


func _screen() -> SetupScreen:
	var screen := SetupScreen.new()
	screen.auto_begin = false
	screen.change_scenes = false
	screen.shift_grace = 0.0
	screen.launcher_path = ROOT.path_join("launcher.cfg")
	screen.progress_path = ROOT.path_join("progress.cfg")
	screen.graphics_path = ROOT.path_join("graphics.cfg")
	screen.legacy_settings_path = ROOT.path_join("settings.cfg")
	screen.texture_pack_folders = PackedStringArray([PACKS])
	screen.importer = _importer
	screen.import_process = _process
	add_child_autofree(screen)
	return screen


func _files_view(screen: SetupScreen) -> SetupGameFilesView:
	return screen.views[0] as SetupGameFilesView


func _import_view(screen: SetupScreen) -> SetupImportView:
	return screen.views[1] as SetupImportView


func _options_view(screen: SetupScreen) -> SetupOptionsView:
	return screen.views[2] as SetupOptionsView


func _install_pack(folder: String, title: String, author: String) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(PACKS.path_join(folder)), OK)
	var config := ConfigFile.new()
	config.set_value("pack", "name", title)
	config.set_value("pack", "author", author)
	config.set_value("pack", "base_build", "pc-retail-v3.0e")
	assert_eq(config.save(PACKS.path_join(folder).path_join("pack.cfg")), OK)


func _texture_items(screen: SetupScreen) -> PackedStringArray:
	var items := PackedStringArray()
	for child: Node in _options_view(screen).find_children("*", "OptionButton", true, false):
		var option: OptionButton = child as OptionButton
		if option.item_count > 0 and option.get_item_text(0) == SetupOptions.pack_label(null):
			for index: int in option.item_count:
				items.append(option.get_item_text(index) + (" *" if index == option.selected else ""))
	return items


func test_a_source_checkout_without_a_launcher_file_goes_straight_to_the_front_end() -> void:
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray())
	assert_eq(screen.opening, SetupFlow.Opening.SKIP)
	assert_eq(screen.left_for, FrontEndScreen.SCENE)
	assert_null(screen.flow)
	assert_eq(_importer.detected, PackedStringArray(), "a skip detects nothing")


func test_the_setup_flag_opens_the_pages_on_the_committed_assets() -> void:
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray([SetupFlow.SETUP_FLAG]))
	assert_eq(screen.opening, SetupFlow.Opening.REQUESTED)
	assert_eq(screen.left_for, "")
	assert_not_null(screen.flow)
	assert_eq(screen.flow.base_root, ImportedAssets.SHIPPABLE_ROOT)
	assert_eq(screen.views.size(), screen.flow.pages.size(), "one view per page")
	assert_true(screen.views[0].visible)
	assert_false(screen.views[1].visible)
	assert_true(screen.flow.can_continue(), "the committed assets play without an import")


func test_the_first_run_waits_for_game_files_and_offers_the_remembered_folder() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("game_data", "directory", "/Games/Remembered")
	assert_eq(legacy.save(ROOT.path_join("settings.cfg")), OK)
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray(["--assets-root=%s/missing" % ROOT]))
	assert_eq(screen.opening, SetupFlow.Opening.FIRST_RUN)
	assert_eq(screen.flow.game_files.data_dir, "/Games/Remembered")
	assert_eq(_importer.detected, PackedStringArray(["/Games/Remembered"]))
	assert_false(screen.flow.game_files.suggestion_note.is_empty())


func test_a_whole_setup_imports_saves_and_opens_the_front_end() -> void:
	_install_pack("crisp", "Crisp Frogs", "A. Artist")
	assert_eq(DirAccess.make_dir_recursive_absolute(PACKS.path_join("not_a_pack")), OK)
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray(["--assets-root=%s/missing" % ROOT]))
	assert_false(screen.flow.can_continue())
	_files_view(screen).choose_folder("/Games/Frogger")
	assert_true(screen.flow.can_continue())
	screen.next_page()
	assert_eq(screen.flow.page(), screen.flow.import_page)
	assert_eq(screen.flow.import_page.state, SetupImport.State.RUNNING, "the import starts on entry")
	assert_eq(_process.started.data_dir, "/Games/Frogger")
	assert_eq(_process.started.target_root, AssetImporter.root_for(FINGERPRINT))
	assert_false(screen.flow.can_go_back())
	_process.report_text = ImportProgress.progress_line(0.5, "Converting maps")
	_import_view(screen).poll()
	assert_almost_eq(screen.flow.import_page.fraction, 0.5, 0.0001)
	_process.report_text += ImportProgress.note_line("music: no disc image supplied") \
		+ ImportProgress.progress_line(1.0, "Done") + ImportProgress.done_line(true)
	_import_view(screen).poll()
	assert_eq(screen.flow.import_page.state, SetupImport.State.SUCCEEDED)
	var recorded: LauncherStore = LauncherStore.load_from(screen.launcher_path)
	assert_eq(recorded.settings.imported_root, AssetImporter.root_for(FINGERPRINT), "the import is recorded at once")
	assert_true(recorded.settings.show_setup_on_start, "until Play the setup opens again")
	screen.next_page()
	assert_eq(_texture_items(screen), PackedStringArray(["None (original textures) *", "Crisp Frogs, by A. Artist"]),
		"the settings page lists none and each installed pack")
	screen.flow.options.set_texture_pack("crisp")
	screen.flow.options.set_music_volume(6)
	screen.flow.options.set_language(GameLanguage.Id.FRENCH)
	screen.flow.options.set_fullscreen(true)
	screen.next_page()
	screen.next_page()
	assert_true(screen.flow.is_last())
	assert_true(screen.play(), screen.last_error)
	assert_eq(screen.left_for, FrontEndScreen.SCENE)
	var launcher: LauncherStore = LauncherStore.load_from(screen.launcher_path)
	assert_eq(launcher.error, "")
	assert_false(launcher.settings.show_setup_on_start)
	assert_eq(launcher.settings.game_data_dir, "/Games/Frogger")
	assert_eq(launcher.settings.texture_pack, "crisp")
	var progress: ProgressStore = ProgressStore.load_from(screen.progress_path)
	assert_eq(progress.music_volume, 6)
	assert_eq(progress.language, GameLanguage.Id.FRENCH)
	var graphics: GraphicsStore = GraphicsStore.load_from(screen.graphics_path)
	assert_eq(graphics.settings.window_mode, GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN)
	assert_eq(GraphicsProfile.current().window_mode, GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN,
		"the live profile follows")


func test_a_cancelled_import_stops_the_process_and_offers_a_retry() -> void:
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray(["--assets-root=%s/missing" % ROOT]))
	_files_view(screen).choose_folder("/Games/Frogger")
	screen.next_page()
	_import_view(screen).cancel_import()
	assert_true(_process.cancelled)
	assert_eq(screen.flow.import_page.state, SetupImport.State.CANCELLED)
	assert_false(screen.flow.can_continue())
	assert_true(screen.flow.can_go_back())
	assert_false(FileAccess.file_exists(screen.launcher_path), "nothing is recorded")
	_import_view(screen).start_import()
	assert_eq(screen.flow.import_page.state, SetupImport.State.RUNNING)


func test_a_process_that_ends_without_finishing_fails_the_import() -> void:
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray(["--assets-root=%s/missing" % ROOT]))
	_files_view(screen).choose_folder("/Games/Frogger")
	screen.next_page()
	_process.report_text = ImportProgress.problem_line("the import process ended without finishing") \
		+ ImportProgress.done_line(false)
	_import_view(screen).poll()
	assert_eq(screen.flow.import_page.state, SetupImport.State.FAILED)
	assert_eq(screen.flow.import_page.problems, PackedStringArray(["the import process ended without finishing"]))


func test_the_launch_draws_the_texture_pack_the_setup_chose() -> void:
	var launcher := LauncherSettings.new()
	assert_eq(ViewerArguments.texture_set_from(PackedStringArray(), launcher), "", "no pack by default")
	assert_eq(ViewerArguments.texture_set_from(PackedStringArray(), null), "")
	launcher.texture_pack = " Crisp Frogs "
	assert_eq(ViewerArguments.texture_set_from(PackedStringArray(), launcher), "Crisp Frogs")
	assert_eq(ViewerArguments.texture_set_from(PackedStringArray(["--texture-pack=other"]), launcher), "other",
		"the launch argument wins")
	assert_eq(ViewerArguments.texture_set_from(PackedStringArray(["--texture-pack="]), launcher), "",
		"an empty argument draws the original textures")


func test_the_settings_page_follows_the_installed_packs() -> void:
	var screen: SetupScreen = _screen()
	screen.begin(PackedStringArray([SetupFlow.SETUP_FLAG]))
	screen.next_page()
	screen.next_page()
	assert_eq(screen.flow.page(), screen.flow.options)
	assert_eq(_texture_items(screen), PackedStringArray(["None (original textures) *"]))
	_install_pack("b_pack", "Beta", "B. Artist")
	_install_pack("a_pack", "Alpha", "")
	screen.previous_page()
	screen.next_page()
	assert_eq(_texture_items(screen), PackedStringArray(["None (original textures) *", "Alpha", "Beta, by B. Artist"]),
		"packs are listed by folder name each time the page shows")


func test_shift_during_the_grace_wait_opens_the_setup() -> void:
	var screen: SetupScreen = _screen()
	screen.shift_grace = 1.0
	screen.begin(PackedStringArray())
	assert_eq(screen.left_for, "", "the skip waits for a held Shift first")
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	screen._input(shift)
	assert_eq(screen.opening, SetupFlow.Opening.REQUESTED)
	assert_not_null(screen.flow)
	screen._process(2.0)
	assert_eq(screen.left_for, "", "an opened setup stays")


func test_without_shift_the_grace_wait_ends_in_the_front_end() -> void:
	var screen: SetupScreen = _screen()
	screen.shift_grace = 1.0
	screen.begin(PackedStringArray())
	var motion := InputEventMouseMotion.new()
	screen._input(motion)
	screen._process(0.5)
	assert_eq(screen.left_for, "")
	screen._process(0.6)
	assert_eq(screen.left_for, FrontEndScreen.SCENE)
	assert_null(screen.flow)
