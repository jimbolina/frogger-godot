extends GutTest
## SetupFlow decides whether the setup screen opens and walks its pages: the
## skip for a complete setup, the first run, the Shift or --setup reopen and a
## setup left before Play; the game-files, import, settings and FrogLord rules;
## and the launcher settings recorded on import and on Play.

const FINGERPRINT: String = "0123456789abcdef"
const OTHER_FINGERPRINT: String = "fedcba9876543210"
const COMMITTED: String = "res://assets"


func _detection(error: String = "", fingerprint: String = FINGERPRINT) -> AssetImporter.Detection:
	var detection := AssetImporter.Detection.new()
	detection.error = error
	detection.fingerprint = fingerprint
	detection.build = AssetImporter.SUPPORTED_BUILD
	detection.summary = "PC Retail v3.0e"
	return detection


func _saved(show_on_start: bool = false, imported: bool = false) -> LauncherSettings:
	var saved := LauncherSettings.new()
	saved.show_setup_on_start = show_on_start
	if imported:
		saved.fingerprint = FINGERPRINT
		saved.imported_root = AssetImporter.root_for(FINGERPRINT)
	return saved


func _flow_with_files(root: String = "") -> SetupFlow:
	var flow: SetupFlow = SetupFlow.create(_saved(), root, SetupFlow.Opening.FIRST_RUN)
	flow.game_files.choose_folder("/Games/Frogger", _detection())
	return flow


func test_a_source_checkout_without_a_launcher_file_skips() -> void:
	var opening: SetupFlow.Opening = SetupFlow.opening(PackedStringArray(), false, true, false, LauncherSettings.new())
	assert_eq(opening, SetupFlow.Opening.SKIP)


func test_a_complete_setup_skips() -> void:
	assert_eq(SetupFlow.opening(PackedStringArray(["--level=ORG1"]), false, true, true, _saved(false, true)),
		SetupFlow.Opening.SKIP)


func test_the_first_run_opens_the_setup() -> void:
	assert_eq(SetupFlow.opening(PackedStringArray(), false, false, false, LauncherSettings.new()),
		SetupFlow.Opening.FIRST_RUN)
	var halfway: LauncherSettings = _saved()
	halfway.game_data_dir = "/Games/Frogger"
	assert_eq(SetupFlow.opening(PackedStringArray(), false, false, true, halfway), SetupFlow.Opening.FIRST_RUN,
		"a game folder without an import is still a first run")


func test_shift_or_the_setup_flag_reopens_the_setup() -> void:
	assert_eq(SetupFlow.opening(PackedStringArray(), true, true, true, _saved(false, true)),
		SetupFlow.Opening.REQUESTED)
	assert_eq(SetupFlow.opening(PackedStringArray([SetupFlow.SETUP_FLAG]), false, true, true, _saved(false, true)),
		SetupFlow.Opening.REQUESTED)
	assert_eq(SetupFlow.opening(PackedStringArray(["--setup-import"]), false, true, true, _saved(false, true)),
		SetupFlow.Opening.SKIP, "only the exact flag reopens")


func test_an_incomplete_config_opens_the_setup() -> void:
	assert_eq(SetupFlow.opening(PackedStringArray(), false, true, true, _saved(true, true)),
		SetupFlow.Opening.ON_START, "a setup left before Play, or one asked for on every start")
	assert_eq(SetupFlow.opening(PackedStringArray(), false, false, true, _saved(false, true)),
		SetupFlow.Opening.UNUSABLE, "a recorded import that can no longer be opened")


func test_each_opening_has_a_sentence() -> void:
	for opening: SetupFlow.Opening in [SetupFlow.Opening.FIRST_RUN, SetupFlow.Opening.REQUESTED,
			SetupFlow.Opening.ON_START, SetupFlow.Opening.UNUSABLE]:
		assert_false(SetupFlow.opening_text(opening).is_empty())


func test_the_pages_come_in_order() -> void:
	var flow: SetupFlow = SetupFlow.create(_saved(), "", SetupFlow.Opening.FIRST_RUN)
	var titles := PackedStringArray()
	for page: SetupPage in flow.pages:
		titles.append(page.title())
	assert_eq(titles, PackedStringArray(["Game files", "Import", "Settings", "FrogLord", "Play"]))
	assert_eq(flow.page(), flow.game_files)
	assert_false(flow.can_go_back(), "the first page has nothing before it")
	assert_false(flow.back())


