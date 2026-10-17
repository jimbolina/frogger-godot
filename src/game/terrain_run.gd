class_name TerrainRun
extends RefCounted
## Frozen-source terrain movement, collision and ordered run systems at 30 ticks/sec.
## Owns detached frog/entity candidates; game-flow progression remains external.

const TICKS_PER_SECOND: int = 30
const GRAVITY_16: int = 0x100000
const NO_INPUT: int = 128
const MODE_STATIONARY: int = 0
const MODE_JUMPING: int = 1
var error: String = ""
var _grid: GridDefinition = null
var _default_cell: Vector2i = Vector2i.ZERO
var _default_direction: int = 0
var _state: RunSnapshot = null
var _controller_directions: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])
var _collision_enabled: bool = false
var _collision_bounds: Rect2i = Rect2i()
var _death_height: int = 30000
var _theme: int = 0
var _map_index: int = -1
var _camera_definition: GameplayCameraDefinition = null
var _action_lengths: PackedInt32Array = PackedInt32Array()
var _theme_name: StringName = &"SUB"
var _camera: GameplayCamera = null
var _random: SourceRandom = null
var _animation: FrogAnimationController = null
var _capture_phases: bool = true
var _candidate_camera: GameplayCamera = null
var _candidate_random: SourceRandom = null
var _candidate_animation: FrogAnimationController = null
var _entity_collision: EntityCollisionDefinition = null
var _entities: EntityRun = null
var _candidate_entities: EntityRun = null
var _source_id: String = ""
var _resource_id: int = -1
var _exploration_guard: ExplorationGuard = null
var _callback_error: String = ""
var _has_entity_updates: bool = false

## Validates and copies ordinary terrain, then creates a stationary component start.
static func create(level: LevelDefinition, initial: RunStart = null) -> TerrainRun:
	var run := TerrainRun.new()
	if level == null or level.grid == null:
		run.error = "Terrain run requires a level grid"
		return run
	run.error = run._copy_grid(level.grid)
	if not run.error.is_empty():
		return run
	run._default_cell = level.spawn_cell
	run._default_direction = level.spawn_direction
	run._collision_enabled = level.collision_enabled
	run._collision_bounds = level.collision_bounds
	run._death_height = level.theme_death_height
	run._theme = level.theme
	run._map_index = level.map_index
	run._camera_definition = level.camera.copy() if level.camera != null else null
	run._action_lengths = level.frog_action_lengths.duplicate()
	run._theme_name = level.theme_name
	run._source_id = level.source_id
	run._resource_id = level.resource_id
	if level.exploration_guard != null:
		run.error = level.exploration_guard.validate()
		if not run.error.is_empty():
			return run
		if level.entity_collision != null and level.entity_collision.lifecycle != null:
			run.error = "Guarded exploration requires all-attached entity lifetime"
			return run
		run._exploration_guard = level.exploration_guard.copy()
	if level.entity_collision != null:
		for contact: FormContactDefinition in level.entity_collision.contacts:
			if not contact.admission_exclusion.is_empty() and (run._exploration_guard == null or run._exploration_guard.frog_roots.is_empty()):
				run.error = "Contact exclusion requires animated inspection admission"
				return run
		if level.entity_collision.lifecycle != null and level.camera == null:
			run.error = "Visibility lifecycle requires an integrated camera"
			return run
		if level.entity_collision.platforms_enabled and level.camera == null:
			run.error = "Platform execution requires an integrated camera"
			return run
		if not level.collision_enabled:
			run.error = "Entity collision requires enabled frog collision"
			return run
		run.error = level.entity_collision.validate()
		if not run.error.is_empty():
			return run
		run._entity_collision = level.entity_collision.copy()
		for entity: EntityDefinition in run._entity_collision.entities:
			run._has_entity_updates = run._has_entity_updates or entity.script_definition != null or entity.background_admitted
		run._entities = EntityRun.create(run._entity_collision.entities, run._entity_collision.lifecycle)
		if not run._entities.error.is_empty():
			run.error = run._entities.error
			return run
	if run._collision_bounds.size.x <= 0 or run._collision_bounds.size.y <= 0 or run._theme < 0 or run._theme > 10 or run._map_index < -1 or run._map_index > 2147483647 or run._death_height < -2147483648 or run._death_height > 2147483647:
		run.error = "Collision setup requires positive fade bounds, a known theme and signed32 death height"
		return run
	for corner: int in [run._collision_bounds.position.x, run._collision_bounds.position.y, int(run._collision_bounds.position.x) + run._collision_bounds.size.x, int(run._collision_bounds.position.y) + run._collision_bounds.size.y]:
		if corner < -32768 or corner > 32767:
			run.error = "Fade bounds must fit source signed16 corners"
			return run
	run.error = run.reset(initial)
	return run

## Resets every owned clock, buffer and request count; failed starts preserve current state.
func reset(initial: RunStart = null) -> String:
	if _grid == null:
		return "Terrain run has no validated grid"
	var cell: Vector2i = _default_cell
	var direction: int = _default_direction
	var powers: int = 0
	var controller_directions := PackedInt32Array([0, 1, 2, 3])
	if initial != null:
		powers = initial.powerup_flags
		if initial.spawn_cell != Vector2i(-1, -1):
			cell = initial.spawn_cell
		if initial.spawn_direction != -1:
			direction = initial.spawn_direction
		if not initial.controller_directions.is_empty():
			controller_directions = initial.controller_directions.duplicate()
	if controller_directions.size() != 4:
		return "Controller directions require four cardinal values"
	for i: int in 4:
		if controller_directions[i] != ((controller_directions[0] + i) & 3):
			return "Controller directions must form a cardinal camera rotation"
	var stack: GridStackDefinition = _grid.stack_at(cell)
	if powers & ~7 or direction < 0 or direction > 3 or stack == null or stack.square_count == 0:
		return "Terrain run start requires a bounded terrain cell, direction 0..3 and supported fixture powers"
	var index: int = stack.first_square_index + stack.square_count - 1
	var state := RunSnapshot.new()
	state.cell = cell
	state.direction = direction
	state.square_index = index
	state.powerup_flags = powers
	if initial != null:
		if initial.quick_jump_timer < 0 or initial.quick_jump_timer > 65535 or initial.auto_hop_timer < 0 or initial.auto_hop_timer > 65535 or initial.super_tongue_timer < 0 or initial.super_tongue_timer > 65535:
			return "Modifier timers must fit source unsigned16 values"
		state.quick_jump_timer = initial.quick_jump_timer
		state.auto_hop_timer = initial.auto_hop_timer
		state.super_tongue_timer = initial.super_tongue_timer
	state.position_16 = GridQueries.square_centre(_grid, _grid.squares[index]) * 65536
	state.world_position = Vector3i(state.position_16.x >> 16, state.position_16.y >> 16, state.position_16.z >> 16)
	state.fixture_lives = initial.lives if initial != null else 3
	state.old_y = state.position_16.y >> 16
	state.target_y = state.old_y
	state.old_position_16 = state.position_16
	state.matrix12[9] = state.world_position.x
	state.matrix12[10] = state.world_position.y
	state.matrix12[11] = state.world_position.z
	state.matrix12 = TerrainMatrix.update(state.matrix12, state.flags, state.direction, _grid.squares[index])
	state.initial_cell = cell
	state.start_mode = initial.start_mode if initial != null else 0
	if state.start_mode < 0 or state.start_mode > 2:
		return "Start mode must select component, fast reset or single-start bounce"
	state.start_target_16 = state.position_16.y
	if state.start_mode == 2:
		state.position_16.y -= 6400 << 12
		state.mode = 265
		_update_world(state)
		state.old_position_16 = state.position_16
		state.old_y = state.world_position.y
		state.target_y = state.old_y
	elif state.start_mode == 1:
		state.mode = 3
	if _exploration_guard != null:
		var guard_error: String = _exploration_guard.check_world(state.world_position)
		if guard_error.is_empty():
			guard_error = _exploration_guard.check_cell(state.cell)
		if not guard_error.is_empty():
			return guard_error
	_sync_facts(state)
	var random: SourceRandom = SourceRandom.create(initial.seed if initial != null else 1)
	var camera: GameplayCamera = null
	var animation: FrogAnimationController = null
	if _camera_definition != null:
		camera = GameplayCamera.create(_camera_definition, state.world_position, initial.camera_startup if initial != null else false)
		if not camera.error.is_empty():
			return camera.error
		state.camera = camera.snapshot()
		controller_directions = state.camera.controller_directions.duplicate()
	if not _action_lengths.is_empty():
		animation = FrogAnimationController.create(_action_lengths, FrogAnimationContext.create(random, _theme_name))
		if not animation.error.is_empty():
			return animation.error
		state.animation = animation.state.copy()
	if _exploration_guard != null:
		var animated_issue: String = _exploration_guard.check_frog(state)
		if not animated_issue.is_empty():
			return animated_issue
	state.rng_state = random.state
	state.start_timer = initial.start_timer if initial != null else 0
	if state.start_timer < 0:
		return "Start timer must be nonnegative"
	var candidate_entities: EntityRun = _entities.copy() if _entities != null else null
	if candidate_entities != null:
		var entity_error: String = candidate_entities.reset()
		if not entity_error.is_empty():
			return entity_error
		state.entities = candidate_entities.snapshot()
		state.entity_environment = _entity_collision.environment.copy() if _entity_collision.environment != null else null
	_state = state
	_controller_directions = controller_directions
	_camera = camera
	_random = random
	_animation = animation
	_entities = candidate_entities
	return ""

