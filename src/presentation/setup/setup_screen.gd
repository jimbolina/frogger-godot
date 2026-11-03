class_name SetupScreen
extends Control
## The first-run setup screen and the game's main scene.
##
## On start it decides through [method SetupFlow.opening]: when the game has a
## usable assets root and the setup is complete it goes straight to the front
## end, after a short wait for a held Shift; otherwise, or with Shift held or
## [constant SetupFlow.SETUP_FLAG], it shows the pages one at a time with Back
## and Next, and Play saves every choice and opens the front end. Each page has
## a [SetupPage] model and a [SetupPageView].
##
## Started with [constant ImportCommand.IMPORT_FLAG] (headless, by
## [ImportProcess]), the scene shows nothing: it runs the import on the main
## thread through [ImportChild] and quits with its exit code.

## The scene of this screen.
const SCENE: String = "res://scenes/setup.tscn"
## Seconds the screen waits for a held Shift before it skips to the front end.
const SHIFT_GRACE: float = 0.3
## The space around the screen's content.
const MARGIN: int = 14
## The text size of the pages, in 640 by 480 canvas pixels.
const FONT_SIZE: int = 13

## The launcher settings file.
var launcher_path: String = LauncherStore.DEFAULT_PATH
## The progress and options file the language and volumes are saved to.
var progress_path: String = FrontEndSession.store_path
## The graphics settings file the window choices are saved to.
var graphics_path: String = GraphicsStore.DEFAULT_PATH
## The archive's settings file, whose remembered game folder is suggested once.
var legacy_settings_path: String = LauncherStore.LEGACY_SETTINGS_PATH
## The folders the settings page lists texture packs from.
var texture_pack_folders: PackedStringArray = TexturePackReader.search_folders()
## Whether [method _ready] starts the screen from the launch's own arguments;
## tests call [method begin] themselves.
var auto_begin: bool = true
## Whether leaving changes the scene; tests read [member left_for] instead.
var change_scenes: bool = true
## Seconds to wait for a held Shift before skipping.
var shift_grace: float = SHIFT_GRACE
## The scene the screen left for, or "".
var left_for: String = ""
## The flow shown, or null when the screen skipped or is importing.
var flow: SetupFlow = null
## Why the screen opened, or [constant SetupFlow.Opening.SKIP].
var opening: SetupFlow.Opening = SetupFlow.Opening.SKIP
## The importer that detects game files, made on first use.
var importer: AssetImporter:
	get:
		if _importer == null:
			_importer = AssetImporterFactory.create()
		return _importer
	set(value):
		_importer = value
## The child process that runs an import.
var import_process := ImportProcess.new()
## The page views, in the flow's page order.
var views: Array[SetupPageView] = []
## Why the last save failed, or "".
var last_error: String = ""

var _importer: AssetImporter = null
var _arguments := PackedStringArray()
var _game_files_view: SetupGameFilesView
var _waiting: float = -1.0
var _store: LauncherStore = null
var _step: Label
var _blocker: Label
var _back: Button
var _next: Button


func _ready() -> void:
	if auto_begin:
		begin(OS.get_cmdline_user_args())


## Starts the screen for the user arguments [param arguments]: import mode,
## the skip, or the pages.
func begin(arguments: PackedStringArray) -> void:
	_arguments = arguments
	if ImportCommand.is_requested(arguments):
		_import_and_quit.call_deferred(arguments)
		return
	_store = LauncherStore.load_from(launcher_path)
	if not _store.error.is_empty():
		push_warning(_store.error)
	var location: AssetLocation = AssetLocation.resolve(arguments, _store)
	opening = SetupFlow.opening(arguments, _shift_held(), location.is_usable(), _store.found, _store.settings)
	if opening != SetupFlow.Opening.SKIP:
		open_pages(location.base_root if location.is_usable() else "")
		return
	if shift_grace <= 0.0:
		_leave(FrontEndScreen.SCENE)
		return
	_waiting = shift_grace


## Shows the pages over the saved settings, with [param root] the usable assets root or "".
func open_pages(root: String) -> void:
	_waiting = -1.0
	if _store == null:
		_store = LauncherStore.load_from(launcher_path)
	var saved: LauncherSettings = _store.settings
	flow = SetupFlow.create(saved, root, opening)
	flow.options.read(ProgressStore.load_from(progress_path), GraphicsStore.load_from(graphics_path).settings,
		saved, TexturePackReader.list(texture_pack_folders))
	flow.froglord.read(saved, not saved.froglord_dir.is_empty() and DirAccess.dir_exists_absolute(saved.froglord_dir))
	_build()
	var folder: String = saved.game_data_dir
	if folder.is_empty():
		folder = LauncherStore.legacy_game_folder(legacy_settings_path)
		if not folder.is_empty():
			flow.game_files.suggestion_note = "Suggested: the game folder the developer tools remembered."
	if not saved.disc_image_path.is_empty():
		_game_files_view.choose_disc(saved.disc_image_path)
	if not folder.is_empty():
		_game_files_view.choose_folder(folder)
	_show_page()


## Offers the texture packs installed in [member texture_pack_folders].
func offer_texture_packs() -> void:
	flow.options.offer_texture_packs(TexturePackReader.list(texture_pack_folders))


