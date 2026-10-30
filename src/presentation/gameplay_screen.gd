class_name GameplayScreen
extends GameplayWorldView
## Dedicated single-player scene sharing the transactional host and world renderer.

## Command-line flag that skips creating sound-effect and music players.
const NO_AUDIO_FLAG: String = "--no-audio"

static var selected_level: String = ""
var auto_open: bool = true
var level_code: String = "ORG1"
var run: GameplayRun
var last_error: String = ""
var _data: GameData
var _owns_data: bool = false
var _definition: LevelDefinition
var _host := GameplayHost.new()
var _held: int = 0
## Optional owner playthrough recording requested on the command line.
var recorder: InputRecorder = null
var _hud: GameplayHud
var _status: Label
var _actions: HBoxContainer
var _replay: Button
var _advance: Button
var _back: Button
var _advance_event: int = -1
var _advance_events: PackedInt32Array = PackedInt32Array()
var _next_level: int = -1
var _session_finished: bool = false
var _model_origins: EntityModelOrigins = null
## Problems from the latest map-less entity model resolution, shown to callers instead of failing.
var entity_model_diagnostics := PackedStringArray()
## The player's disc image for level music, located from the command line or environment, or null.
var disc: DiscAudio = null

func _ready() -> void:
	audio_enabled = not ViewerArguments.has_flag(OS.get_cmdline_user_args(), NO_AUDIO_FLAG)
	build_world()
	_frog.hide()
	smoothing = true
	_build_interface()
	if auto_open:
		var arguments: PackedStringArray = OS.get_cmdline_user_args()
		recorder = InputRecorder.from_arguments(arguments)
		level_code = selected_level if not selected_level.is_empty() else ViewerArguments.value(arguments, "--level=")
		if level_code.is_empty():
			level_code = "ORG1"
		selected_level = ""
		if audio_enabled:
			disc = DiscAudio.locate(arguments, OS.get_environment(DiscAudio.ENVIRONMENT_VARIABLE))
		var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
		if found.is_ok():
			open_data(GameData.open(found.source, found.version), level_code, true)
		else:
			_show_error(found.error)

func _exit_tree() -> void:
	close_data()

## Opens an explicitly selected level, borrowing the data unless ownership is transferred.
func open_data(data: GameData, code: String, take_ownership: bool = false) -> String:
	_finish_pending()
	if data != _data:
		close_data()
		_owns_data = take_ownership
	else:
		_detach_game()
		if take_ownership:
			_owns_data = true
	_data = data
	level_code = code
	var level_number: int = FroggerIds.level_from_code(code)
	if not GameplaySetup.supports_level(level_number):
		return _show_error("Playable levels are ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4")
	if data == null or not data.is_valid():
		return _show_error("A valid player data folder is required")
	var scene_data: MapSceneData = MapSceneData.load_level(data, level_number)
	if not scene_data.error.is_empty():
		return _show_error(scene_data.error)
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(data)
	if not assets.error.is_empty():
		return _show_error(assets.error)
	var setup: GameplaySetup = GameplaySetup.from_data(data, level_number, scene_data.map, assets.model, assets.action_lengths)
	if not setup.error.is_empty():
		return _show_error(setup.error)
	var hud_error: String = _hud.configure(data)
	if not hud_error.is_empty():
		return _show_error(hud_error)
	_definition = setup.definition
	_host.close()
	_clear_entity_visuals()
	if _frog_model != null:
		remove_child(_frog_model)
		_frog_model.queue_free()
		_frog_model = null
	build_map(scene_data)
	var effect_issue: String = _hud.configure_effects(scene_data.effects)
	if not effect_issue.is_empty():
		scene_data.diagnostics.append(effect_issue)
	build_frog(assets)
	_configure_level_audio(data, level_number)
	var issue: String = restart()
	if not issue.is_empty():
		return issue
	build_entities(_definition.entity_collision, scene_data, data)
	draw_state(1.0)
	return ""

## Joins pending work and releases owned source data after detaching its consumers.
func close_data() -> void:
	_detach_game()
	if _owns_data and _data != null:
		_data.close()
	_data = null
	_owns_data = false
	configure_audio(null)
	configure_music(null, -1)

func _configure_level_audio(data: GameData, level_number: int) -> void:
	if voice_view() == null:
		return
	var ids := PackedInt32Array()
	for sound: LogicalSoundDefinition in _definition.sounds:
		ids.append(sound.sound_id)
	configure_audio(AudioResources.from_data(data, _definition.sounds), ids)
	var directory: String = data.source.directory if data.source != null else ""
	configure_music(disc, data.tables.music().track_for_level(level_number), directory)