## Returns detached state; changing it has no effect on the run.
func snapshot() -> RunSnapshot:
	return _state.copy() if _state != null else null

## Commits one atomic tick. Optional phase capture affects diagnostics only; final state is always detached.
func step(command: TickCommand, capture_phases: bool = true) -> TickResult:
	var result := TickResult.new()
	_capture_phases = capture_phases
	if _state == null or command == null:
		result.error = "Terrain run and tick command must be initialized"
		return result
	if _state.completed:
		result.error = "Terrain run completed; reset before supplying another tick"
		return result
	result.tick_index = command.tick_index
	if command.tick_index != _state.tick_index:
		result.error = "Tick index must equal next tick %d" % _state.tick_index
		return result
	if command.pressed_mask < 0 or command.held_mask < 0 or (command.pressed_mask | command.held_mask) & ~127:
		result.error = "Terrain commands support directional, super-hop and camera-turn masks"
		return result
	if _camera == null and (command.pressed_mask | command.held_mask) & 96:
		result.error = "Camera-turn commands require an integrated camera definition"
		return result
	if command.start_timer_context < -1 or command.start_timer_context > 2147483647 or (command.start_sequence_complete and _state.mode not in [265, 266]):
		result.error = "Start context requires a nonnegative timer and completion only during single-start callbacks"
		return result
	_candidate_camera = _camera.copy() if _camera != null else null
	_candidate_random = _random.copy()
	_candidate_random.begin_tick()
	_candidate_animation = _animation.copy(_animation.context.copy(_candidate_random)) if _animation != null else null
	_candidate_entities = _entities.advanced_copy(command.tick_index, _state.current_entity_index) if _entities != null else null
	var next: RunSnapshot = _state.copy(false)
	if _candidate_entities != null:
		result.error = _candidate_entities.error
		if not result.error.is_empty():
			return _failed_tick(result, result.error)
	# Both aggregate views own the same unpublished entity candidate. Public
	# snapshots and phase observations still detach at their existing boundaries.
	next.entities = _candidate_entities._state if _candidate_entities != null else null
	var entity_issue: String = _update_entity_scripts(next, result.events)
	if not entity_issue.is_empty():
		return _failed_tick(result, entity_issue)
	next.entity_hit_indices = PackedInt32Array()
	next.entity_carry_indices = PackedInt32Array()
	if next.current_entity_index >= 0 and (_platform_pose(next) == null or _platform_definition(next) == null):
		return _failed_tick(result, "Current platform identity or matrix is invalid")
	if command.start_timer_context >= 0:
		next.start_timer = command.start_timer_context
	if command.start_sequence_complete:
		next.mode = 3
	_callback_error = ""
	var control_error: String = _control(next, command, result.events)
	if not control_error.is_empty():
		return _failed_tick(result, control_error)
	_sync_systems(next)
	if capture_phases:
		result.control_snapshot = next.copy()
	next.old_position_16 = next.position_16
	_move(next, result.events)
	if not _callback_error.is_empty():
		return _failed_tick(result, _callback_error)
	if next.flags & 4 and next.current_entity_index >= 0 and next.mode != 2:
		_mark_carry(next, next.current_entity_index)
	# MoveFrog updates the camera zone here, before modifiers and collision.
	if _exploration_guard != null:
		var guard_error: String = _exploration_guard.check_cell(next.cell)
		if guard_error.is_empty():
			guard_error = _exploration_guard.check_world(next.world_position)
		if not guard_error.is_empty():
			return _failed_tick(result, guard_error)
	_sync_systems(next)
	if capture_phases:
		result.move_snapshot = next.copy()
	TerrainModifiers.update(next)
	var continue_entities: bool = true
	if _collision_enabled:
		continue_entities = _collision(next, result.events)
	if not _callback_error.is_empty():
		return _failed_tick(result, _callback_error)
	if continue_entities and _candidate_entities != null:
		if _exploration_guard != null:
			var animated_issue: String = _exploration_guard.check_frog(next)
			if not animated_issue.is_empty():
				return _failed_tick(result, animated_issue)
		var entity_error: String = _contact_entities(next, result)
		if not entity_error.is_empty():
			return _failed_tick(result, entity_error)
	if not _callback_error.is_empty():
		return _failed_tick(result, _callback_error)
	_sync_systems(next)
	if capture_phases:
		result.collision_snapshot = next.copy()
	if _candidate_camera != null:
		var camera_input := GameplayCameraTick.new()
		camera_input.frog_world = next.world_position
		camera_input.frog_mode = next.mode
		camera_input.remaining_ticks = next.remaining_ticks
		camera_input.old_y = next.old_y
		camera_input.target_y = next.target_y
		camera_input.freefall = next.flags & 128 != 0
		camera_input.superjump = next.flags & 32 != 0
		camera_input.start_timer = next.start_timer
		camera_input.on_entity = next.current_entity_index >= 0
		if camera_input.on_entity:
			camera_input.entity_matrix12 = _platform_pose(next).matrix12.duplicate()
		result.error = _candidate_camera.step(camera_input)
		if not result.error.is_empty():
			return _failed_tick(result, result.error)
		next.camera = _candidate_camera.snapshot()
		next.entity_angle = (next.entity_angle + next.camera.entity_angle_delta) & 3
	if capture_phases:
		result.camera_snapshot = next.copy()
	if _candidate_animation != null:
		next.no_input_timer = _candidate_animation.update_scripts(next.no_input_timer)
		_sync_systems(next)
		next.animation_condition_counter = _candidate_animation.context.if_counter
	if capture_phases:
		result.scripts_snapshot = next.copy()
	if _candidate_animation != null:
		_candidate_animation.advance_pose()
		if not _candidate_animation.error.is_empty():
			result.error = _candidate_animation.error
			return _failed_tick(result, result.error)
		next.animation = _candidate_animation.state.copy()
		next.animation_condition_counter = _candidate_animation.context.if_counter
	# gamesys.C creates/renews visible live entities only after camera and animation.
	if _candidate_entities != null:
		_candidate_entities.advance_animations()
		next.entities = _candidate_entities._state
	# A failure here discards the entire candidate, including earlier frog requests.
	if _candidate_entities != null and _entity_collision.lifecycle != null:
		var visibility_error: String = _candidate_entities.apply_visibility(next.camera)
		if not visibility_error.is_empty():
			return _failed_tick(result, visibility_error)
		next.entities = _candidate_entities._state
	next.rng_state = _candidate_random.state
	next.rng_draw_count = _candidate_random.draw_count
	if _exploration_guard != null:
		var guard_error: String = _exploration_guard.check_world(next.world_position)
		if guard_error.is_empty():
			guard_error = _exploration_guard.check_frog(next)
		if not guard_error.is_empty():
			return _failed_tick(result, guard_error)
	result.rng_consumers.assign(_candidate_random.consumers)
	next.tick_index += 1
	_state = next
	_camera = _candidate_camera
	_random = _candidate_random
	_animation = _candidate_animation
	_entities = _candidate_entities
	if _camera != null:
		_controller_directions = next.camera.controller_directions.duplicate()
	result.final_snapshot = next.copy()
	return result

