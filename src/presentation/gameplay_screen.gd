class_name GameplayScreen
extends GameplayWorldView
## Dedicated single-player scene sharing the transactional host and world renderer.

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
var _hud: GameplayHud
var _status: Label
var _actions: HBoxContainer
var _replay: Button

func _ready() -> void:
	build_world()
	_frog.hide()
	smoothing = true
	_build_interface()
	if auto_open:
		var arguments: PackedStringArray = OS.get_cmdline_user_args()
		level_code = selected_level if not selected_level.is_empty() else ViewerArguments.value(arguments, "--level=")
		if level_code.is_empty():
			level_code = "ORG1"
		selected_level = ""
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
		return _show_error("Playable levels are ORG1–ORG5 and SUB1")
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
	build_frog(assets)
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

func _detach_game() -> void:
	_host.close()
	_host.run = null
	run = null
	_definition = null
	_current = null
	_previous = null
	playing = false
	_clear_entity_visuals()
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
	var start := RunStart.new()
	start.start_mode = RunStart.Mode.SINGLE_START
	start.camera_startup = true
	start.start_timer = 120
	return open_run(_definition, start)

## Installs a run for normal play or asset-free scene verification.
func open_run(definition: LevelDefinition, start: RunStart) -> String:
	_host.close()
	var replacement: GameplayRun = GameplayRun.create(definition, start)
	if not replacement.error.is_empty():
		return _show_error(replacement.error)
	_definition = definition
	run = replacement
	_host.open(run)
	_held = 0
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
		if not _host.submit(_host.sample(_current.tick_index, _held)):
			_show_error(_host.error)
	draw_state(_host.render_elapsed / GameplayHost.PERIOD if playing else 1.0)

func _accept(result: TickResult) -> void:
	if not result.error.is_empty():
		_show_error(result.error)
		reset_interpolation()
		return
	accept_state(result.final_snapshot)
	_host.render_elapsed = 0.0
	if _current.completed:
		playing = false
		reset_interpolation()
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
	var back := Button.new()
	back.text = "Return"
	back.pressed.connect(_return_to_menu)
	_actions.add_child(back)
	_actions.hide()

func _update_interface(events: Array[TickEvent] = []) -> void:
	if _status == null:
		return
	if _current != null:
		_hud.present(_current, _current.tick_index, events)
	var terminal: bool = _current != null and _current.completed
	_actions.visible = terminal or not last_error.is_empty()
	_replay.visible = _definition != null
	if not last_error.is_empty():
		_status.text = last_error
	elif terminal:
		_status.text = "Level complete" if _current.flow.phase == LevelFlowState.Phase.COMPLETE else "Game over"
	else:
		_status.text = "" if playing else "Paused — Space to resume"

func _show_error(message: String) -> String:
	last_error = message
	playing = false
	_update_interface()
	return message

func _return_to_menu() -> void:
	close_data()
	get_tree().change_scene_to_file("res://scenes/boot.tscn")
