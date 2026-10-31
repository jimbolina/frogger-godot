extends SceneTree
## Replays sparse keyboard stimuli through the viewer and compares fresh rules playback.

var _viewer: TerrainViewer
var _data: AssetCatalog

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ViewerArguments.value(arguments, "--output=")
	var route_path: String = ViewerArguments.value(arguments, "--route=")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	if not parsed is Dictionary:
		_finish("Route must be an object")
		return
	var route: Dictionary = parsed
	var goal: String = route.get("goal", "complete")
	if goal not in ["complete", "pink_delivery", "tongue_collection"]:
		_finish("Unknown route goal")
		return
	var inputs: Dictionary[int, int] = {}
	var duration: int = _integer(route.get("ticks", 0))
	var entries: Array = route.get("inputs", [])
	for value: Variant in entries:
		if not value is Array:
			_finish("Route inputs require [tick, mask]")
			return
		var pair: Array = value
		if pair.size() != 2:
			_finish("Route inputs require [tick, mask]")
			return
		var tick: int = _integer(pair[0])
		var mask: int = _integer(pair[1])
		if tick < 0 or tick >= duration or mask <= 0 or mask & ~255 or inputs.has(tick):
			_finish("Invalid or duplicate route input")
			return
		inputs[tick] = mask
	if duration <= 0 or duration > 10000:
		_finish("Route duration must be 1..10000")
		return
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		_finish(issue)
		return
	var located: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not located.is_ok():
		_finish(located.error)
		return
	_data = GameData.open(located.source, located.version)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.level_code = "ORG1"
	_viewer = TerrainViewer.new()
	_viewer.auto_open = false
	root.add_child(_viewer)
	await process_frame
	_viewer.set_process(false)
	_viewer.configure_input(arguments)
	issue = _viewer.open_scenario(scenario)
	if issue.is_empty():
		issue = _viewer.open_data(_data, false)
	if not issue.is_empty():
		_finish(issue)
		return
	if _viewer.replay_commands or _viewer.playing:
		_finish("Expected LIVE input and paused initial state")
		return
	var reference: GameplayRun = GameplayRun.create(_viewer.scenario.level, _viewer.scenario.initial)
	var prior_mask: int = 0
	var prior_held: int = 0
	var milestones: Array[Dictionary] = []
	var pink_delivered: bool = false
	var tongue_collected: bool = false
	for tick: int in duration:
		var mask: int = inputs.get(tick, 0)
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = mask & ~prior_held
		prior_held = mask
		command.held_mask = mask
		var before: GameplayState = reference.snapshot()
		var result: TickResult = reference.step(command, false)
		if not result.error.is_empty():
			_finish("Headless tick %d: %s" % [tick, result.error])
			return
		for bit: int in 8:
			if mask & (1 << bit):
				_key(_code(bit), true)
		await process_frame
		_key(KEY_PERIOD, true)
		await process_frame
		_key(KEY_PERIOD, false)
		for bit: int in 8:
			if mask & (1 << bit):
				_key(_code(bit), false)
		await process_frame
		if not _viewer.last_error.is_empty():
			_finish("Keyboard tick %d: %s" % [tick, _viewer.last_error])
			return
		var actual: GameplayState = _viewer.run.snapshot()
		if actual.frog.mode == FrogMode.DYING or actual.frog.lives < 3:
			_finish("Route must complete without deaths")
			return
		if JSON.stringify(TerrainTrace.facts(actual, true)) != JSON.stringify(TerrainTrace.facts(result.final_snapshot, true)):
			_finish("Keyboard/headless state mismatch at tick %d" % tick)
			return
		var new_collection: bool = false
		for event: TickEvent in result.events:
			if event.kind == TickEvent.Kind.REWARD and event.reward_id == 9 and _pink_home(actual):
				pink_delivered = true
				new_collection = true
			if event.kind == TickEvent.Kind.SOUND and event.sound_id == 5 and before.tongue.target_index >= 0 and actual.tongue.mode == TongueState.Mode.IDLE and _target_hidden(actual, before.tongue.target_index):
				tongue_collected = true
				new_collection = true
		if new_collection:
			await RenderingServer.frame_post_draw
			issue = ViewerCapture.save_image(root.get_texture().get_image(), folder.path_join("collection-%d.png" % actual.tick_index))
			if not issue.is_empty():
				_finish(issue)
				return
		var collected: int = actual.entity_environment.collected
		if collected != prior_mask:
			milestones.append({"tick": actual.tick_index, "collected": collected, "score": actual.flow.score, "lives": actual.frog.lives})
			prior_mask = collected
			await RenderingServer.frame_post_draw
			issue = ViewerCapture.save_image(root.get_texture().get_image(), folder.path_join("checkpoint-%02d.png" % collected))
			if not issue.is_empty():
				_finish(issue)
				return
	var final: GameplayState = _viewer.run.snapshot()
	var accepted_goal: bool = final.entity_environment.collected == 31 and final.flow.phase == LevelFlowState.Phase.COMPLETE if goal == "complete" else pink_delivered if goal == "pink_delivery" else tongue_collected
	if not accepted_goal or final.frog.lives < 3:
		_finish("Route failed goal %s or lost lives" % goal)
		return
	await RenderingServer.frame_post_draw
	issue = ViewerCapture.save_image(root.get_texture().get_image(), folder.path_join("final.png"))
	var report := FileAccess.open(folder.path_join("playthrough.json"), FileAccess.WRITE)
	if report == null:
		_finish("Cannot write playthrough report")
		return
	report.store_string(JSON.stringify({"accepted": issue.is_empty(), "goal": goal, "pink_delivered": pink_delivered, "tongue_collected": tongue_collected, "ticks": duration, "milestones": milestones, "final": TerrainTrace.facts(final, true)}, "\t"))
	report.close()
	_finish(issue)

func _code(bit: int) -> Key:
	var codes: Array[Key] = [KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_SHIFT, KEY_E, KEY_Q, KEY_CTRL]
	return codes[bit]

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _finish(issue: String) -> void:
	if not issue.is_empty():
		push_error(issue)
	print("org1_playthrough: " + ("PASS" if issue.is_empty() else "FAIL"))
	if _viewer != null:
		_viewer.queue_free()
	if _data != null:
		_data.close()
	quit(0 if issue.is_empty() else 1)

func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_finite(number) and number == floor(number) and number >= 0 and number <= 10000:
			return int(number)
	return -1

func _pink_home(state: GameplayState) -> bool:
	for index: int in state.entities.entities.size():
		var definition: EntityDefinition = _viewer.scenario.level.entity_collision.entities[index]
		var entity: EntitySnapshot = state.entities.entities[index]
		if definition.behavior.kind == EntityBehavior.Kind.BABY_FROG and entity.custom_state != null and entity.custom_state.home:
			return true
	return false

func _target_hidden(state: GameplayState, target: int) -> bool:
	for entity: EntitySnapshot in state.entities.entities:
		if entity.entity_index == target:
			return bool(entity.entity_flags & EntityDefinition.HIDDEN)
	return false