func _update_entity_scripts(state: RunSnapshot, events: Array[String]) -> String:
	if _candidate_entities == null or not _has_entity_updates:
		return ""
	for slot: int in range(_entity_collision.entities.size() - 1, -1, -1):
		var previous_flags: int = state.entities.entities[slot].live_flags
		var was_alive: bool = state.mode != 2 and not state.flags & 8
		var issue: String = _visit_entity(slot, previous_flags, state, events)
		if not issue.is_empty():
			return issue
		var killed: bool = was_alive and bool(state.flags & 8)
		if killed:
			events.append("entity:%d:death_pgen" % _entity_collision.entities[slot].entity_index)
		_candidate_entities.finish_update(slot, previous_flags, _candidate_random, state.sound_requests, state.entity_environment, killed, _capture_phases)
		state.entities.entities[slot] = _candidate_entities._state.entities[slot]
	return ""

func _visit_entity(slot: int, previous_flags: int, state: RunSnapshot, events: Array[String]) -> String:
	var definition: EntityDefinition = _entity_collision.entities[slot]
	if definition.background_admitted:
		var frog_position := Vector3i(state.matrix12[9], state.matrix12[10], state.matrix12[11])
		var background: EntityBackgroundResult = _candidate_entities.update_background(definition.entity_index, state.entity_environment, _candidate_random, frog_position, _state.entity_hit_indices.has(definition.entity_index))
		if not background.error.is_empty():
			return background.error
		state.entity_environment = background.environment
		_candidate_random.state = background.random.state
		_candidate_random.draw_count = background.random.draw_count
		_candidate_random.consumers.assign(background.random.consumers)
		state.entities.entities[slot] = _candidate_entities._state.entities[slot]
	if definition.script_definition == null:
		return ""
	var context := EntityUpdateContext.new()
	context.entity_index = definition.entity_index
	context.form_id = definition.form_id
	context.base_matrix = state.entities.entities[slot].matrix12.duplicate()
	context.frog_position = Vector3i(state.matrix12[9], state.matrix12[10], state.matrix12[11])
	context.previous_hit = bool(previous_flags & 64)
	context.previous_carry = bool(previous_flags & 4)
	context.has_path = definition.path_definition != null
	context.no_display = bool(state.entities.entities[slot].entity_flags & EntityDefinition.NO_DISPLAY)
	context.fade_bounds = PackedInt32Array([_collision_bounds.position.x, _collision_bounds.end.x, _collision_bounds.position.y, _collision_bounds.end.y])
	var update: EntityUpdateResult = _candidate_entities._update_script(slot, context, _candidate_random, true)
	if not update.error.is_empty():
		return "Entity %d script: %s" % [definition.entity_index, update.error]
	# Keep the shared candidate object: the frog animation context owns this
	# same stream and must observe every preceding entity draw.
	if update.random != _candidate_random:
		_candidate_random.state = update.random.state
		_candidate_random.draw_count = update.random.draw_count
		_candidate_random.consumers.assign(update.random.consumers)
	for request: String in update.requests:
		events.append("entity:%d:%s" % [definition.entity_index, request])
		if request.begins_with("sound:"):
			state.sound_requests += 1
	if update.drown:
		_kill(state, FrogAnimationCatalog.DROWN, false, events)
	state.entities.entities[slot] = _candidate_entities._state.entities[slot]
	return ""

func _copy_grid(source: GridDefinition) -> String:
	if source.dimensions.x <= 0 or source.dimensions.y <= 0 or source.dimensions.x > 65535 or source.dimensions.y > 65535:
		return "Terrain run requires positive unsigned16 grid dimensions"
	if source.stacks.size() != source.dimensions.x * source.dimensions.y:
		return "Terrain run requires validated 256-unit grid bounds"
	var grid := GridDefinition.new()
	grid.dimensions = source.dimensions
	grid.base = source.base
	var expected_index: int = 0
	for original: GridStackDefinition in source.stacks:
		if original == null or original.square_count < 0 or original.square_count > 255 or original.first_square_index != expected_index or original.first_square_index > 65535 or original.first_square_index + original.square_count > source.squares.size() or original.cliff_height_byte < 0 or original.cliff_height_byte > 255:
			return "Terrain run requires bounded authored layer ranges"
		expected_index += original.square_count
		var stack := GridStackDefinition.new()
		stack.first_square_index = original.first_square_index
		stack.square_count = original.square_count
		stack.cliff_height_byte = original.cliff_height_byte
		stack.source_offset = original.source_offset
		grid.stacks.append(stack)
	if expected_index != source.squares.size():
		return "Terrain run layer ranges must cover every authored square"
	for original: GridSquareDefinition in source.squares:
		if original == null or original.vertices.size() != 4:
			return "Terrain run requires four calculation corners per layer"
		if original.flags < 0 or original.flags > 4294967295:
			return "Terrain flags must fit source unsigned32 values"
		for vertex: Vector3i in original.vertices:
			if vertex.x < -32768 or vertex.x > 32767 or vertex.y < -32768 or vertex.y > 32767 or vertex.z < -32768 or vertex.z > 32767:
				return "Terrain run requires signed16 terrain corners"
		var square := GridSquareDefinition.new()
		square.flags = original.flags
		square.vertices.assign(original.vertices)
		square.source_offset = original.source_offset
		square.polygon_index = original.polygon_index
		square.polygon_source_offset = original.polygon_source_offset
		grid.squares.append(square)
	_grid = grid
	return ""

