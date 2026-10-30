class_name FrontEndScreen
extends Control
## Single-player main menu, options and controller pages and 3D level-select stack driven by
## [FrontEndFlow], drawn from the player's menu images in the chosen language.
##
## The pages play the generic menu sounds unless audio is turned off, at the saved effects
## volume; the saved music volume sets the music bus. Every page draws the front-end water: the
## main menu, options and controller pages through the shared [OptionsCamera], the level select
## through the stack camera. One [MenuWater] serves all of them, so the wave continues across
## pages, and a camera sweep begun on one options page continues on the next. The language is
## the saved setting or, when it follows the locale, the operating system's; [code]--language=[/code]
## with en, it, de, fr or es overrides it for the session without saving.

## The front-end scene.
const SCENE: String = "res://scenes/front_end.tscn"
## The inspection tools' start screen.
const TOOLS_SCENE: String = "res://scenes/boot.tscn"
## The dedicated game scene.
const GAME_SCENE: String = "res://scenes/game/gameplay.tscn"
## Side margin of the page content.
const MARGIN: int = 24
## CD track played on the menu pages (LEVEL_SELECT in the music table).
const MENU_TRACK: int = 13
## Colour behind the messages shown when the player's files cannot be used.
const BACKGROUND_COLOUR: Color = Color(0.04, 0.12, 0.05)
## FrogLord name of the generic hop sound the level-select stack plays.
const HOP_SOUND: String = "GEN_FROG_HOP"
## FrogLord name of the generic croak sound played when a level is started.
const CROAK_SOUND: String = "GEN_FROG_CROAK"
## FrogLord name of the splash played when the options frog lands (SFX_GEN_FROG_SPLASH1).
const SPLASH_SOUND: String = "GEN_SPLASH01"
## FrogLord name of the repeating croak that tests the effects volume.
const TEST_SOUND: String = "GEN_FROG_CROAK_REPEAT"
## Command-line argument choosing the language for the session.
const LANGUAGE_ARGUMENT: String = "--language="
## Sound of each [enum OptionsMenu.EventKind], or "" for none.
const OPTIONS_SOUNDS: PackedStringArray = [HOP_SOUND, SPLASH_SOUND, HOP_SOUND, CROAK_SOUND, "", "", "", "", "", ""]

var page: int = FrontEndPage.Page.MAIN_MENU
var assets: FrontEndAssets
## The water animation shared by the pages, its frame count starting when the screen opens.
var water: MenuWater = MenuWater.create()
## The options camera shared by the main menu, options and controller pages.
var camera_rig: OptionsCamera = OptionsCamera.new()

var _background: ColorRect
var _content: Control
var _first_focus: Control
var _music: MusicPlayer
var _sounds: Dictionary[String, AudioStreamPlayer] = {}
var _sound_definitions: Dictionary[String, LogicalSoundDefinition] = {}
var _main_water: MenuWaterView
var _options: OptionsView
var _controls: ControlsView
var _options_row: int = OptionsMenu.Row.EXIT
var _camera_elapsed: float = 0.0


func _ready() -> void:
	_background = ColorRect.new()
	_background.color = BACKGROUND_COLOUR
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		_show_message("No usable Frogger files were found (%s).\nSet FROGGER_DATA_DIR or use --data-dir=<folder>." % found.error)
		return
	var data: GameData = GameData.open(found.source, found.version)
	if not data.is_valid():
		_show_message("Game tables are unreadable: %s" % data.error)
		return
	var issue: String = FrontEndSession.load_progress(data)
	assets = FrontEndAssets.from_data(data, session_language(arguments))
	if issue.is_empty():
		issue = assets.error
	FrontEndSession.diagnostics.append_array(assets.diagnostics)
	var audio: bool = not ViewerArguments.has_flag(arguments, GameplayScreen.NO_AUDIO_FLAG)
	if issue.is_empty() and audio:
		_load_sounds(data)
	data.close()
	if not issue.is_empty():
		_show_message(issue)
		return
	AudioLevels.apply(FrontEndSession.music_volume, FrontEndSession.sound_volume)
	_apply_sound_volumes()
	if audio:
		_music = MusicPlayer.new()
		add_child(_music)
		var disc: DiscAudio = DiscAudio.locate(arguments, OS.get_environment(DiscAudio.ENVIRONMENT_VARIABLE))
		_music.select(disc, MENU_TRACK, found.source.directory)
		_music.restart()
	page = FrontEndSession.start_page
	_show_page()