func _detach_game() -> void:
	_host.close()
	_host.run = null
	run = null
	_definition = null
	_model_origins = null
	entity_model_diagnostics = PackedStringArray()
	_current = null
	_previous = null
	playing = false
	_clear_entity_visuals()
	collapse_effects()
	if _frog_model != null:
		remove_child(_frog_model)
		_frog_model.queue_free()
		_frog_model = null
	frog_assets = null
	_map_instance = null
	if _ground != null:
		for child: Node in _ground.get_children():
			_ground.remove_child(child)
			child.queue_free()
	if _hud != null:
		_hud.clear()
	if _status != null:
		_status.text = ""
	if _actions != null:
		_actions.hide()

## Creates a fresh session while retaining the selected level and decoded assets.
func restart() -> String:
	if _definition == null:
		return _show_error("Select a level before restarting")
	var start: RunStart
	if FrontEndSession.active:
		start = FrontEndSession.run_start()
	else:
		start = RunStart.new()
		start.start_mode = RunStart.Mode.SINGLE_START
		start.camera_startup = true
		start.start_timer = 120
	_session_finished = false
	return open_run(_definition, start, _model_origins)

## Installs a run for normal play or asset-free scene verification.
## Supplied `origins` rebuild entity visuals without a map, borrowing their data; null keeps the current visuals.
func open_run(definition: LevelDefinition, start: RunStart, origins: EntityModelOrigins = null) -> String:
	_host.close()
	var replacement: GameplayRun = GameplayRun.create(definition, start)
	if not replacement.error.is_empty():
		return _show_error(replacement.error)
	_definition = definition
	set_effect_grid(definition.grid)
	run = replacement
	_host.open(run)
	_held = 0
	if recorder != null:
		recorder.reset(level_code)
	_previous = null
	_current = null
	for slot: int in _entity_models.size():
		if _entity_models[slot] != null:
			remove_child(_entity_models[slot])
			_entity_models[slot].queue_free()
			_entity_models[slot] = null
		_entity_generations[slot] = -1
	_frog_pose_tick = -1
	_entity_pose_tick = -1
	playing = true
	last_error = ""
	accept_state(run.snapshot())
	_model_origins = origins
	if origins != null:
		entity_model_diagnostics = build_mapless_entities(definition.entity_collision, origins)
	reset_interpolation()
	_update_interface()
	return ""

## Executes an explicit command using the same host as keyboard play.
func step_command(command: TickCommand, capture_phases: bool = true) -> TickResult:
	_finish_pending()
	var result: TickResult = _host.step(command, capture_phases)
	_accept(result)
	return result

## Pauses only after joining a pending command and collapses drawing history.
func set_paused(paused: bool) -> void:
	_finish_pending()
	playing = not paused and run != null and _current != null and not _current.completed and last_error.is_empty()
	pause_audio(paused)
	_held = 0
	_host.sampled_held = 0
	_host.elapsed = 0.0
	_host.render_elapsed = 0.0
	reset_interpolation()
	_update_interface()

func _process(delta: float) -> void:
	if run == null or _current == null:
		return
	_host.begin_frame(delta)
	var result: TickResult = _host.poll()
	if result != null:
		_accept(result)
	if _host.advance(delta, playing):
		_host.consume_period()
		var command: TickCommand = _host.sample(_current.tick_index, _held)
		if recorder != null:
			recorder.record(command)
		if not _host.submit(command):
			_show_error(_host.error)
	draw_state(_host.render_elapsed / GameplayHost.PERIOD if playing else 1.0)

func _accept(result: TickResult) -> void:
	if not result.error.is_empty():
		_show_error(result.error)
		reset_interpolation()
		return
	accept_state(result.final_snapshot, result.events)
	_host.render_elapsed = 0.0
	if _current.completed:
		playing = false
		reset_interpolation()
		_finish_front_end_level()
		if recorder != null and _current.flow.phase == LevelFlowState.Phase.COMPLETE:
			var issue: String = recorder.save(_current.tick_index)
			if not issue.is_empty():
				last_error = issue
	_update_interface(result.events)

func _finish_pending() -> void:
	if _host.pending():
		_accept(_host.finish())

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	var action: int = 0
	match key.physical_keycode:
		KEY_UP: action = TickCommand.NORTH
		KEY_RIGHT: action = TickCommand.EAST
		KEY_DOWN: action = TickCommand.SOUTH
		KEY_LEFT: action = TickCommand.WEST
		KEY_SHIFT: action = TickCommand.SUPER_HOP
		KEY_CTRL: action = TickCommand.TONGUE
		KEY_C: action = TickCommand.CROAK
		KEY_E: action = TickCommand.CAMERA_CLOCKWISE
		KEY_Q: action = TickCommand.CAMERA_ANTICLOCKWISE
	if action != 0:
		if key.pressed and playing:
			_held |= action
		else:
			_held &= ~action
	elif key.pressed:
		match key.physical_keycode:
			KEY_SPACE: set_paused(playing)
			KEY_R: restart()
			KEY_ESCAPE: _return_to_menu()

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = GameplayHud.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status = Label.new()
	_status.position = Vector2(16, 200)
	_status.size = Vector2(608, 70)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_status)
	_actions = HBoxContainer.new()
	_actions.position = Vector2(0, 280)
	_actions.size = Vector2(640, 40)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(_actions)
	_replay = Button.new()
	_replay.text = "Replay"
	_replay.pressed.connect(restart)
	_actions.add_child(_replay)
	_advance = Button.new()
	_advance.pressed.connect(_advance_front_end)
	_actions.add_child(_advance)
	_back = Button.new()
	_back.text = "Return"
	_back.pressed.connect(_return_to_menu)
	_actions.add_child(_back)
	_actions.hide()