func _first_direction(mask: int) -> int:
	for direction: int in 4:
		if mask & (1 << direction):
			return direction
	return NO_INPUT

func _control(state: RunSnapshot, command: TickCommand, events: Array[String]) -> String:
	if state.flags & 8:
		state.flags &= ~8
		if state.mode != MODE_JUMPING or not state.flags & 64:
			state.remaining_ticks = 0
		state.mode = 2
		state.death_count = 70
		if _candidate_camera != null:
			_candidate_camera.request_death()
		events.append("camera_death")
	if state.start_timer != 0 or not state.flags & 2048:
		return ""
	if state.mode == 262:
		var callback: TerrainCallbackResult = TerrainFreeformSlip.control(state, command, _controller_directions, _theme)
		if callback.forward_steering:
			if state.square_index < 0:
				return "Freeform forward steering requires a current authored square"
			TerrainFreeformSlip.forward_control(state, _grid.squares[state.square_index])
		_apply_requests(state, callback, events)
		return _callback_error
	if state.mode not in [0, 1, 5, 258, 267]:
		return ""
	if state.mode == MODE_JUMPING:
		var pressed: int = _first_direction(command.pressed_mask)
		if pressed == NO_INPUT and command.pressed_mask & TickCommand.SUPER_HOP:
			pressed = 8
		if pressed != NO_INPUT and state.buffered_keys < 1:
			state.buffered_keys = 1
			state.buffered_direction = (pressed - _controller_directions[0]) & 3 if pressed != 8 else 8
		return ""
	var input: int = NO_INPUT
	state.no_input_timer += 1
	var buffered_mask: int = 16 if state.buffered_direction == 8 else 1 << state.buffered_direction
	if state.buffered_keys > 0 and command.held_mask & buffered_mask:
		input = state.buffered_direction
		state.buffered_input_count += 1
	elif state.buffered_input_count > 0:
		state.buffered_input_count -= 1
	state.buffered_keys = 0
	if input == NO_INPUT:
		input = _first_direction(command.pressed_mask)
		if input == NO_INPUT and command.pressed_mask & TickCommand.SUPER_HOP:
			input = 8 | NO_INPUT
		if input & NO_INPUT:
			if command.pressed_mask & TickCommand.CAMERA_CLOCKWISE:
				input |= 32
			if command.pressed_mask & TickCommand.CAMERA_ANTICLOCKWISE:
				input |= 64
		if state.powerup_flags & 4:
			var held_direction: int = _first_direction(command.held_mask)
			if held_direction != NO_INPUT:
				input = held_direction
		if input & 96:
			var failure: String = _candidate_camera.request_turn(1 if input & 32 else -1)
			if not failure.is_empty():
				return failure
			state.mode = 3
			events.append("camera_clockwise" if input & 32 else "camera_anticlockwise")
			return ""
	var is_super: bool = input & 8 != 0
	if is_super:
		input = (state.direction - (state.entity_angle if state.flags & 4 else _controller_directions[0])) & 3
	if input != NO_INPUT:
		state.no_input_timer = 0
		var failure: String = _jump(state, input, events, is_super)
		if not failure.is_empty():
			return failure
	state.current_input = input
	return ""

func _jump(state: RunSnapshot, direction: int, events: Array[String], is_super: bool = false, forced: bool = false, distance: int = 1, duration: int = 0) -> String:
	if state.flags & 4:
		return _jump_platform(state, direction, events, is_super, distance)
	direction = _controller_directions[direction]
	var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var target_cell: Vector2i = state.cell + offsets[direction] * distance
	for attempt: int in range(distance):
		if _grid.stack_at(target_cell) != null:
			break
		target_cell += offsets[direction]
	var stack: GridStackDefinition = _grid.stack_at(target_cell)
	var wall: bool = false
	if stack != null:
		if direction in [0, 1] and state.square_index >= 0:
			wall = _grid.squares[state.square_index].flags & (16384 if direction == 0 else 32768) != 0
		elif direction in [2, 3]:
			for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
				wall = wall or _grid.squares[candidate].flags & (16384 if direction == 2 else 32768) != 0
		if not wall:
			for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
				if _grid.squares[candidate].flags & 1 and _grid.squares[candidate].flags & 2048 and state.world_position.y >= -(stack.cliff_height_byte << 6):
					wall = true
					break
	if wall:
		state.user_target_cell = target_cell
		state.direction = direction
		_apply_requests(state, TerrainWallBounce.setup(state, _grid), events)
		state.mode = 261
		return _callback_error
	var current_height: int = state.world_position.y
	var allowed_up: int = 448 if is_super else 200
	if not is_super and state.square_index >= 0 and _grid.squares[state.square_index].flags & 512:
		allowed_up = 255
	var index: int = -1
	var height: int = current_height
	var smooth: bool = false
	if stack != null:
		for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
			var square: GridSquareDefinition = _grid.squares[candidate]
			var candidate_height: int = GridQueries.square_height(square)
			if square.flags & 1 and ((current_height >= candidate_height and current_height - candidate_height <= allowed_up) or (candidate_height >= current_height and candidate_height - current_height <= 256)):
				index = candidate
				height = candidate_height
				smooth = true
				break
		if index < 0:
			for candidate: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
				if _grid.squares[candidate].flags & 1 and GridQueries.square_height(_grid.squares[candidate]) >= current_height:
					index = candidate
					height = GridQueries.square_height(_grid.squares[candidate])
					break
	if stack != null and stack.square_count > 0 and index < 0 and forced:
		# Source backward search leaves a pointer before the selected stack.
		index = stack.first_square_index - 1
		if index < 0 or index >= _grid.squares.size():
			return "Source forced-hop leftover layer pointer lies outside authored global storage"
	if stack != null and stack.square_count > 0 and index < 0:
		state.direction = direction
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.OUCH, state)
		events.append("ouch")
		return ""
	var roll_request: bool = state.direction == direction and state.buffered_input_count > 3
	if roll_request:
		state.buffered_input_count = 0
	state.direction = direction
	state.cell = target_cell
	state.square_index = index
	if smooth:
		state.flags |= 64
	else:
		state.flags &= ~64
	if is_super:
		state.flags |= 32
	state.mode = MODE_JUMPING
	state.remaining_ticks = 15 if is_super else 3 if state.powerup_flags & 2 else 6
	if duration > 0:
		state.remaining_ticks = duration
	state.old_y = state.target_y
	state.target_y = height if smooth else current_height
	state.target_16 = Vector3i((target_cell.x * 256 + _grid.base.x + 128) * 65536, state.target_16.y, (target_cell.y * 256 + _grid.base.y + 128) * 65536)
	var delta: Vector3i = state.target_16 - state.position_16
	@warning_ignore("integer_division")
	state.velocity_16.x = delta.x / state.remaining_ticks
	@warning_ignore("integer_division")
	state.velocity_16.z = delta.z / state.remaining_ticks
	@warning_ignore("integer_division")
	state.velocity_16.y = ((state.target_y - current_height) * 65536) / (state.remaining_ticks + 1) - ((GRAVITY_16 * (state.remaining_ticks + 1)) >> 1)
	state.animation_requests += 1
	_request_animation(FrogAnimationCatalog.SUPERJUMP if is_super else FrogAnimationCatalog.SUPERHOP if state.powerup_flags & 2 else FrogAnimationCatalog.AUTOHOP if state.powerup_flags & 4 else FrogAnimationCatalog.ROLL if roll_request else FrogAnimationCatalog.HOP, state)
	state.sound_requests += 1
	if is_super or state.powerup_flags & 2 or not state.powerup_flags & 4:
		state.score_requests += 1
	events.append("super_hop" if is_super else "quick_hop" if state.powerup_flags & 2 else "auto_hop" if state.powerup_flags & 4 else "roll" if roll_request else "hop")
	events.append("hop_sound")
	if is_super or state.powerup_flags & 2 or not state.powerup_flags & 4:
		events.append("score_10_request" if is_super else "score_50_request" if roll_request or state.powerup_flags & 2 else "score_5_request")
	return ""