## Shows the next page when the shown one allows it.
func next_page() -> void:
	if flow.next():
		_show_page()


## Shows the previous page when the shown one allows it.
func previous_page() -> void:
	if flow.back():
		_show_page()


## Saves the launcher settings as the flow holds them; false with [member last_error] on failure.
func save_launcher() -> bool:
	last_error = LauncherStore.save(flow.launcher, launcher_path)
	if not last_error.is_empty():
		push_warning(last_error)
		_refresh()
	return last_error.is_empty()


## Saves every choice (launcher, progress and graphics settings), applies the
## window settings and opens the front end; false when something could not be saved.
func play() -> bool:
	if not flow.can_play():
		return false
	flow.finish()
	var problems := PackedStringArray()
	var progress: ProgressStore = ProgressStore.load_from(progress_path)
	flow.options.write_progress(progress)
	problems.append(progress.save(progress_path))
	var graphics: GraphicsSettings = GraphicsStore.load_from(graphics_path).settings
	flow.options.write_graphics(graphics)
	problems.append(GraphicsStore.save(graphics, graphics_path))
	problems.append(LauncherStore.save(flow.launcher, launcher_path))
	var failures := PackedStringArray()
	for problem: String in problems:
		if not problem.is_empty():
			failures.append(problem)
	last_error = "; ".join(failures)
	if not failures.is_empty():
		_refresh()
		return false
	GraphicsProfile.replace(graphics)
	if DisplayServer.get_name() != "headless":
		GraphicsApplier.apply_window(graphics)
	_leave(FrontEndScreen.SCENE)
	return true


func _process(delta: float) -> void:
	if _waiting < 0.0:
		return
	if _shift_held():
		_reopen()
		return
	_waiting -= delta
	if _waiting <= 0.0:
		_waiting = -1.0
		_leave(FrontEndScreen.SCENE)


func _input(event: InputEvent) -> void:
	if _waiting < 0.0:
		return
	var key: InputEventKey = event as InputEventKey
	var modifiers: InputEventWithModifiers = event as InputEventWithModifiers
	if (key != null and key.pressed and key.keycode == KEY_SHIFT) or (modifiers != null and modifiers.shift_pressed):
		_reopen()


func _reopen() -> void:
	opening = SetupFlow.Opening.REQUESTED
	var location: AssetLocation = AssetLocation.resolve(_arguments, _store)
	open_pages(location.base_root if location.is_usable() else "")


func _shift_held() -> bool:
	return DisplayServer.get_name() != "headless" and Input.is_key_pressed(KEY_SHIFT)


func _leave(scene: String) -> void:
	left_for = scene
	if change_scenes:
		get_tree().change_scene_to_file.call_deferred(scene)


func _import_and_quit(arguments: PackedStringArray) -> void:
	var code: int = ImportChild.run(ImportCommand.parse(arguments), importer, ProjectSettings.globalize_path("user://"))
	get_tree().quit(code)


func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	views.clear()
	theme = Theme.new()
	theme.default_font_size = FONT_SIZE
	var background := ColorRect.new()
	background.color = Color(0.09, 0.11, 0.1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, MARGIN)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)
	var heading := Label.new()
	heading.text = "Frogger setup"
	heading.add_theme_font_size_override("font_size", 20)
	layout.add_child(heading)
	SetupPageView.add_text(layout, SetupFlow.opening_text(flow.opening_reason), true)
	_step = Label.new()
	_step.add_theme_font_size_override("font_size", 16)
	layout.add_child(_step)
	layout.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	_game_files_view = SetupGameFilesView.new()
	for view: SetupPageView in [_game_files_view, SetupImportView.new(), SetupOptionsView.new(),
			SetupFrogLordView.new(), SetupPlayView.new()]:
		pages.add_child(view)
		view.setup(flow, self)
		view.edited.connect(_refresh)
		view.visible = false
		views.append(view)
	_blocker = Label.new()
	_blocker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blocker.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	layout.add_child(_blocker)
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size.x = 96
	_back.pressed.connect(previous_page)
	footer.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_next = Button.new()
	_next.custom_minimum_size.x = 96
	_next.pressed.connect(_on_next)
	footer.add_child(_next)


func _on_next() -> void:
	if flow.is_last():
		play()
	else:
		next_page()


func _show_page() -> void:
	for index: int in range(views.size()):
		views[index].visible = index == flow.index
	views[flow.index].shown()
	_refresh()
	_next.grab_focus()


func _refresh() -> void:
	if flow == null or _step == null:
		return
	_step.text = "Step %d of %d: %s" % [flow.index + 1, flow.pages.size(), flow.page().title()]
	var reason: String = flow.page().blocker()
	if flow.is_last() and not flow.can_play():
		reason = "There is nothing to play from yet: go back and import your game files."
	if not last_error.is_empty():
		reason = last_error
	_blocker.text = reason
	_blocker.visible = not reason.is_empty()
	_back.disabled = not flow.can_go_back()
	_next.text = "Play" if flow.is_last() else "Next"
	_next.disabled = not (flow.can_play() if flow.is_last() else flow.can_continue())