func _update_interface(events: Array[TickEvent] = []) -> void:
	if _status == null:
		return
	if _current != null:
		_hud.present(_current, _current.tick_index, events)
	var terminal: bool = _current != null and _current.completed
	_actions.visible = terminal or not last_error.is_empty()
	var in_game: bool = FrontEndSession.active
	_replay.visible = _definition != null and not in_game
	_advance.visible = in_game and terminal and _advance_event >= 0
	if not last_error.is_empty():
		_status.text = last_error
	elif terminal:
		_status.text = "Level complete" if _current.flow.phase == LevelFlowState.Phase.COMPLETE else "Game over"
		if recorder != null and not recorder.saved_path.is_empty():
			_status.text += "\nRecorded " + recorder.saved_path
	else:
		_status.text = "" if playing else "Paused — Space to resume"

func _show_error(message: String) -> String:
	last_error = message
	playing = false
	_update_interface()
	return message

func _return_to_menu() -> void:
	close_data()
	if FrontEndSession.active:
		var finished: bool = _session_finished and _current != null and _current.flow.phase == LevelFlowState.Phase.COMPLETE
		if finished:
			FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
		else:
			FrontEndSession.end_game()
		get_tree().change_scene_to_file(FrontEndScreen.SCENE)
		return
	get_tree().change_scene_to_file("res://scenes/boot.tscn")

## Applies the finished level to the front-end progress and saves it.
func _finish_front_end_level() -> void:
	if not FrontEndSession.active or _session_finished or _current == null:
		return
	_session_finished = true
	var flow: LevelFlowState = _current.flow
	var progress: LevelProgress = FrontEndSession.progress
	var number: int = FroggerIds.level_from_code(level_code)
	if flow.gold_collected:
		FrontEndSession.collect_gold_frog(number)
	_advance_events = PackedInt32Array()
	_next_level = -1
	if flow.phase == LevelFlowState.Phase.COMPLETE:
		FrontEndSession.carry(_current)
		if number == LevelProgress.LEVEL_JUNGLE1:
			progress.reach_jungle_statue()
			progress.rewrite_jungle_row()
			_advance_events = PackedInt32Array([FrontEndFlow.Event.GAME_FINISHED, FrontEndFlow.Event.ENDING_DONE])
			_advance.text = "Finish"
		else:
			var completion: LevelProgress.Completion = progress.complete_level(number)
			if completion.found and completion.next_level >= 0:
				_next_level = completion.next_level
				progress.open_level_if_closed(_next_level)
				_advance_events = PackedInt32Array([FrontEndFlow.Event.LEVEL_FINISHED, FrontEndFlow.Event.NEXT_LEVEL])
				_advance.text = "Next level"
			else:
				_advance_events = PackedInt32Array([FrontEndFlow.Event.LEVEL_FINISHED, FrontEndFlow.Event.ZONE_COMPLETE])
				_advance.text = "Level select"
	else:
		_advance_events = PackedInt32Array([FrontEndFlow.Event.ALL_LIVES_LOST, FrontEndFlow.Event.GAME_OVER_DONE, FrontEndFlow.Event.CONTINUE_DONE])
		_advance.text = "Continue"
	_advance_event = _advance_events[0]
	var issue: String = FrontEndSession.save()
	if not issue.is_empty():
		last_error = issue

## Follows the flow from the finished level to its next page.
func _advance_front_end() -> void:
	var page: int = FrontEndPage.Page.GAME
	var problems := PackedStringArray()
	for event: int in _advance_events:
		page = FrontEndFlow.next_page(page, event, problems)
	for problem: String in problems:
		push_warning(problem)
	if page == FrontEndPage.Page.GAME and _next_level >= 0:
		FrontEndSession.progress.open_level(_next_level)
		FrontEndSession.save()
		FrontEndSession.level = _next_level
		selected_level = FroggerIds.level_code(_next_level)
		close_data()
		get_tree().reload_current_scene()
		return
	close_data()
	if page == FrontEndPage.Page.LEVEL_SELECT:
		FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
	else:
		FrontEndSession.end_game()
	get_tree().change_scene_to_file(FrontEndScreen.SCENE)