func test_the_first_run_needs_game_files() -> void:
	var flow: SetupFlow = SetupFlow.create(_saved(), "", SetupFlow.Opening.FIRST_RUN)
	assert_string_contains(flow.game_files.blocker(), "Choose the folder")
	assert_false(flow.next())
	assert_eq(flow.index, 0)


func test_a_detection_error_blocks_the_game_files_page() -> void:
	var flow: SetupFlow = SetupFlow.create(_saved(), COMMITTED, SetupFlow.Opening.REQUESTED)
	flow.game_files.choose_folder("/Games/Other", _detection("/Games/Other is pc-retail-v3.0a; only pc-retail-v3.0e can be imported"))
	assert_false(flow.game_files.has_game_files())
	assert_string_contains(flow.game_files.blocker(), "only pc-retail-v3.0e")
	assert_false(flow.next(), "a wrong build blocks even when another root is usable")
	flow.game_files.clear_folder()
	assert_eq(flow.game_files.blocker(), "", "without a folder the usable root is kept")
	assert_true(flow.next())


func test_the_disc_image_is_optional_but_must_be_complete() -> void:
	var page := SetupGameFiles.new()
	page.choose_disc("", false, false)
	assert_eq(page.disc_problem, "")
	page.choose_disc("/Discs/FROGGER.cue", true, true)
	assert_string_contains(page.disc_problem, ".mds")
	page.choose_disc("/Discs/FROGGER.mds", false, false)
	assert_string_contains(page.disc_problem, "There is no disc image")
	page.choose_disc("/Discs/FROGGER.mds", true, false)
	assert_string_contains(page.disc_problem, "FROGGER.mdf")
	page.choose_disc("/Discs/FROGGER.MDS", true, true)
	assert_eq(page.disc_problem, "")
	assert_eq(SetupGameFiles.mdf_path("/Discs/FROGGER.mds"), "/Discs/FROGGER.mdf")


func test_new_files_need_an_import_that_starts_on_entry() -> void:
	var flow: SetupFlow = _flow_with_files()
	assert_true(flow.next())
	assert_eq(flow.import_target(), "user://assets/" + FINGERPRINT)
	flow.prepare_import(false)
	assert_eq(flow.import_page.state, SetupImport.State.READY)
	assert_true(flow.import_page.starts_on_entry())
	assert_false(flow.next(), "the import must run first")
	assert_string_contains(flow.import_page.blocker(), "Import")


func test_an_import_succeeds_and_is_recorded() -> void:
	var flow: SetupFlow = _flow_with_files()
	flow.game_files.choose_disc("/Discs/FROGGER.mds", true, true)
	flow.next()
	flow.prepare_import(false)
	assert_true(flow.import_page.start())
	assert_false(flow.can_go_back(), "no going back while the import runs")
	assert_false(flow.import_page.start(), "one import at a time")
	flow.import_page.advance(0.4, "Converting maps")
	flow.import_page.advance(0.2, "Converting maps")
	assert_almost_eq(flow.import_page.fraction, 0.4, 0.0001, "progress never goes back")
	assert_eq(flow.import_page.label, "Converting maps")
	flow.import_page.finish(PackedStringArray(), PackedStringArray(["a note"]))
	assert_eq(flow.import_page.state, SetupImport.State.SUCCEEDED)
	assert_eq(flow.import_page.notes, PackedStringArray(["a note"]))
	assert_true(flow.record_import())
	assert_eq(flow.launcher.fingerprint, FINGERPRINT)
	assert_eq(flow.launcher.imported_root, "user://assets/" + FINGERPRINT)
	assert_eq(flow.launcher.game_data_dir, "/Games/Frogger")
	assert_eq(flow.launcher.disc_image_path, "/Discs/FROGGER.mds")
	assert_true(flow.launcher.show_setup_on_start, "a setup left before Play opens again")
	assert_eq(flow.play_root(), "user://assets/" + FINGERPRINT)
	assert_true(flow.next())
	assert_true(flow.can_go_back())


func test_a_failed_import_blocks_and_can_be_retried() -> void:
	var flow: SetupFlow = _flow_with_files()
	flow.next()
	flow.prepare_import(false)
	flow.import_page.start()
	flow.import_page.finish(PackedStringArray(["cannot read FROGPSX.MWD"]), PackedStringArray())
	assert_eq(flow.import_page.state, SetupImport.State.FAILED)
	assert_eq(flow.import_page.problems, PackedStringArray(["cannot read FROGPSX.MWD"]))
	assert_false(flow.record_import())
	assert_false(flow.next())
	assert_true(flow.can_go_back())
	assert_true(flow.import_page.can_start())
	assert_true(flow.import_page.start())
	assert_eq(flow.import_page.problems, PackedStringArray(), "a retry starts clean")