func _move(state: RunSnapshot, events: Array[String]) -> void:
	if state.current_entity_index >= 0 and state.mode in [0, 3, 5] and state.flags & 4:
		var was_centring: bool = state.mode == 5
		_apply_requests(state, TerrainPlatform.carry(state, _platform_pose(state)), events)
		_update_world(state)
		if not was_centring:
			state.target_y = state.world_position.y
		if was_centring:
			_update_matrix(state)
			return
	if state.mode == 262:
		_apply_callback(state, TerrainFreeformSlip.move(state, _grid), events)
		return
	if state.mode == 261:
		_apply_callback(state, TerrainWallBounce.move(state, _grid), events)
		return
	if state.mode in [265, 266]:
		_apply_callback(state, TerrainStartup.move(state), events)
		return
	if state.mode in [258, 267]:
		_apply_callback(state, TerrainGridSlip.move(state, _grid), events)
		return
	if state.mode == 268:
		var callback: TerrainCallbackResult = TerrainGridSlip.move(state, _grid, false)
		callback.kill_looping_sound = false
		_apply_callback(state, callback, events)
		return
	if state.mode == 269:
		_apply_callback(state, TerrainCliffRoll.move(state, _grid), events)
		return
	if state.mode == 6:
		state.remaining_ticks -= 1
		if state.remaining_ticks == 0:
			state.mode = 0
			state.animation_requests += 1
			_request_animation(FrogAnimationCatalog.PANT, state)
			events.append("pant")
		_update_matrix(state)
		return
	if state.mode == 2:
		var continuing_jump: bool = state.remaining_ticks != 0
		if state.current_entity_index >= 0 and state.flags & 4:
			# FrogModeMovementDying retains the attachment and carries before
			# applying death velocity, without reasserting live CARRY flags.
			state.position_16 = PlatformMath.world(_platform_pose(state).matrix12, state.entity_offset_16) * 65536
		state.death_count -= 1
		if state.death_count == 0:
			state.flags &= ~2048
			state.game_mode_request = 3
			state.completed = true
			events.append("death_complete")
			events.append("single_frog_died_request")
		if state.remaining_ticks != 0:
			_move_jumping(state, events, false)
			state.mode = 2
		else:
			state.position_16 += state.velocity_16
			if _map_index == 2:
				# Source signed32 multiplication wraps before the arithmetic shift.
				var product: Vector3i = state.velocity_16 * 14
				state.velocity_16 = Vector3i(product.x >> 4, product.y >> 4, product.z >> 4)
		_update_world(state)
		if not continuing_jump:
			_update_matrix(state)
		return
	if state.mode == MODE_STATIONARY or state.mode == 3:
		if _candidate_camera == null or _candidate_camera.snapshot().turn_wait_complete():
			state.mode = MODE_STATIONARY
			state.buffered_keys = 0
		_update_matrix(state)
		return
	var landing: bool = state.remaining_ticks == 1 and state.flags & 64 != 0
	_move_jumping(state, events)
	_update_world(state)
	if not landing:
		_update_matrix(state)

func _move_jumping(state: RunSnapshot, events: Array[String], react_on_land: bool = true) -> void:
	if state.current_entity_index >= 0:
		_move_platform_jumping(state, events, react_on_land)
		return
	state.remaining_ticks -= 1
	if state.remaining_ticks == 0:
		if state.flags & 64:
			state.position_16.x = state.target_16.x
			state.position_16.z = state.target_16.z
			_land(state, events)
			_update_world(state)
			if react_on_land:
				_update_matrix(state)
			if react_on_land:
				_react(state, _grid.squares[state.square_index].flags & 65535, events)
		else:
			state.position_16.x = state.target_16.x
			state.position_16.z = state.target_16.z
			if state.square_index < 0:
				var stack: GridStackDefinition = _grid.stack_at(state.cell)
				if stack == null:
					_callback_error = "Source final hop stack lookup lies outside authored storage"
					return
				if stack != null:
					for index: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
						if _grid.squares[index].flags & 1 and GridQueries.square_height(_grid.squares[index]) >= (state.position_16.y >> 16):
							state.square_index = index
							break
			state.flags &= ~(32 | 64)
			state.flags |= 128 | 8192
			state.remaining_ticks = 0x7FFFFFF
			state.velocity_16.x = 0
			state.velocity_16.z = 0
	else:
		state.velocity_16.y += GRAVITY_16
		if state.flags & (128 | 8192) == (128 | 8192) and state.world_position.y - state.old_y >= 0:
			state.animation_requests += 1
			_request_animation(FrogAnimationCatalog.FREEFALL if _map_index >= 42 and _map_index <= 47 else FrogAnimationCatalog.FALLING, state)
			state.flags &= ~8192
			events.append("falling")
		state.position_16 += state.velocity_16

func _update_world(state: RunSnapshot) -> void:
	state.world_position = Vector3i(state.position_16.x >> 16, state.position_16.y >> 16, state.position_16.z >> 16)
	state.cell = GridQueries.world_to_cell(_grid, state.world_position.x, state.world_position.z)
	state.matrix12[9] = state.world_position.x
	state.matrix12[10] = state.world_position.y
	state.matrix12[11] = state.world_position.z

func _update_matrix(state: RunSnapshot) -> void:
	if state.flags & 4 and state.current_entity_index >= 0:
		TerrainPlatform.update_matrix(state, _platform_pose(state))
		return
	if state.current_entity_index >= 0 and state.flags & (16 | 64) == 16:
		var facing: Vector3i = PlatformMath.apply(_platform_pose(state).matrix12, TerrainPlatform.DIRECTIONS[state.direction])
		state.matrix12 = TerrainMatrix.update(state.matrix12, state.flags, state.direction, null, facing)
		return
	state.matrix12 = TerrainMatrix.update(state.matrix12, state.flags, state.direction, _grid.squares[state.square_index] if state.square_index >= 0 else null)