## The language the front end draws: [param arguments]' [code]--language=[/code] code when it
## names one of the five, otherwise the saved setting resolved against the locale.
static func session_language(arguments: PackedStringArray) -> int:
	var code: String = ViewerArguments.value(arguments, LANGUAGE_ARGUMENT).strip_edges().to_lower()
	var chosen: int = GameLanguage.CODES.find(code)
	if chosen >= 0:
		return chosen
	if not code.is_empty():
		push_warning("Unknown language %s; expected one of %s" % [code, ", ".join(GameLanguage.CODES)])
	return GameLanguage.resolve(FrontEndSession.language, OS.get_locale())


func _process(delta: float) -> void:
	if page != FrontEndPage.Page.MAIN_MENU or _main_water == null or camera_rig.timer == 0:
		return
	_camera_elapsed += delta
	if _camera_elapsed >= MenuWaterView.PERIOD:
		_camera_elapsed = 0.0 if _camera_elapsed > MenuWaterView.PERIOD * 2.0 else _camera_elapsed - MenuWaterView.PERIOD
		camera_rig.tick()
		_main_water.camera.transform = camera_rig.transform()


## Applies [param event] to the current page and shows the result.
func _send(event: int) -> void:
	var problems := PackedStringArray()
	var next: int = FrontEndFlow.next_page(page, event, problems)
	_options_row = OptionsMenu.Row.CONTROLS if page == FrontEndPage.Page.CONTROLS else OptionsMenu.Row.EXIT
	for problem: String in problems:
		push_warning(problem)
	if next == FrontEndPage.Page.GAME:
		FrontEndSession.level_chosen = true
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	page = next
	_show_page()