func test_a_cancelled_import_blocks_and_can_be_retried() -> void:
	var flow: SetupFlow = _flow_with_files()
	flow.next()
	flow.prepare_import(false)
	assert_false(flow.import_page.cancel(), "nothing runs yet")
	flow.import_page.start()
	assert_true(flow.import_page.cancel())
	assert_eq(flow.import_page.state, SetupImport.State.CANCELLED)
	assert_false(flow.next())
	assert_true(flow.import_page.start())


func test_an_existing_root_for_the_same_files_is_kept() -> void:
	var saved: LauncherSettings = _saved(false, true)
	var flow: SetupFlow = SetupFlow.create(saved, saved.imported_root, SetupFlow.Opening.REQUESTED)
	flow.game_files.choose_folder("/Games/Frogger", _detection())
	flow.next()
	flow.prepare_import(true)
	assert_eq(flow.import_page.state, SetupImport.State.EXISTING)
	assert_false(flow.import_page.starts_on_entry())
	assert_true(flow.import_page.can_start(), "it may be imported again")
	assert_true(flow.next())
	flow.prepare_import(false)
	assert_eq(flow.import_page.state, SetupImport.State.READY, "a recorded root without an index is imported again")
	flow.game_files.choose_disc("/Discs/FROGGER.mds", true, true)
	flow.prepare_import(true)
	assert_eq(flow.import_page.state, SetupImport.State.READY, "another disc image needs an import with music")
	flow.game_files.choose_disc("", false, false)
	flow.game_files.choose_folder("/Games/Patched", _detection("", OTHER_FINGERPRINT))
	flow.prepare_import(true)
	assert_eq(flow.import_page.state, SetupImport.State.READY, "other files need their own import")
	assert_eq(flow.import_page.target_root, "user://assets/" + OTHER_FINGERPRINT)


func test_no_files_need_no_import_when_a_root_is_usable() -> void:
	var flow: SetupFlow = SetupFlow.create(_saved(), COMMITTED, SetupFlow.Opening.REQUESTED)
	assert_true(flow.next())
	flow.prepare_import(false)
	assert_eq(flow.import_page.state, SetupImport.State.NOT_NEEDED)
	assert_false(flow.import_page.can_start())
	assert_eq(flow.play_root(), COMMITTED)
	assert_true(flow.next())


func test_the_settings_stay_valid() -> void:
	var options := SetupOptions.new()
	var progress := ProgressStore.new()
	progress.language = GameLanguage.Id.GERMAN
	progress.music_volume = 7
	progress.sound_volume = 2
	var graphics := GraphicsSettings.new()
	graphics.window_mode = GraphicsSettings.WindowMode.EXCLUSIVE_FULLSCREEN
	graphics.window_size = Vector2i(1000, 700)
	graphics.vsync = GraphicsSettings.Vsync.MAILBOX
	var launcher := LauncherSettings.new()
	launcher.texture_pack = "gone"
	options.read(progress, graphics, launcher, [_pack("crisp", "Crisp Frogs", "")])
	assert_eq(options.language, GameLanguage.Id.GERMAN)
	assert_eq(options.texture_pack, "", "a pack that is not installed falls back to none")
	assert_eq(options.texture_packs.size(), 1)
	assert_true(options.window_sizes().has(Vector2i(1000, 700)), "the saved size stays on offer")
	options.set_fullscreen(true)
	assert_eq(options.window_mode, GraphicsSettings.WindowMode.EXCLUSIVE_FULLSCREEN, "a chosen fullscreen mode is kept")
	options.set_vsync(true)
	assert_eq(options.vsync, GraphicsSettings.Vsync.MAILBOX)
	options.set_language(9)
	assert_eq(options.language, GameLanguage.AUTO)
	options.set_music_volume(12)
	options.set_sound_volume(-3)
	assert_eq(options.music_volume, ProgressStore.MAX_VOLUME)
	assert_eq(options.sound_volume, 0)
	options.set_window_size(Vector2i(-1, 5))
	assert_eq(options.window_size, Vector2i.ZERO)
	options.set_fullscreen(false)
	options.set_vsync(false)
	options.write_progress(progress)
	options.write_graphics(graphics)
	assert_eq(progress.language, GameLanguage.AUTO)
	assert_eq(progress.music_volume, ProgressStore.MAX_VOLUME)
	assert_eq(progress.sound_volume, 0)
	assert_eq(graphics.window_mode, GraphicsSettings.WindowMode.WINDOWED)
	assert_eq(graphics.vsync, GraphicsSettings.Vsync.DISABLED)
	assert_eq(graphics.window_size, Vector2i.ZERO)