func _land(state: RunSnapshot, events: Array[String]) -> void:
	var flags: int = _grid.squares[state.square_index].flags
	if not flags & (4 | 8 | 4096):
		state.position_16 = GridQueries.square_centre(_grid, _grid.squares[state.square_index]) * 65536
	state.target_y = state.position_16.y >> 16
	var distance: int = state.target_y - state.old_y
	_react_fall(state, distance, flags, events)
	state.current_entity_index = -1
	state.forbidden_entity_index = -1
	state.velocity_16 = Vector3i.ZERO
	state.old_y = state.target_y
	state.flags &= ~(4 | 2 | 16 | 32 | 64 | 128 | 256 | 65536 | 16384)
	if _entity_collision != null and _entity_collision.platforms_enabled and _candidate_camera != null and _candidate_camera.snapshot().twist_counter == 0:
		_candidate_camera.align_y()
	if _entity_collision != null and _entity_collision.platforms_enabled:
		state.direction = PlatformMath.quadrant(Vector3i(state.matrix12[2], state.matrix12[5], state.matrix12[8]))

func _react_fall(state: RunSnapshot, distance: int, flags: int, events: Array[String]) -> void:
	state.mode = 0
	if flags & 256 or distance <= 512:
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.PANT, state)
		events.append("pant")
	elif distance <= 1024:
		state.mode = 6
		state.remaining_ticks = 45
		state.sound_requests += 1
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.CRASH, state)
		if _candidate_camera != null:
			_candidate_camera.request_shake(128, 45, 20480, _candidate_random.next_value("camera_stun_shake_x"), _candidate_random.next_value("camera_stun_shake_y"))
		events.append("stun_sound")
		events.append("crash")
		events.append("camera_stun_shake")
	else:
		if flags & 4:
			if _theme == 3:
				state.sound_requests += 1
			_kill(state, 12 if _theme == 3 else 8, _theme != 3, events)
		elif flags & 4096:
			_kill(state, 23, false, events)
		elif flags & 8:
			_kill(state, 8, true, events)
			state.sound_requests += 1
		else:
			_kill(state, 2, false, events)

func _react(state: RunSnapshot, flags: int, events: Array[String]) -> void:
	flags &= 65535
	if flags & ~0xDFFF:
		events.append("unknown_terrain_flags_ignored")
	if not flags & 1:
		return
	if flags & 2048:
		if state.flags & 2048:
			_apply_requests(state, TerrainCliffRoll.setup(state, _grid), events)
			state.mode = 269
		return
	if flags & 2:
		return
	if flags & 4:
		_kill(state, 12 if _theme == 3 else 8, _theme != 3, events)
		state.sound_requests += 1
	elif flags & 4096:
		_kill(state, 23, false, events)
		state.sound_requests += 1
	elif flags & 8:
		_kill(state, 8, true, events)
		state.sound_requests += 1
	elif flags & (16 | 1024):
		var mode: int = 258 if flags & 16 else 267
		var callback: TerrainCallbackResult = TerrainGridSlip.setup(state, _grid, mode == 267, _theme)
		_apply_requests(state, callback, events)
		state.mode = mode
	elif flags & 128:
		_apply_requests(state, TerrainFreeformSlip.setup(state), events)
		state.mode = 262
	elif flags & 32:
		_callback_error = _jump(state, (state.direction - _controller_directions[0]) & 3, events, false, true, 2, 15)
		state.mode = 268

func _kill(state: RunSnapshot, animation: int, down_velocity: bool, events: Array[String]) -> void:
	if state.mode == 2 or state.flags & 8:
		return
	state.flags &= ~2048
	if state.fixture_lives > 0:
		state.life_decrement_requested = true
	if state.fixture_lives <= 1:
		state.flags &= ~1
	state.flags |= 8
	state.animation_requests += 1
	_request_animation(animation, state)
	if _candidate_camera != null:
		_candidate_camera.request_fixed()
	state.death_equate = animation
	if down_velocity:
		state.velocity_16 = Vector3i(0, 65536, 0)
	elif state.mode != 1 or not state.flags & 64:
		state.velocity_16 = Vector3i.ZERO
	if _theme == 10 and animation in [FrogAnimationCatalog.DROWN, FrogAnimationCatalog.FLOP]:
		state.death_fire_requested = true
		state.death_scale_colour = Vector3i(24, 0, 0)
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.DROWN, state)
		events.append("death_fire_particle_request")
	events.append("death_animation_%d" % animation)
	events.append("camera_fixed")

func _collision(state: RunSnapshot, events: Array[String]) -> bool:
	if state.mode == 3 and (_candidate_camera == null or _candidate_camera.snapshot().twist_counter == 0):
		return false
	if state.mode in [2, 4, 264] or state.flags & 8:
		return false
	var p: Vector3i = state.world_position
	if p.x < _collision_bounds.position.x or p.x > _collision_bounds.end.x or p.z < _collision_bounds.position.y or p.z > _collision_bounds.end.y:
		_kill(state, 2, false, events)
		return false
	if state.flags & 128 and state.square_index >= 0 and p.y > GridQueries.square_height(_grid.squares[state.square_index]):
		_land(state, events)
		_update_world(state)
		_react(state, _grid.squares[state.square_index].flags & 65535, events)
		return false
	if p.y > _death_height:
		state.world_position.y = _death_height
		state.velocity_16 = Vector3i.ZERO
		_kill(state, 8, true, events)
		state.sound_requests += 1
		return false
	return true

func _contact_entities(state: RunSnapshot, result: TickResult) -> String:
	if state.entities == null or state.entities.entities.size() != _entity_collision.entities.size():
		return "Entity collision snapshot does not match validated definitions"
	for index: int in _entity_collision.entities.size():
		var expected: EntityDefinition = _entity_collision.entities[index]
		var actual: EntitySnapshot = state.entities.entities[index]
		if actual == null or actual.entity_index != expected.entity_index or actual.unique_id != expected.unique_id:
			return "Entity collision snapshot identity does not match validated definitions"
	var ordered: PackedInt32Array = EntityContactOrder._indices_validated(_entity_collision, state.entities, state.world_position)
	var forbidden: int = state.forbidden_entity_index
	for entity_id: int in ordered:
		if _exploration_guard != null:
			var guard_error: String = _exploration_guard.check_world(state.world_position)
			if guard_error.is_empty():
				guard_error = _exploration_guard.check_frog(state)
			if not guard_error.is_empty():
				return guard_error
		if entity_id == state.current_entity_index or entity_id == forbidden:
			continue
		var index: int = -1
		for candidate: int in _entity_collision.entities.size():
			if _entity_collision.entities[candidate].entity_index == entity_id:
				index = candidate
				break
		if index < 0:
			return "Entity contact order produced an unknown authored index"
		if state.entities.lifecycle_enabled and not state.entities.entities[index].live:
			return "Entity contact order produced a dormant identity"
		var contact: FormContactResult = FormContactQuery.query(_entity_collision.contacts[index], state.entities.entities[index], state.world_position)
		var reaction: FormReactionResult = FormReaction.evaluate(_entity_collision.contacts[index], contact, _entity_collision.platforms_enabled)
		if reaction.status == FormReactionResult.INVALID:
			return reaction.reason
		result.entity_contacts.append(reaction)
		var issue: String = _apply_form_reaction(state, _entity_collision.contacts[index], state.entities.entities[index], reaction, result)
		if not issue.is_empty():
			return issue
	if state.current_entity_index >= 0 and state.flags & (2 | 16) == (2 | 16) and state.remaining_ticks == 1:
		if _exploration_guard != null:
			var guard_error: String = _exploration_guard.check_world(state.world_position)
			if not guard_error.is_empty():
				return guard_error
		var pose: EntitySnapshot = _platform_pose(state)
		var definition: FormContactDefinition = _platform_definition(state)
		var delta: Vector3i = state.world_position - Vector3i(pose.matrix12[9], pose.matrix12[10], pose.matrix12[11])
		delta = Vector3i(PlatformMath.s16(delta.x), PlatformMath.s16(delta.y), PlatformMath.s16(delta.z))
		var local: Vector3i = PlatformMath.apply(PlatformMath.transpose(pose.matrix12), delta)
		var cell := Vector2i((local.x - definition.offsets.x) >> 8, (local.z - definition.offsets.y) >> 8)
		if cell.x < 0 or cell.y < 0 or cell.x >= definition.dimensions.x or cell.y >= definition.dimensions.y:
			return "Source same-platform re-reaction cell lies outside authored storage"
		var contact := FormContactResult.new()
		contact.status = FormContactResult.CONTACT
		contact.entity_index = definition.entity_index
		contact.unique_id = definition.unique_id
		contact.form_grid_id = definition.form_grid_id
		contact.form_id = definition.form_id
		contact.form_name = definition.form_name
		contact.local_position = local
		contact.cell = cell
		contact.height = definition.height
		contact.cell_flags = definition.grid_flags[cell.y * definition.dimensions.x + cell.x]
		var reaction: FormReactionResult = FormReaction.evaluate(definition, contact, true)
		if reaction.status in [FormReactionResult.INVALID, FormReactionResult.UNSUPPORTED]:
			return "Same-platform re-reaction requires a supported cell: " + reaction.reason
		result.entity_contacts.append(reaction)
		var issue: String = _apply_form_reaction(state, definition, pose, reaction, result)
		if not issue.is_empty():
			return issue
		# COLLIDE.C reasserts HIT outside ReactFrogWithForm in this special path,
		# including a geometric/vertical rejection by the FORM reaction itself.
		reaction.hit = true
		if not state.entity_hit_indices.has(pose.entity_index):
			state.entity_hit_indices.append(pose.entity_index)
	return ""

