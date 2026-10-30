extends SceneTree
## Captures the dedicated game scene while replaying real keyboard stimuli against pure rules.

var _screen: GameplayScreen
var _data: GameData
var _folder: String
var _forest_captures: Dictionary[String, bool] = {}
var _volcano_captures: Dictionary[String, bool] = {}
var _cave_captures: Dictionary[String, bool] = {}
var _prior_light_max: int = -1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	_folder = ViewerArguments.value(arguments, "--output=")
	var issue: String = ViewerCapture.prepare_folder(_folder)
	if not issue.is_empty():
		_finish(issue)
		return
	var code: String = ViewerArguments.value(arguments, "--level=")
	var ticks: int = ViewerArguments.value(arguments, "--ticks=").to_int()
	var route_path: String = ViewerArguments.value(arguments, "--route=")
	var inputs: Dictionary[int, int] = {}
	var goal: String = "game_over" if ViewerArguments.value(arguments, "--flow-check=") == "true" else "inspect"
	if not route_path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(route_path))
		if not parsed is Dictionary:
			_finish("Route must be an object")
			return
		var route: Dictionary = parsed
		ticks = _integer(route.get("ticks", 0))
		goal = route.get("goal", "complete")
		if goal not in ["complete", "pink_delivery", "tongue_collection"]:
			_finish("Unknown route goal")
			return
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
			if tick < 0 or tick >= ticks or mask <= 0 or mask & ~255 or inputs.has(tick):
				_finish("Invalid or duplicate route input")
				return
			inputs[tick] = mask
	if ticks <= 0 or ticks > 10000:
		_finish("Capture duration must be 1..10000")
		return
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		_finish(found.error)
		return
	_data = GameData.open(found.source, found.version)
	_screen = GameplayScreen.new()
	_screen.auto_open = false
	root.add_child(_screen)
	await process_frame
	_screen.set_process(false)
	issue = _screen.open_data(_data, code)
	if not issue.is_empty():
		_finish(issue)
		return
	var start := RunStart.new()
	start.start_mode = RunStart.Mode.SINGLE_START
	start.camera_startup = true
	start.start_timer = 120
	var reference: GameplayRun = GameplayRun.create(_screen._definition, start)
	_screen.draw_state(1.0)
	issue = await _capture("startup")
	if not issue.is_empty():
		_finish(issue)
		return
	var prior_held: int = 0
	var prior_collected: int = 0
	var prior_phase: int = -1
	var prior_bonus_stage: int = -1
	var milestones: Array[Dictionary] = []
	var pink_delivered: bool = false
	var tongue_collected: bool = false
	var timeout_seen: bool = false
	var respawn_seen: bool = false
	for tick: int in ticks:
		var mask: int = inputs.get(tick, 0)
		for bit: int in 8:
			if (mask & (1 << bit)) != (prior_held & (1 << bit)):
				_bound_key(bit, bool(mask & (1 << bit)))
		if mask != prior_held:
			await process_frame
		var command := TickCommand.new()
		command.tick_index = tick
		command.held_mask = mask
		command.pressed_mask = mask & ~prior_held
		prior_held = mask
		var before: GameplayState = reference.snapshot()
		var expected: TickResult = reference.step(command, false)
		var actual_result: TickResult = _screen.step_command(_screen._host.sample(tick, _screen._held), false)
		if not expected.error.is_empty() or not actual_result.error.is_empty():
			_finish("Tick %d: %s %s" % [tick, expected.error, actual_result.error])
			return
		var actual: GameplayState = _screen.run.snapshot()
		if JSON.stringify(TerrainTrace.facts(actual, true)) != JSON.stringify(TerrainTrace.facts(expected.final_snapshot, true)):
			var difference := FileAccess.open(_folder.path_join("mismatch.json"), FileAccess.WRITE)
			if difference != null:
				difference.store_string(JSON.stringify({"actual": TerrainTrace.facts(actual, true), "expected": TerrainTrace.facts(expected.final_snapshot, true)}, "\t"))
				difference.close()
			_finish("Keyboard/headless state mismatch at tick %d" % tick)
			return
		_screen.draw_state(1.0)
		issue = await _capture_forest_states(actual)
		if not issue.is_empty():
			_finish(issue)
			return
		issue = await _capture_volcano_states(actual)
		if not issue.is_empty():
			_finish(issue)
			return
		issue = await _capture_cave_states(actual)
		if not issue.is_empty():
			_finish(issue)
			return
		timeout_seen = timeout_seen or actual.frog.death_equate == FrogAnimationCatalog.TIMEOUT
		respawn_seen = respawn_seen or (actual.frog.lives < 3 and actual.flow.phase == LevelFlowState.Phase.PLAY)
		for event: TickEvent in actual_result.events:
			if event.kind == TickEvent.Kind.REWARD and event.reward_id == 9 and _pink_home(actual):
				pink_delivered = true
			if event.kind == TickEvent.Kind.SOUND and event.sound_id == 5 and before.tongue.target_index >= 0 and actual.tongue.mode == TongueState.Mode.IDLE and _target_hidden(actual, before.tongue.target_index):
				tongue_collected = true
		var collected: int = actual.entity_environment.collected
		if collected != prior_collected or actual.flow.phase != prior_phase or actual.tick_index == _screen._hud._help_tick + 16 or (actual.flow.phase == LevelFlowState.Phase.CHECKPOINT and actual.flow.bonus_stage != prior_bonus_stage) or tick in [29, 59, 89, 119, 149, 179, 209]:
			milestones.append({"tick": actual.tick_index, "collected": collected, "phase": actual.flow.phase, "bonus_stage": actual.flow.bonus_stage, "score": actual.flow.score, "lives": actual.frog.lives})
			issue = await _capture("tick-%04d-phase-%d-bonus-%d-checkpoints-%02d" % [actual.tick_index, actual.flow.phase, actual.flow.bonus_stage, collected])
			if not issue.is_empty():
				_finish(issue)
				return
		prior_collected = collected
		prior_phase = actual.flow.phase
		prior_bonus_stage = actual.flow.bonus_stage
		if actual.completed:
			break
	var final: GameplayState = _screen.run.snapshot()
	var accepted: bool = goal == "inspect" or (goal == "game_over" and timeout_seen and respawn_seen and final.flow.phase == LevelFlowState.Phase.GAME_OVER) or (goal == "complete" and final.entity_environment.collected == 31 and final.flow.phase == LevelFlowState.Phase.COMPLETE) or (goal == "pink_delivery" and pink_delivered) or (goal == "tongue_collection" and tongue_collected)
	if not accepted:
		_finish("Route did not reach " + goal)
		return
	issue = await _capture("final")
	if not issue.is_empty():
		_finish(issue)
		return
	var restart_verified: bool = false
	if goal == "game_over":
		_key(KEY_R, true)
		await process_frame
		_key(KEY_R, false)
		await process_frame
		var restarted: GameplayState = _screen.run.snapshot()
		if restarted.tick_index != 0 or restarted.frog.lives != 3 or restarted.flow.phase != LevelFlowState.Phase.START or not _screen.playing:
			_finish("Keyboard restart did not create a fresh session")
			return
		restart_verified = true
		_screen.draw_state(1.0)
		issue = await _capture("restart")
		if not issue.is_empty():
			_finish(issue)
			return
	var report := FileAccess.open(_folder.path_join("gameplay.json"), FileAccess.WRITE)
	if report == null:
		_finish("Cannot write capture report")
		return
	report.store_string(JSON.stringify({"accepted": accepted, "goal": goal, "level": code, "window_size": [root.size.x, root.size.y], "viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y], "timeout_seen": timeout_seen, "respawn_seen": respawn_seen, "restart_verified": restart_verified, "ticks": final.tick_index, "milestones": milestones, "forest_captures": _forest_captures.keys(), "volcano_captures": _volcano_captures.keys(), "cave_captures": _cave_captures.keys(), "final": TerrainTrace.facts(final, true)}, "\t"))
	report.close()
	_finish("")

func _capture(label: String) -> String:
	await process_frame
	await RenderingServer.frame_post_draw
	return ViewerCapture.save_image(root.get_texture().get_image(), _folder.path_join(label + ".png"))

func _bound_key(bit: int, pressed: bool) -> void:
	var action: int = BindingInput.COMMANDS.find(1 << bit)
	var scancode: int = _screen.input.bindings.key(_screen.input.record, action)
	_key(KeyScancodes.godot_key(scancode) as Key, pressed, KeyScancodes.godot_location(scancode) as KeyLocation)

func _key(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)

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
		var definition: EntityDefinition = _screen._definition.entity_collision.entities[index]
		var entity: EntitySnapshot = state.entities.entities[index]
		if definition.behavior.kind == EntityBehavior.Kind.BABY_FROG and entity.custom_state != null and entity.custom_state.home:
			return true
	return false

func _target_hidden(state: GameplayState, target: int) -> bool:
	for entity: EntitySnapshot in state.entities.entities:
		if entity.entity_index == target:
			return bool(entity.entity_flags & EntityDefinition.HIDDEN)
	return false

func _finish(issue: String) -> void:
	if not issue.is_empty():
		push_error(issue)
	print("gameplay_capture: " + ("PASS" if issue.is_empty() else "FAIL"))
	if _screen != null:
		_screen.close_data()
		_screen.queue_free()
	if _data != null:
		_data.close()
	quit(0 if issue.is_empty() else 1)

func _capture_forest_states(state: GameplayState) -> String:
	if state.entities == null or _screen._definition.entity_collision == null:
		return ""
	for slot: int in state.entities.entities.size():
		var entity: EntitySnapshot = state.entities.entities[slot]
		if not entity.live or entity.custom_state == null:
			continue
		var kind: EntityBehavior.Kind = _screen._definition.entity_collision.entities[slot].behavior.kind
		if kind not in [EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG]:
			continue
		var kind_name: String = EntityBehavior.Kind.keys()[kind]
		var label: String = "forest-%s-mode-%d" % [kind_name.to_lower(), entity.custom_state.mode]
		if _forest_captures.has(label):
			continue
		_forest_captures[label] = true
		var issue: String = await _capture(label + "-tick-%04d" % state.tick_index)
		if not issue.is_empty():
			return issue
	return ""

func _capture_volcano_states(state: GameplayState) -> String:
	if state.entities == null or _screen._definition.entity_collision == null:
		return ""
	for slot: int in state.entities.entities.size():
		var entity: EntitySnapshot = state.entities.entities[slot]
		if not entity.live or entity.entity_flags & EntityDefinition.NO_DISPLAY:
			continue
		if not _screen._camera.is_position_in_frustum(GameSpace.transform(entity.matrix12).origin):
			continue
		var definition: EntityDefinition = _screen._definition.entity_collision.entities[slot]
		var label: String = ""
		var kind: EntityBehavior.Kind = definition.behavior.kind if entity.custom_state != null else EntityBehavior.Kind.UNKNOWN
		match kind:
			EntityBehavior.Kind.VOL_COLOUR_SWITCH:
				label = "volcano-switch-colour-%d-state-%d-action-%d" % [definition.volcano.colour, entity.custom_state.mode, entity.animation.action]
			EntityBehavior.Kind.MOVING_PLATFORM:
				if state.attachment.current_entity_index == entity.entity_index:
					label = "volcano-platform-carrying"
			EntityBehavior.Kind.VOL_FALLING_PLATFORM:
				label = "volcano-falling-state-%d-collision-%d" % [entity.custom_state.mode, int(not bool(entity.entity_flags & EntityDefinition.NO_COLLISION))]
		if definition.form_name in ["VOL_MECHANISM", "VOL_FURNACE_PLATFORM", "VOL_LAVA_SPRAY", "VOL_SPINNER"]:
			label = "volcano-" + definition.form_name.to_lower()
		if label.is_empty() or _volcano_captures.has(label):
			continue
		_volcano_captures[label] = true
		var issue: String = await _capture(label + "-tick-%04d" % state.tick_index)
		if not issue.is_empty():
			return issue
	return ""

func _capture_cave_states(state: GameplayState) -> String:
	if not _screen._definition.cave_light or state.entity_environment == null:
		return ""
	var labels: PackedStringArray = []
	var maximum: int = state.entity_environment.light_max_squared
	if _prior_light_max >= 0:
		if maximum < _prior_light_max:
			labels.append("cave-light-decay-first")
		elif maximum == _prior_light_max + 8:
			labels.append("cave-light-gain-firefly")
		elif maximum >= _prior_light_max + 65536:
			labels.append("cave-light-gain-pickup")
	_prior_light_max = maximum
	if state.entities != null and _screen._definition.entity_collision != null:
		for slot: int in state.entities.entities.size():
			var entity: EntitySnapshot = state.entities.entities[slot]
			if not entity.live or entity.entity_flags & (EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY):
				continue
			if not _screen._camera.is_position_in_frustum(GameSpace.transform(entity.matrix12).origin):
				continue
			var kind: EntityBehavior.Kind = _screen._definition.entity_collision.entities[slot].behavior.kind
			if kind == EntityBehavior.Kind.FIREFLY:
				labels.append("cave-firefly-visible")
			elif kind == EntityBehavior.Kind.FAT_FIRE_FLY:
				labels.append("cave-fat-fire-fly-visible")
			if entity.colour_scaled and entity.model_present:
				if entity.colour_scale == Vector3i.ZERO:
					labels.append("cave-fade-dark")
				elif entity.colour_scale.x < 128:
					labels.append("cave-fade-partial")
	for label: String in labels:
		if _cave_captures.has(label):
			continue
		_cave_captures[label] = true
		var issue: String = await _capture(label + "-tick-%04d" % state.tick_index)
		if not issue.is_empty():
			return issue
	return ""
