class_name FrontEndScreen
extends Control
## Single-player main menu, options and controller pages, 3D level-select stack and high-score
## pages driven by [FrontEndFlow], drawn from the player's menu images in the chosen language.
##
## The pages play the generic menu sounds unless audio is turned off, at the saved effects
## volume; the saved music volume sets the music bus. Every page draws the front-end water: the
## main menu, options and controller pages through the shared [OptionsCamera], the level select
## through the stack camera. One [MenuWater] serves all of them, so the wave continues across
## pages, and a camera sweep begun on one options page continues on the next. The language is
## the saved setting or, when it follows the locale, the operating system's; [code]--language=[/code]
## with en, it, de, fr or es overrides it for the session without saving.
##
## The main menu runs the scrolly high-score table behind its buttons, the camera's Z following
## the frog once any sweep has ended. A finished game opens name entry, which leaves at once when
## nothing qualifies or the game was quit; entered initials go into the main and level tables,
## are saved and lead to the high-score view's tour. The options page's high-score row opens the
## view by hand. The high-score pages use their own static cameras; leaving them places the shared
## camera on the main or options preset.

## The front-end scene.
const SCENE: String = "res://scenes/front_end.tscn"
## The inspection tools' start screen.
const TOOLS_SCENE: String = "res://scenes/boot.tscn"
## The dedicated game scene.
const GAME_SCENE: String = "res://scenes/game/gameplay.tscn"
## Side margin of the page content.
const MARGIN: int = 24
## Main-menu sprite rows: the first sits MAIN_MENU_Y_OFFSET above the bottom once the fly-on has
## lifted it 8 a tick for 10 ticks (tempopt.c:1222-1226, :1486-1488); the rows are 16 apart.
const MENU_ROW_Y: int = StackLayout.DISPLAY_HEIGHT - 80
const MENU_ROW_PITCH: int = 16
const MENU_SLIDE: int = 8
## The cloud poly's border around the widest sprite and its subtractive colour (tempopt.c:1237-1266).
const CLOUD_BORDER: int = 8
const CLOUD_COLOUR: Color = Color(0.25, 0.25, 0.25)
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
## FrogLord names of the name-entry page's rub-out and end sounds.
const GULP_SOUND: String = "GEN_FROG_FLY_GULP"
const EXPLODE_SOUND: String = "GEN_FROG_EXPLODE"
## Sound of each [enum HighScoreEntry.EventKind], or "" for none.
const ENTRY_SOUNDS: PackedStringArray = [HOP_SOUND, SPLASH_SOUND, CROAK_SOUND, GULP_SOUND, EXPLODE_SOUND, "", "", ""]
## Sound of each [enum HighScoreTour.EventKind], or "" for none.
const TOUR_SOUNDS: PackedStringArray = [HOP_SOUND, CROAK_SOUND, SPLASH_SOUND, "", "", "", "", "", "", ""]
## Command-line argument choosing the language for the session.
const LANGUAGE_ARGUMENT: String = "--language="
## Sound of each [enum OptionsMenu.EventKind], or "" for none.
const OPTIONS_SOUNDS: PackedStringArray = [HOP_SOUND, SPLASH_SOUND, HOP_SOUND, CROAK_SOUND, "", "", "", "", "", ""]

var page: int = FrontEndPage.Page.MAIN_MENU
var assets: FrontEndAssets
## The options page's models, frog, sprite images and lights.
var options_models: OptionsModels
## The water animation shared by the pages, its frame count starting when the screen opens.
var water: MenuWater = MenuWater.create()
## The options camera shared by the main menu, options and controller pages.
var camera_rig: OptionsCamera = OptionsCamera.new()