func _apply_form_reaction(state: RunSnapshot, definition: FormContactDefinition, pose: EntitySnapshot, reaction: FormReactionResult, result: TickResult) -> String:
	if reaction.status == FormReactionResult.SAFE:
		var issue: String = _mount_platform(state, definition, pose, reaction, result.events)
		if not issue.is_empty():
			return issue
	if reaction.hit and not state.entity_hit_indices.has(pose.entity_index):
		state.entity_hit_indices.append(pose.entity_index)
	if reaction.status == FormReactionResult.POP and state.death_entity_index < 0 and state.mode != 2 and not state.flags & 8:
		_kill(state, reaction.kill_animation, false, result.events)
		state.death_entity_index = pose.entity_index
		result.events.append("entity_pop_explosion_request")
	if _exploration_guard != null:
		return _exploration_guard.check_world(state.world_position)
	return ""

func _failed_tick(result: TickResult, issue: String) -> TickResult:
	result.error = issue
	result.control_snapshot = null
	result.move_snapshot = null
	result.collision_snapshot = null
	result.camera_snapshot = null
	result.scripts_snapshot = null
	result.final_snapshot = null
	result.entity_contacts.clear()
	result.events.clear()
	result.rng_consumers.clear()
	return result

func _platform_pose(state: RunSnapshot) -> EntitySnapshot:
	if state.entities != null:
		for pose: EntitySnapshot in state.entities.entities:
			if pose != null and pose.entity_index == state.current_entity_index and PlatformMath.valid(pose.matrix12):
				if state.entities.lifecycle_enabled and (not pose.live or not pose.lifecycle_supported):
					return null
				return pose
	return null

func _platform_definition(state: RunSnapshot) -> FormContactDefinition:
	if _entity_collision != null:
		for definition: FormContactDefinition in _entity_collision.contacts:
			if definition.entity_index == state.current_entity_index:
				return definition
	return null

func _mark_carry(state: RunSnapshot, index: int) -> void:
	if not state.entity_carry_indices.has(index):
		state.entity_carry_indices.append(index)

func _mount_platform(state: RunSnapshot, definition: FormContactDefinition, pose: EntitySnapshot, reaction: FormReactionResult, events: Array[String]) -> String:
	var matrix: PackedInt32Array = pose.matrix12
	if PlatformMath.s32(matrix[2] * matrix[2] + matrix[8] * matrix[8]) < 0x700 * 0x700:
		reaction.status = FormReactionResult.NONE
		reaction.reason = "SAFE platform is too vertical"
		return ""
	if state.flags & (2 | 16) != (2 | 16):
		var previous: PackedInt32Array = PackedInt32Array()
		if state.current_entity_index >= 0:
			previous = _platform_pose(state).matrix12
		_react_fall(state, state.world_position.y - state.old_y, reaction.contact.cell_flags, events)
		var outcome: TerrainCallbackResult = TerrainPlatform.land(state, definition, reaction.contact, pose, _candidate_camera, previous)
		_apply_requests(state, outcome, events)
		if not outcome.error.is_empty():
			return outcome.error
		_update_world(state)
		_mark_carry(state, pose.entity_index)
		events.append("platform_attachment")
	reaction.hit = true
	return ""

func _detach_platform(state: RunSnapshot, events: Array[String]) -> void:
	if state.current_entity_index < 0:
		return
	_callback_error = _candidate_camera.transition_attachment(_platform_pose(state).matrix12, PackedInt32Array(), false)
	state.current_entity_index = -1
	events.append("platform_departure")

func _jump_platform(state: RunSnapshot, input: int, events: Array[String], is_super: bool, distance: int) -> String:
	var definition: FormContactDefinition = _platform_definition(state)
	var pose: EntitySnapshot = _platform_pose(state)
	if definition == null or pose == null:
		return "Platform departure requires a current definition and pose"
	var old_direction: int = state.direction
	var old_y: int = state.target_y
	var selection: PlatformJumpResult = TerrainPlatform.prepare_jump(state, definition, pose, _grid, _controller_directions, input, is_super, distance)
	if not selection.error.is_empty():
		return selection.error
	if selection.blocked:
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.OUCH, state)
		events.append("ouch")
		return ""
	if not selection.moved:
		return ""
	if selection.detach:
		_detach_platform(state, events)
		if not _callback_error.is_empty():
			return _callback_error
	state.mode = MODE_JUMPING
	state.remaining_ticks = 15 if is_super else 3 if state.powerup_flags & 2 else 6
	state.old_y = old_y
	if is_super:
		state.flags |= 32
	var origin: Vector3i = state.entity_offset_16 if state.current_entity_index >= 0 and not state.flags & 64 else state.position_16
	state.velocity_16.x = PlatformMath.divide(state.target_16.x - origin.x, state.remaining_ticks)
	state.velocity_16.z = PlatformMath.divide(state.target_16.z - origin.z, state.remaining_ticks)
	state.velocity_16.y = PlatformMath.divide((state.target_y - state.world_position.y) << 16, state.remaining_ticks + 1) - ((GRAVITY_16 * (state.remaining_ticks + 1)) >> 1)
	var roll: bool = old_direction == state.direction and state.buffered_input_count > 3 and not is_super and not state.powerup_flags & (2 | 4)
	if roll:
		state.buffered_input_count = 0
	state.animation_requests += 1
	_request_animation(FrogAnimationCatalog.SUPERJUMP if is_super else FrogAnimationCatalog.SUPERHOP if state.powerup_flags & 2 else FrogAnimationCatalog.AUTOHOP if state.powerup_flags & 4 else FrogAnimationCatalog.ROLL if roll else FrogAnimationCatalog.HOP, state)
	state.sound_requests += 1
	events.append("super_hop" if is_super else "quick_hop" if state.powerup_flags & 2 else "auto_hop" if state.powerup_flags & 4 else "roll" if roll else "hop")
	events.append("hop_sound")
	if is_super or state.powerup_flags & 2 or not state.powerup_flags & 4:
		state.score_requests += 1
		events.append("score_10_request" if is_super else "score_50_request" if roll or state.powerup_flags & 2 else "score_5_request")
	return ""

