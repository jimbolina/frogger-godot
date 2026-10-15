extends SceneTree
## Exercises Godot's input dispatch, guarded controls and complete inspection reset.

var _viewer: TerrainViewer
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		push_error(found.error)
		quit(1)
		return
	var data: GameData = GameData.open(found.source, found.version)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var issue: String = scenario.apply_arguments(arguments)
	if not issue.is_empty():
		push_error(issue)
		data.close()
		quit(1)
		return
	scenario.level_code = "ORG1"
	_viewer = TerrainViewer.new()
	_viewer.auto_open = false
	root.add_child(_viewer)
	await process_frame
	_viewer.set_process(false)
	_viewer.configure_input(arguments)
	issue = _viewer.open_scenario(scenario)
	if issue.is_empty():
		issue = _viewer.open_data(data, true)
	if not issue.is_empty():
		push_error(issue)
		quit(1)
		return
	_check(not _viewer.playing and not _viewer.replay_commands, "opens LIVE and paused")
	_check(_viewer.scenario.commands.is_empty(), "no automatic commands")
	var initial: String = JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot(), true))
	for tick: int in 52:
		var key: Key = KEY_UP if tick in [0, 12] else KEY_DOWN if tick in [34, 46] else KEY_NONE
		if key != KEY_NONE:
			await _key(key, true)
		await _tap(KEY_PERIOD)
		if key != KEY_NONE:
			await _key(key, false)
		if not _viewer.last_error.is_empty():
			_failures.append("route tick %d: %s" % [tick, _viewer.last_error])
			break
	var bank: RunSnapshot = _viewer.run.snapshot()
	_check(bank.tick_index == 52 and bank.current_entity_index == -1 and bank.mode == 0 and bank.world_position == Vector3i(128, -256, -128), "keyboard round-trip bank return")
	await _tap(KEY_SPACE)
	_check(_viewer.playing, "resume dispatch")
	_viewer._process(1.0 / 30.0)
	await _tap(KEY_SPACE)
	_check(not _viewer.playing and _viewer.run.snapshot().tick_index == 53, "pause dispatch")
	_viewer._process(1.0)
	_check(_viewer.run.snapshot().tick_index == 53, "paused clock remains fixed")
	await _tap(KEY_R)
	_check(JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot(), true)) == initial, "complete reset")
	_check(_viewer._held == 0 and _viewer._sampled_held == 0 and not _viewer.replay_commands, "reset clears buffers and retains live mode")
	await _key(KEY_DOWN, true)
	await _tap(KEY_PERIOD)
	_check(_viewer.last_error.contains("boundary") and not _viewer.playing, "boundary rejection pauses")
	_check(JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot(), true)) == initial, "boundary rejects complete tick")
	await _key(KEY_DOWN, false)
	await _tap(KEY_R)
	await _key(KEY_E, true)
	await _tap(KEY_PERIOD)
	await _key(KEY_E, false)
	for unused: int in 48:
		await _tap(KEY_PERIOD)
	var expected_direction: int = _viewer.run.snapshot().camera.controller_directions[0]
	_check(expected_direction != 0, "camera turn completes")
	await _key(KEY_UP, true)
	await _tap(KEY_PERIOD)
	await _key(KEY_UP, false)
	_check(_viewer.last_error.is_empty() and _viewer.run.snapshot().direction == expected_direction, "camera-relative keyboard hop")
	await _tap(KEY_R)
	await _tap(KEY_TAB)
	await _tap(KEY_R)
	_check(_viewer.replay_commands and not _viewer.playing, "reset retains replay mode")
	await _tap(KEY_TAB)
	_viewer.scenario.tick_limit = 1
	await _tap(KEY_SPACE)
	for unused: int in 3:
		_viewer._process(1.0 / 30.0)
	_check(_viewer.playing and _viewer.run.snapshot().tick_index == 3, "live input has no replay tick limit")
	await _tap(KEY_R)
	var folder: String = ViewerArguments.value(arguments, "--screenshot-dir=")
	if not folder.is_empty():
		await RenderingServer.frame_post_draw
		issue = ViewerCapture.prepare_folder(folder)
		if issue.is_empty():
			issue = ViewerCapture.save_image(root.get_texture().get_image(), folder.path_join("org1-keyboard-reset.png"))
		_check(issue.is_empty(), issue)
	for failure: String in _failures:
		push_error(failure)
	print("org1_keyboard: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _tap(code: Key) -> void:
	await _key(code, true)
	await _key(code, false)

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
	print("%s: %s" % ["ok" if condition else "FAIL", label])