func _pack(name: String, title: String, author: String) -> TexturePack:
	var pack := TexturePack.new()
	pack.pack_name = name
	pack.title = title
	pack.author = author
	return pack


func test_only_installed_texture_packs_are_offered() -> void:
	var options := SetupOptions.new()
	assert_eq(options.texture_pack, "", "no pack until one is chosen")
	options.offer_texture_packs([_pack("crisp", "Crisp Frogs", "A. Artist"), _pack("plain", "", "")])
	assert_eq(options.texture_packs.size(), 2)
	options.set_texture_pack("CRISP")
	assert_eq(options.texture_pack, "crisp", "a pack is matched ignoring case")
	options.set_texture_pack("x4")
	assert_eq(options.texture_pack, "", "a pack that is not offered chooses none")
	options.set_texture_pack("plain")
	options.offer_texture_packs([_pack("crisp", "Crisp Frogs", "A. Artist")])
	assert_eq(options.texture_pack, "", "a pack that is no longer installed falls back to none")
	options.set_texture_pack("crisp")
	var launcher := LauncherSettings.new()
	options.write_launcher(launcher)
	assert_eq(launcher.texture_pack, "crisp")


func test_packs_are_listed_by_name_and_author() -> void:
	assert_eq(SetupOptions.pack_label(null), "None (original textures)")
	assert_eq(SetupOptions.pack_label(_pack("crisp", "Crisp Frogs", "A. Artist")), "Crisp Frogs, by A. Artist")
	assert_eq(SetupOptions.pack_label(_pack("plain", "", "")), "plain", "a pack without a name shows its folder")


func test_froglord_needs_an_existing_folder_when_on() -> void:
	var page := SetupFrogLord.new()
	assert_eq(page.blocker(), "")
	page.enabled = true
	assert_string_contains(page.blocker(), "Choose FrogLord's save folder")
	page.choose_folder("/FrogLord/save", false)
	assert_string_contains(page.blocker(), "no folder /FrogLord/save")
	page.choose_folder("/FrogLord/save", true)
	assert_eq(page.blocker(), "")


func test_play_saves_every_page_into_the_launcher_settings() -> void:
	var flow: SetupFlow = _flow_with_files()
	flow.next()
	flow.prepare_import(false)
	flow.import_page.start()
	flow.import_page.finish(PackedStringArray(), PackedStringArray())
	flow.record_import()
	flow.next()
	flow.options.offer_texture_packs([_pack("crisp", "Crisp Frogs", "")])
	flow.options.set_texture_pack("crisp")
	flow.next()
	flow.froglord.enabled = true
	assert_false(flow.next(), "FrogLord on without a folder blocks")
	flow.froglord.choose_folder("/FrogLord/save", true)
	assert_true(flow.next())
	assert_true(flow.is_last())
	assert_false(flow.can_continue(), "Play is the last page")
	assert_true(flow.can_play())
	flow.play.show_setup_on_start = false
	var saved: LauncherSettings = flow.finish()
	assert_eq(saved.texture_pack, "crisp")
	assert_true(saved.froglord_enabled)
	assert_eq(saved.froglord_dir, "/FrogLord/save")
	assert_false(saved.show_setup_on_start, "Play completes the setup")
	assert_eq(saved.imported_root, "user://assets/" + FINGERPRINT)


func test_play_needs_something_to_play_from() -> void:
	var flow: SetupFlow = SetupFlow.create(_saved(), COMMITTED, SetupFlow.Opening.REQUESTED)
	flow.index = flow.pages.size() - 1
	assert_true(flow.can_play())
	flow.base_root = ""
	assert_false(flow.can_play())


func test_the_flow_works_on_a_copy_of_the_saved_settings() -> void:
	var saved: LauncherSettings = _saved(true, true)
	var flow: SetupFlow = SetupFlow.create(saved, "", SetupFlow.Opening.ON_START)
	flow.play.show_setup_on_start = false
	flow.finish()
	assert_true(saved.show_setup_on_start)
	assert_true(SetupFlow.create(saved, "", SetupFlow.Opening.ON_START).play.show_setup_on_start)