var _background: ColorRect
var _content: Control
var _first_focus: Control
## The main menu's sprites top to bottom, slid by the scrolly table's fly-on.
var _menu_sprites: Array[TextureButton] = []
## False until the menu's first sprite has taken focus, so only later moves hop.
var _menu_focused: bool = false
var _music: MusicPlayer
var _sounds: Dictionary[String, AudioStreamPlayer] = {}
var _sound_definitions: Dictionary[String, LogicalSoundDefinition] = {}
var _main_water: MenuWaterView
var _options: OptionsView
var _controls: ControlsView
var _options_row: int = OptionsMenu.Row.EXIT
var _camera_elapsed: float = 0.0
var _camera_before_source: Vector3i = MenuWaterView.MAIN_SOURCE
var _camera_before_target: Vector3i = MenuWaterView.MAIN_TARGET
var _entry: HighScoreEntryView
var _table: HighScoreTableView
var _scores_from_options: bool = false
var _entry_score: int = 0
## The main menu's scrolly high-score table and its drawing, while the main menu shows.
var menu_scores: HighScoreScene
var menu_scores_view: HighScoreSceneView


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
	if issue.is_empty():
		options_models = OptionsModels.from_data(data)
		issue = options_models.error
	FrontEndSession.diagnostics.append_array(assets.diagnostics)
	if options_models != null:
		FrontEndSession.diagnostics.append_array(options_models.diagnostics)
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
	if page != FrontEndPage.Page.MAIN_MENU or _main_water == null:
		return
	_camera_elapsed += delta
	if _camera_elapsed >= MenuWaterView.PERIOD:
		_camera_elapsed = 0.0 if _camera_elapsed > MenuWaterView.PERIOD * 2.0 else _camera_elapsed - MenuWaterView.PERIOD
		tick_main_menu()
	_draw_main_menu(_camera_elapsed / MenuWaterView.PERIOD)


## Runs one main-menu tick: the water, any camera sweep, the scrolly table and its sounds, then
## the camera's follow of the frog.
func tick_main_menu() -> void:
	if _main_water == null:
		return
	_camera_before_source = camera_rig.source
	_camera_before_target = camera_rig.target
	_main_water.tick()
	if camera_rig.timer != 0:
		camera_rig.tick()
	if menu_scores != null:
		for kind: int in menu_scores.tick(water, true):
			_play_sound(TOUR_SOUNDS[kind])
		menu_scores_view.step()
		if camera_rig.timer == 0 and menu_scores.camera_followed:
			camera_rig.follow_z(menu_scores.camera_source_z, menu_scores.camera_target_z)
		_place_menu_sprites()
	_draw_main_menu(0.0)