func _move_platform_jumping(state: RunSnapshot, events: Array[String], react_on_land: bool) -> void:
	var pose: EntitySnapshot = _platform_pose(state)
	state.remaining_ticks -= 1
	if state.remaining_ticks > 0:
		_platform_freefall(state, pose, events)
		return
	if state.flags & (16 | 2) == (16 | 2):
		var definition: FormContactDefinition = _platform_definition(state)
		state.flags = (state.flags & ~TerrainPlatform.LANDED_CLEAR) | 4
		state.mode = 0
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.PANT, state)
		state.entity_offset_16 = state.target_16
		state.entity_transform12 = PlatformMath.project(PlatformMath.multiply(state.matrix12, PlatformMath.transpose(pose.matrix12)))
		state.position_16 = PlatformMath.world(pose.matrix12, state.entity_offset_16) * 65536
		state.velocity_16 = Vector3i.ZERO
		var flags: int = definition.grid_flags[state.entity_cell.y * definition.dimensions.x + state.entity_cell.x]
		_react_fall(state, state.world_position.y - state.old_y, flags, events)
		_update_world(state)
		_update_matrix(state)
		if react_on_land:
			_react(state, flags, events)
		state.old_position_16 = state.position_16
		return
	if state.flags & 64:
		if not state.flags & 16:
			state.position_16.x = state.target_16.x
			state.position_16.z = state.target_16.z
		_detach_platform(state, events)
		_land(state, events)
		_update_world(state)
		_update_matrix(state)
		if react_on_land:
			_react(state, _grid.squares[state.square_index].flags, events)
		state.old_position_16 = state.position_16
		return
	# At the last no-land departure tick C integrates once more before detaching.
	_platform_freefall(state, pose, events)
	_detach_platform(state, events)
	if state.square_index < 0:
		var stack: GridStackDefinition = _grid.stack_at(state.cell)
		if stack == null:
			_callback_error = "Source platform final-hop stack lookup lies outside authored storage"
			return
		for index: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
			if _grid.squares[index].flags & 1 and GridQueries.square_height(_grid.squares[index]) >= state.world_position.y:
				state.square_index = index
				break
	state.flags = (state.flags & ~TerrainPlatform.LANDED_CLEAR) | 128 | 8192
	state.remaining_ticks = 0x7FFFFFF
	state.velocity_16.x = 0
	state.velocity_16.z = 0
	_update_world(state)
	state.old_position_16 = state.position_16

func _platform_freefall(state: RunSnapshot, pose: EntitySnapshot, events: Array[String]) -> void:
	state.velocity_16.y += GRAVITY_16
	if state.flags & (128 | 8192) == (128 | 8192) and state.world_position.y - state.old_y >= 0:
		state.animation_requests += 1
		_request_animation(FrogAnimationCatalog.FREEFALL if _map_index >= 42 and _map_index <= 47 else FrogAnimationCatalog.FALLING, state)
		state.flags &= ~8192
		events.append("falling")
	if not state.flags & 64:
		TerrainPlatform.airborne(state, pose)
	else:
		state.position_16 += state.velocity_16

func _request_animation(animation_id: int, state: RunSnapshot) -> void:
	state.last_animation_request = animation_id
	if _candidate_animation != null:
		_candidate_animation.request(animation_id)

func _sync_systems(state: RunSnapshot) -> void:
	if _has_entity_updates:
		_candidate_entities.set_contact_flags(state.entity_hit_indices, state.entity_carry_indices)
		state.entities = _candidate_entities._state
	state.camera = _candidate_camera.snapshot() if _candidate_camera != null else null
	state.animation = _candidate_animation.state.copy() if _candidate_animation != null else null
	state.rng_state = _candidate_random.state
	state.rng_draw_count = _candidate_random.draw_count
	_sync_facts(state)

func _sync_facts(state: RunSnapshot) -> void:
	state.source_id = _source_id
	state.resource_id = _resource_id
	state.map_index = _map_index
	state.destination_cell = GridQueries.world_to_cell(_grid, state.target_16.x >> 16, state.target_16.z >> 16)
	if _entity_collision != null and _entity_collision.platforms_enabled and (state.flags & 128 or (state.current_entity_index < 0 and state.mode != MODE_JUMPING)):
		# After angled departure the source retains a stale local target. Freefall
		# has no active horizontal target; inspect the current world cell instead.
		state.destination_cell = state.cell
	elif state.current_entity_index >= 0 and not state.flags & 64:
		var target: Vector3i = PlatformMath.world(_platform_pose(state).matrix12, state.target_16)
		state.destination_cell = GridQueries.world_to_cell(_grid, target.x, target.z)
	state.square_flags = 0
	state.square_source_offset = -1
	state.polygon_index = -1
	state.polygon_source_offset = -1
	if state.square_index >= 0:
		var square: GridSquareDefinition = _grid.squares[state.square_index]
		state.square_flags = square.flags
		state.square_source_offset = square.source_offset
		state.polygon_index = square.polygon_index
		state.polygon_source_offset = square.polygon_source_offset

func _apply_requests(state: RunSnapshot, callback: TerrainCallbackResult, events: Array[String]) -> void:
	_callback_error = callback.error
	for animation_id: int in callback.animation_ids:
		state.animation_requests += 1
		_request_animation(animation_id, state)
	if callback.kill_animation >= 0:
		_kill(state, callback.kill_animation, false, events)
	if callback.start_slipping_sound:
		events.append("slipping_loop_start")
	if callback.kill_looping_sound:
		events.append("slipping_loop_stop")
	if callback.create_slide_particles:
		events.append("slide_particles_request")
	if callback.kill_slide_particles:
		events.append("slide_particles_stop")
	if callback.setup_mode_request == 269:
		_apply_requests(state, TerrainCliffRoll.setup(state, _grid), events)
		state.mode = 269

func _apply_callback(state: RunSnapshot, callback: TerrainCallbackResult, events: Array[String]) -> void:
	_apply_requests(state, callback, events)
	if callback.land_requested:
		_land(state, events)
	if callback.callback_flags & 1:
		_update_world(state)
	if callback.callback_flags & 8:
		_update_matrix(state)
	if callback.callback_flags & 4:
		_react(state, callback.react_flags & 65535, events)
	if callback.callback_flags & 2:
		state.old_position_16 = state.position_16