func _show_page() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_first_focus = null
	_main_water = null
	_options = null
	_controls = null
	_background.visible = false
	match page:
		FrontEndPage.Page.LEVEL_SELECT:
			_build_level_select()
		FrontEndPage.Page.OPTIONS:
			_build_options()
		FrontEndPage.Page.CONTROLS:
			_build_controls()
		_:
			page = FrontEndPage.Page.MAIN_MENU
			_build_main_menu()
	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func _build_main_menu() -> void:
	_main_water = MenuWaterView.create_with_camera(water, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	_main_water.camera.transform = camera_rig.transform()
	_content.add_child(_main_water)
	var column := _column()
	var logo := TextureRect.new()
	logo.texture = assets.texture("froglogo")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	column.add_child(logo)
	var start := _image_button("opt_start", _start_game)
	column.add_child(start)
	_first_focus = start
	column.add_child(_image_button("opt_options", _send.bind(FrontEndFlow.Event.OPTIONS)))
	column.add_child(_image_button("opt_exit", get_tree().quit))
	var tools := Button.new()
	tools.text = "Inspection tools"
	tools.pressed.connect(open_tools)
	column.add_child(tools)
	if not FrontEndSession.diagnostics.is_empty():
		var notes := Label.new()
		notes.text = "\n".join(FrontEndSession.diagnostics)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(notes)


func _build_level_select() -> void:
	var first_time: bool = not FrontEndSession.level_chosen
	var view := LevelStackView.create(assets, FrontEndSession.stack, FrontEndSession.progress, FrontEndSession.level,
		first_time, Color.BLACK, water)
	view.input = BindingInput.new(FrontEndSession.bindings)
	view.stack_event.connect(_on_stack_event, CONNECT_DEFERRED)
	_content.add_child(view)


func _build_options() -> void:
	_options = OptionsView.create(assets, water, camera_rig, FrontEndSession.music_volume, FrontEndSession.sound_volume,
		_options_row)
	_options.menu_event.connect(_on_options_event, CONNECT_DEFERRED)
	_content.add_child(_options)


func _build_controls() -> void:
	_controls = ControlsView.create(assets, FrontEndSession.bindings.copy(), water, camera_rig)
	_controls.page_event.connect(_on_controls_event, CONNECT_DEFERRED)
	_content.add_child(_controls)


func _on_options_event(kind: int) -> void:
	if _options == null:
		return
	var menu: OptionsMenu = _options.menu
	_play_sound(OPTIONS_SOUNDS[kind])
	match kind:
		OptionsMenu.EventKind.VOLUME_STEP:
			FrontEndSession.music_volume = menu.music_volume
			FrontEndSession.sound_volume = menu.effects_volume
			AudioLevels.apply(FrontEndSession.music_volume, FrontEndSession.sound_volume)
			_apply_sound_volumes()
		OptionsMenu.EventKind.VOLUME_TEST_SOUND:
			_play_sound(TEST_SOUND)
		OptionsMenu.EventKind.STOP_TEST_SOUND:
			_stop_sound(TEST_SOUND)
		OptionsMenu.EventKind.LEAVE:
			_stop_sound(TEST_SOUND)
			_save()
			match menu.request:
				OptionsMenu.Request.CONTROLS:
					_send(FrontEndFlow.Event.CONTROLS)
				OptionsMenu.Request.MAIN_MENU:
					_send(FrontEndFlow.Event.BACK)


func _on_controls_event(kind: int) -> void:
	if _controls == null:
		return
	_play_sound(ControlsPage.sound_name(kind))
	if kind == ControlsPage.EventKind.EXIT:
		FrontEndSession.bindings = _controls.page.bindings().copy()
		_save()
		_send(FrontEndFlow.Event.BACK)


func _save() -> void:
	var issue: String = FrontEndSession.save()
	if not issue.is_empty():
		push_warning(issue)


func _on_stack_event(kind: int, level: int) -> void:
	match kind:
		StackSelector.EventKind.HOP:
			_play_sound(HOP_SOUND)
		StackSelector.EventKind.CROAK:
			_play_sound(CROAK_SOUND)
		StackSelector.EventKind.ENTER_GAME:
			_select_level(level)
		StackSelector.EventKind.BACK:
			_send(FrontEndFlow.Event.BACK)


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = MARGIN
	column.offset_top = MARGIN
	column.offset_right = -MARGIN
	column.offset_bottom = -MARGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(column)
	return column


func _image_button(image_name: String, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = assets.texture(image_name)
	button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	button.pressed.connect(action)
	button.focus_entered.connect(button.set_modulate.bind(Color(1.0, 1.0, 0.6)))
	button.focus_exited.connect(button.set_modulate.bind(Color.WHITE))
	return button


func _load_sounds(data: GameData) -> void:
	var setup: LogicalSoundSetup = LogicalSoundSetup.from_data(data, PackedInt32Array([FroggerIds.THEME_GENERAL]))
	if not setup.error.is_empty():
		push_warning("Menu sounds are unavailable: " + setup.error)
		return
	var resources: AudioResources = AudioResources.from_data(data, setup.definitions)
	SoundVoiceView.ensure_bus(SoundVoiceView.BUS, &"Master")
	var names := PackedStringArray([HOP_SOUND, CROAK_SOUND, SPLASH_SOUND, TEST_SOUND])
	for kind: int in ControlsPage.EventKind.values():
		if not ControlsPage.sound_name(kind).is_empty() and not names.has(ControlsPage.sound_name(kind)):
			names.append(ControlsPage.sound_name(kind))
	for sound_name: String in names:
		var sound_id: int = data.tables.names.sounds.index_of(sound_name) if data.tables.names.sounds != null else -1
		var definition: LogicalSoundDefinition = resources.definition_for(sound_id)
		var stream: AudioStreamWAV = resources.stream_for(sound_id) if definition != null else null
		if stream == null:
			push_warning("Menu sound %s (%d) is unavailable" % [sound_name, sound_id])
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.pitch_scale = AudioResources.pitch_scale(definition.note, 0)
		player.bus = SoundVoiceView.BUS
		add_child(player)
		_sounds[sound_name] = player
		_sound_definitions[sound_name] = definition


func _apply_sound_volumes() -> void:
	var level: int = AudioLevels.effect_volume(FrontEndSession.sound_volume)
	for sound_name: String in _sounds:
		var volumes: Vector2i = AudioResources.fixed_volumes(_sound_definitions[sound_name])
		_sounds[sound_name].volume_db = SoundVoiceView.mix(volumes, level).x


func _play_sound(sound_name: String) -> void:
	if _sounds.has(sound_name):
		_sounds[sound_name].play()


func _stop_sound(sound_name: String) -> void:
	if _sounds.has(sound_name):
		_sounds[sound_name].stop()


func _show_message(text: String) -> void:
	var column := _column()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	var tools := Button.new()
	tools.text = "Inspection tools"
	tools.pressed.connect(open_tools)
	column.add_child(tools)


func _start_game() -> void:
	FrontEndSession.begin_game()
	FrontEndSession.level_chosen = false
	FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
	_send(FrontEndFlow.Event.START)


func _select_level(level: int) -> void:
	FrontEndSession.level = level
	GameplayScreen.selected_level = FroggerIds.level_code(level)
	_send(FrontEndFlow.Event.SELECT_LEVEL)


## Switches to the inspection tools' start screen.
func open_tools() -> void:
	get_tree().change_scene_to_file(TOOLS_SCENE)