## Draws the main menu [param fraction] of the way from the previous tick to the last one, the
## camera blended between the two ticks' eye and target as [OptionsView] blends its frames.
func _draw_main_menu(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var source := Vector3i(Vector3(_camera_before_source).lerp(Vector3(camera_rig.source), weight).round())
	var target := Vector3i(Vector3(_camera_before_target).lerp(Vector3(camera_rig.target), weight).round())
	_main_water.camera.transform = MenuWaterView.camera_transform(source, target)
	_main_water.render(weight)
	if menu_scores_view != null:
		menu_scores_view.draw(weight, source, target)


## Applies [param event] to the current page and shows the result.
func _send(event: int) -> void:
	var problems := PackedStringArray()
	var next: int = FrontEndFlow.next_page(page, event, problems)
	_options_row = OptionsMenu.Row.EXIT
	if page == FrontEndPage.Page.CONTROLS:
		_options_row = OptionsMenu.Row.CONTROLS
	elif page == FrontEndPage.Page.HIGH_SCORE_VIEW:
		_options_row = OptionsMenu.Row.VIEW_SCORES
	if next == FrontEndPage.Page.HIGH_SCORE_VIEW:
		_scores_from_options = page == FrontEndPage.Page.OPTIONS
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
	_entry = null
	_table = null
	menu_scores = null
	menu_scores_view = null
	_background.visible = false
	match page:
		FrontEndPage.Page.LEVEL_SELECT:
			_build_level_select()
		FrontEndPage.Page.HIGH_SCORE_INPUT:
			_build_high_score_input()
			return
		FrontEndPage.Page.HIGH_SCORE_VIEW:
			_build_high_score_view()
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
	_camera_before_source = camera_rig.source
	_camera_before_target = camera_rig.target
	_main_water = MenuWaterView.create_with_camera(water, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	_main_water.camera.transform = camera_rig.transform()
	_content.add_child(_main_water)
	_main_water.set_process(false)
	if FrontEndSession.board != null:
		menu_scores = HighScoreScene.create(FrontEndSession.board.main)
		menu_scores_view = HighScoreSceneView.create_for(menu_scores, options_models)
		_main_water.add_child(menu_scores_view)
		_draw_main_menu(1.0)
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(panel)
	_menu_sprites = [_menu_sprite("opt_start", _start_game),
		_menu_sprite("opt_options", _send.bind(FrontEndFlow.Event.OPTIONS)), _menu_sprite("opt_exit", get_tree().quit)]
	var width: int = 0
	var last_height: int = 0
	for sprite: TextureButton in _menu_sprites:
		if sprite.texture_normal != null:
			width = maxi(width, int(sprite.texture_normal.get_width()))
			last_height = int(sprite.texture_normal.get_height())
	width += CLOUD_BORDER << 1
	var cloud := TextureRect.new()
	cloud.texture = options_models.image_texture(OptionsModels.CLOUD_IMAGE) if options_models != null else null
	cloud.stretch_mode = TextureRect.STRETCH_SCALE
	cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloud.modulate = CLOUD_COLOUR
	var cloud_material := CanvasItemMaterial.new()
	cloud_material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	cloud.material = cloud_material
	cloud.position = Vector2((StackLayout.DISPLAY_WIDTH - width) >> 1, MENU_ROW_Y - CLOUD_BORDER)
	cloud.size = Vector2(width, MENU_ROW_PITCH * 2 + last_height + 16 + CLOUD_BORDER)
	panel.add_child(cloud)
	for sprite: TextureButton in _menu_sprites:
		panel.add_child(sprite)
	var count: int = _menu_sprites.size()
	for index: int in count:
		var sprite: TextureButton = _menu_sprites[index]
		sprite.focus_neighbor_top = sprite.get_path_to(_menu_sprites[(index + count - 1) % count])
		sprite.focus_neighbor_bottom = sprite.get_path_to(_menu_sprites[(index + 1) % count])
	_place_menu_sprites()
	_first_focus = _menu_sprites[0]
	_menu_focused = false
	var tools := Button.new()
	tools.text = "Inspection tools"
	tools.focus_mode = Control.FOCUS_CLICK
	tools.pressed.connect(open_tools)
	tools.position = Vector2(StackLayout.DISPLAY_WIDTH - 160, 8)
	panel.add_child(tools)
	if not FrontEndSession.diagnostics.is_empty():
		var notes := Label.new()
		notes.text = "\n".join(FrontEndSession.diagnostics)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes.position = Vector2(MARGIN, MARGIN)
		notes.size = Vector2(StackLayout.DISPLAY_WIDTH - 2 * MARGIN - 160, 120)
		panel.add_child(notes)


## A main-menu sprite: Up and Down hop between rows and wrap (tempopt.c:1712-1744), fire croaks
## before [param action] runs (:1820).
func _menu_sprite(image_name: String, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = assets.texture(image_name)
	button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	button.pressed.connect(_play_sound.bind(CROAK_SOUND))
	button.pressed.connect(action)
	button.focus_entered.connect(_on_menu_focus.bind(button))
	button.focus_exited.connect(button.set_modulate.bind(Color.WHITE))
	return button


func _on_menu_focus(button: TextureButton) -> void:
	button.modulate = Color(1.0, 1.0, 0.6)
	if _menu_focused:
		_play_sound(HOP_SOUND)
	_menu_focused = true


## Centres each menu sprite on its row, slid down 8 for every fly-on tick still to run.
func _place_menu_sprites() -> void:
	var slide: int = menu_scores.fly_on * MENU_SLIDE if menu_scores != null else 0
	for index: int in _menu_sprites.size():
		var sprite: TextureButton = _menu_sprites[index]
		var sprite_width: int = int(sprite.texture_normal.get_width()) if sprite.texture_normal != null else 0
		sprite.position = Vector2((StackLayout.DISPLAY_WIDTH - sprite_width) >> 1, MENU_ROW_Y + index * MENU_ROW_PITCH + slide)


func _build_level_select() -> void:
	var first_time: bool = not FrontEndSession.level_chosen
	var view := LevelStackView.create(assets, FrontEndSession.stack, FrontEndSession.progress, FrontEndSession.level,
		first_time, Color.BLACK, water)
	view.input = BindingInput.new(FrontEndSession.bindings)
	view.stack_event.connect(_on_stack_event, CONNECT_DEFERRED)
	_content.add_child(view)


func _build_options() -> void:
	_options = OptionsView.create(assets, water, camera_rig, FrontEndSession.music_volume, FrontEndSession.sound_volume,
		_options_row, true, options_models)
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
				OptionsMenu.Request.VIEW_SCORES:
					_send(FrontEndFlow.Event.VIEW_HIGH_SCORES)


func _build_high_score_input() -> void:
	var board: HighScoreBoard = FrontEndSession.board
	var startup: int = HighScoreBoard.Startup.NO_HIGH_SCORE
	_entry_score = FrontEndSession.final_score
	var quit: bool = FrontEndSession.game_quit
	FrontEndSession.consume_entry_request()
	if board != null:
		startup = board.input_startup(_entry_score, quit)
	match startup:
		HighScoreBoard.Startup.GAME_QUIT:
			camera_rig.snap(OptionsMenu.Camera.MAIN)
			_send(FrontEndFlow.Event.GAME_QUIT)
		HighScoreBoard.Startup.NO_HIGH_SCORE:
			camera_rig.snap(OptionsMenu.Camera.MAIN)
			_send(FrontEndFlow.Event.NO_HIGH_SCORE)
		_:
			_entry = HighScoreEntryView.create(assets, water, HighScoreEntry.create(true, false), options_models)
			_entry.input = BindingInput.new(FrontEndSession.bindings)
			_entry.page_event.connect(_on_entry_event.bind(_entry), CONNECT_DEFERRED)
			_content.add_child(_entry)


func _build_high_score_view() -> void:
	var board: HighScoreBoard = FrontEndSession.board
	if board == null:
		var none: Array[HighScoreRow] = []
		board = HighScoreBoard.create(none, none)
	var stack: LevelStack = FrontEndSession.stack
	var tour: HighScoreTour = HighScoreTour.create(StackLayout.create(stack), FrontEndSession.progress, board.main,
		_scores_from_options, not _scores_from_options, board.new_main, board.new_levels, not FrontEndSession.level_chosen,
		LevelStackView.name_widths(assets, stack))
	_table = HighScoreTableView.create(assets, water, tour, stack, FrontEndSession.progress, board, options_models)
	_table.input = BindingInput.new(FrontEndSession.bindings)
	_table.page_event.connect(_on_table_event.bind(_table), CONNECT_DEFERRED)
	_content.add_child(_table)


func _on_entry_event(kind: int, view: HighScoreEntryView) -> void:
	if view != _entry:
		return
	_play_sound(ENTRY_SOUNDS[kind])
	if kind != HighScoreEntry.EventKind.ENTERED:
		return
	var board: HighScoreBoard = FrontEndSession.board
	var initials: String = view.entry.initials
	board.enter(initials, _entry_score)
	board.enter_arcade_times(initials)
	var issue: String = FrontEndSession.save_scores()
	if not issue.is_empty():
		push_warning(issue)
	_send(FrontEndFlow.Event.ENTERED)


func _on_table_event(kind: int, view: HighScoreTableView) -> void:
	if view != _table:
		return
	_play_sound(TOUR_SOUNDS[kind])
	match kind:
		HighScoreTour.EventKind.BACK:
			camera_rig.snap(OptionsMenu.Camera.MAIN)
			_send(FrontEndFlow.Event.BACK)
		HighScoreTour.EventKind.TIMEOUT:
			camera_rig.snap(OptionsMenu.Camera.MAIN)
			_send(FrontEndFlow.Event.TIMEOUT)
		HighScoreTour.EventKind.BACK_TO_OPTIONS:
			camera_rig.snap(OptionsMenu.Camera.OPTIONS)
			_send(FrontEndFlow.Event.BACK_TO_OPTIONS)


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
	var names := PackedStringArray([HOP_SOUND, CROAK_SOUND, SPLASH_SOUND, TEST_SOUND, GULP_SOUND, EXPLODE_SOUND])
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
