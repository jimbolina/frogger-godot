class_name GameplayRun
extends RefCounted
## Ordered gameplay transaction: creates candidates, sequences systems and commits.
## Owns detached frog/entity, reward and optional level-flow candidates.

const TICKS_PER_SECOND: int = 30
var error: String = ""
var _sound_definitions: Array[LogicalSoundDefinition] = []
var _level_time: int = 2250
var _demo_playback: bool = false
var _grid: GridDefinition = null
var _default_cell: Vector2i = Vector2i.ZERO
var _default_direction: int = 0
var _state: GameplayState = null
var _collision_enabled: bool = false
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
var _tick_guard: TickGuard = null
var _camera_zones: Array[ZoneDefinition] = []
var _frog: Frog = Frog.new()
var _has_entity_updates: bool = false
var _cave_light: bool = false
var _sky: bool = false

## Validates and copies ordinary terrain, then creates a stationary component start.
static func create(level: LevelDefinition, initial: RunStart = null) -> GameplayRun:
	var run := GameplayRun.new()
	if level == null or level.grid == null:
		run.error = "Terrain run requires a level grid"
		return run
	run.error = run._copy_grid(level.grid)
	if not run.error.is_empty():
		return run
	if not level.rewards.is_empty():
		if level.rewards.size() != 24 or level.rewards.has(null):
			run.error = "Gameplay requires all 24 non-null reward definitions"
			return run
		run._frog.rewards.clear()
		for reward: RewardDefinition in level.rewards:
			run._frog.rewards.append(reward.copy())
	run._frog.music_pitch_offset = level.music_pitch_offset
	for sound: LogicalSoundDefinition in level.sounds:
		run._sound_definitions.append(sound.copy())
	run._frog.flow_enabled = level.flow_enabled
	run._level_time = level.level_time
	run._demo_playback = level.demo_playback
	if level.level_time < 0:
		run.error = "Level timer must be nonnegative"
		return run
	run._default_cell = level.spawn_cell
	run._default_direction = level.spawn_direction
	run._collision_enabled = level.collision_enabled
	run._frog.collision_bounds = level.collision_bounds
	run._frog.death_height = level.theme_death_height
	run._frog.frog_ambient = level.frog_ambient
	run._frog.theme = level.theme
	run._frog.map_index = level.map_index
	run._camera_definition = level.camera.copy() if level.camera != null else null
	run._action_lengths = level.frog_action_lengths.duplicate()
	run._theme_name = level.theme_name
	run._cave_light = level.cave_light
	run._sky = level.theme == SkyDriftState.THEME
	run._frog.source_id = level.source_id
	run._frog.resource_id = level.resource_id
	if not level.camera_zones.is_empty():
		if level.camera == null:
			run.error = "Active zones require an integrated camera"
			return run
		var identities: Dictionary[int, bool] = {}
		for zone: ZoneDefinition in level.camera_zones:
			if zone == null:
				run.error = "Active zones contain a null definition"
				return run
			run.error = zone.validate_camera()
			if identities.has(zone.zone_index):
				run.error = "Active zones contain duplicate authored identities"
			if not run.error.is_empty():
				return run
			identities[zone.zone_index] = true
			run._camera_zones.append(zone.copy())
	var requirements: TickGuardCandidate = TickGuardCandidate.from_level(level)
	if level.tick_guard != null:
		run._tick_guard = level.tick_guard.copy()
		run.error = run._tick_guard.check(TickGuard.Phase.SETUP, requirements)
		if not run.error.is_empty():
			return run
	elif requirements.restricted_contacts:
		run.error = "Disabled contacts require a tick guard"
		return run
	if level.entity_collision != null:
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
		if run._entity_collision.frog_collision != null:
			var actions: Array[FrogCollisionDefinition.Action] = run._entity_collision.frog_collision.actions
			if actions.size() != run._action_lengths.size():
				run.error = "Frog collision and animation action inventories differ"
				return run
			for action: int in actions.size():
				if actions[action].frames.size() != run._action_lengths[action]:
					run.error = "Frog collision and animation cel counts differ"
					return run
		for entity: EntityDefinition in run._entity_collision.entities:
			run._has_entity_updates = run._has_entity_updates or entity.script_definition != null or entity.behavior.has_custom_update()
		run._entities = EntityRun.create(run._entity_collision.entities, run._entity_collision.lifecycle)
		if not run._entities.error.is_empty():
			run.error = run._entities.error
			return run
	if run._frog.collision_bounds.size.x <= 0 or run._frog.collision_bounds.size.y <= 0 or run._frog.theme < 0 or run._frog.theme > 10 or run._frog.map_index < -1 or run._frog.map_index > 2147483647 or run._frog.death_height < -2147483648 or run._frog.death_height > 2147483647:
		run.error = "Collision setup requires positive fade bounds, a known theme and signed32 death height"
		return run
	for corner: int in [run._frog.collision_bounds.position.x, run._frog.collision_bounds.position.y, int(run._frog.collision_bounds.position.x) + run._frog.collision_bounds.size.x, int(run._frog.collision_bounds.position.y) + run._frog.collision_bounds.size.y]:
		if corner < -32768 or corner > 32767:
			run.error = "Fade bounds must fit source signed16 corners"
			return run
	run._frog.grid = run._grid
	run._frog.entity_collision = run._entity_collision
	run._frog.tick_guard = run._tick_guard
	run.error = run.reset(initial)
	return run

## Resets every owned clock, buffer and request count; failed starts preserve current state.
func reset(initial: RunStart = null) -> String:
	var prepared: Frog.StartResult = _frog.prepare_start(initial, _default_cell, _default_direction)
	if not prepared.error.is_empty():
		return prepared.error
	var state: GameplayState = prepared.state
	if not _sound_definitions.is_empty():
		state.sound = LogicalSoundState.create(_sound_definitions)
		if not state.sound.error.is_empty():
			return state.sound.error
	state.flow.remaining_time = _level_time
	if _frog.flow_enabled and state.frog.start_mode == RunStart.Mode.SINGLE_START:
		state.flow.phase = LevelFlowState.Phase.START
	var controller_directions: PackedInt32Array = prepared.directions
	if _tick_guard != null:
		var guard_error: String = _check_guard(TickGuard.Phase.RESET_WORLD, state)
		if not guard_error.is_empty():
			return guard_error
	_update_camera_zone(state)
	_frog.sync_facts(state)
	var random: SourceRandom = SourceRandom.create(initial.seed if initial != null else 1)
	var camera: GameplayCamera = null
	var animation: FrogAnimationController = null
	if _camera_definition != null:
		camera = GameplayCamera.create(_camera_definition, state.frog.world_position, initial.camera_startup if initial != null else false)
		if not camera.error.is_empty():
			return camera.error
		state.camera = camera.snapshot()
		controller_directions = state.camera.controller_directions.duplicate()
	if not _action_lengths.is_empty():
		animation = FrogAnimationController.create(_action_lengths, FrogAnimationContext.create(random, _theme_name))
		if not animation.error.is_empty():
			return animation.error
		state.animation = animation.state.copy()
	if _entity_collision != null and _entity_collision.frog_collision != null:
		if state.animation == null:
			return "Entity primitives require authoritative frog animation"
		state.frog.frog_collision_pose = FrogCollisionPose.new()
		var pose_issue: String = state.frog.frog_collision_pose.refresh(_entity_collision.frog_collision, state.animation.action, state.animation.cel, state.frog.matrix12)
		if not pose_issue.is_empty():
			return pose_issue
	if _tick_guard != null:
		var animated_issue: String = _check_guard(TickGuard.Phase.RESET_POSE, state)
		if not animated_issue.is_empty():
			return animated_issue
	state.rng_state = random.state
	state.sky_drift = SkyDriftState.new() if _sky else null
	state.game_timer = initial.game_timer & 0xffffffff if initial != null else 0
	if initial != null:
		state.flow.score = initial.score
		state.flow.old_score = initial.old_score
		state.flow.life_bonus_score = initial.life_bonus_score
	state.cheats = initial.cheats.copy() if initial != null and initial.cheats != null else CheatState.new()
	state.frog.start_timer = initial.start_timer if initial != null else 0
	if state.frog.start_timer < 0:
		return "Start timer must be nonnegative"
	var candidate_entities: EntityRun = _entities.copy() if _entities != null else null
	if candidate_entities != null:
		var environment: EntityEnvironmentState = _entity_collision.environment.copy() if _entity_collision.environment != null else null
		var entity_error: String = candidate_entities.reset(environment)
		if not entity_error.is_empty():
			return entity_error
		state.entities = candidate_entities.snapshot()
		state.entity_environment = environment
	var sound_issue: String = _synchronize_sound_entities(state)
	if not sound_issue.is_empty():
		return sound_issue
	_state = state
	_frog.controller_directions = controller_directions
	_camera = camera
	_random = random
	_animation = animation
	_entities = candidate_entities
	return ""

## Replaces the committed cheat switches; call it only while no tick is in flight.
func set_cheats(value: CheatState) -> String:
	if _state == null:
		return "Reset the gameplay run before setting cheats"
	if value == null:
		return "Cheat switches must be provided"
	_state.cheats = value.copy()
	return ""

## The pause menu's Quit (pause.c:499-513): removes the frog's control and requests the
## game-over page by entering [constant LevelFlowState.Phase.GAME_OVER] without completing the run.
## Call it only while no tick is in flight.
func quit_game() -> String:
	if _state == null:
		return "Reset the gameplay run before quitting the game"
	_state.frog.flags &= ~FrogFlags.CONTROL_ACTIVE
	_state.flow.phase = LevelFlowState.Phase.GAME_OVER
	return ""

## Returns detached state; changing it has no effect on the run.
func snapshot() -> GameplayState:
	return _state.copy() if _state != null else null

func _update_camera_zone(state: GameplayState) -> void:
	var selected: Vector2i = ZoneQueries.update_camera_match(_camera_zones, state.frog.cell, Vector2i(state.frog.camera_zone_index, state.frog.camera_zone_region_index), state.frog.flags)
	state.frog.camera_zone_index = selected.x
	state.frog.camera_zone_region_index = selected.y

## Commits one atomic tick. Optional phase capture affects diagnostics only; final state is always detached.
func step(command: TickCommand, capture_phases: bool = true) -> TickResult:
	var result := TickResult.new()
	_capture_phases = capture_phases
	if _state == null or command == null:
		result.error = "Terrain run and tick command must be initialized"
		return result
	result.tick_index = command.tick_index
	if _state.completed:
		result.error = "Terrain run completed; reset before supplying another tick"
		return result
	if command.tick_index != _state.tick_index:
		result.error = "Tick index must equal next tick %d" % _state.tick_index
		return result
	if command.recorded_input_exhausted and command.recorded_input_byte >= 0:
		result.error = "Recorded demo input cannot contain a byte and mark exhaustion"
		return result
	if command.recorded_input_byte < -1 or command.recorded_input_byte > 255:
		result.error = "Recorded demo input must be an unsigned byte or -1"
		return result
	if (command.recorded_input_byte >= 0 or command.recorded_input_exhausted) and (command.pressed_mask != 0 or command.held_mask != 0):
		result.error = "Recorded demo input cannot be mixed with live controller masks"
		return result
	if command.pressed_mask < 0 or command.held_mask < 0 or (command.pressed_mask | command.held_mask) & ~511:
		result.error = "Terrain commands support directional, super-hop, tongue, camera-turn and croak masks"
		return result
	if _camera == null and (command.pressed_mask | command.held_mask) & 96:
		result.error = "Camera-turn commands require an integrated camera definition"
		return result
	if command.start_timer_context < -1 or command.start_timer_context > 2147483647 or (command.start_sequence_complete and _state.frog.mode not in [FrogMode.LEVEL_START_BOUNCE, FrogMode.LEVEL_START_COME_TO_REST]):
		result.error = "Start context requires a nonnegative timer and completion only during single-start callbacks"
		return result
	_candidate_camera = _camera.copy() if _camera != null else null
	_candidate_random = _random.copy()
	_candidate_random.begin_tick()
	_candidate_animation = _animation.copy(_animation.context.copy(_candidate_random)) if _animation != null else null
	_candidate_entities = _entities.begin_candidate(command.tick_index, _state.attachment.current_entity_index, _has_entity_updates, _grid) if _entities != null else null
	_frog.candidate_entities = _candidate_entities
	_frog.begin_tick(_candidate_camera, _candidate_random, _candidate_animation, _frog.controller_directions)
	var next: GameplayState = _state.copy(false)
	if _candidate_entities != null:
		result.error = _candidate_entities.error
		if not result.error.is_empty():
			return _failed_tick(result, result.error)
	next.entities = _candidate_entities.snapshot() if _candidate_entities != null else null
	if next.sound != null:
		var sound_issue: String = _synchronize_sound_entities(next)
		if sound_issue.is_empty():
			sound_issue = next.sound.advance(_candidate_random)
		if not sound_issue.is_empty():
			return _failed_tick(result, sound_issue)
		if next.entities != null:
			for entity: EntitySnapshot in next.entities.entities:
				var moving: LogicalMovingSound = next.sound.moving_for(entity.entity_index)
				_candidate_entities.set_sound_state(entity.entity_index, moving != null, moving != null and moving.voice_tag >= 0)
	var entity_issue: String = _update_entity_scripts(next, result.events)
	if not entity_issue.is_empty():
		return _failed_tick(result, entity_issue)
	if _tick_guard != null:
		var exclusion_issue: String = _check_guard(TickGuard.Phase.ENTITY_UPDATE, next)
		if not exclusion_issue.is_empty():
			return _failed_tick(result, exclusion_issue)
	next.attachment.entity_hit_indices = PackedInt32Array()
	next.attachment.entity_carry_indices = PackedInt32Array()
	if next.attachment.current_entity_index >= 0 and (_frog.contacts.platform_pose(_frog, next) == null or _frog.contacts.platform_definition(_frog, next) == null):
		return _failed_tick(result, "Current platform identity or matrix is invalid")
	if command.start_timer_context >= 0:
		next.frog.start_timer = command.start_timer_context
	if command.start_sequence_complete:
		next.frog.mode = FrogMode.WAIT_FOR_CAMERA
	_frog.callback_error = ""
	var control_error: String = _frog.control(next, command, result.events)
	if not control_error.is_empty():
		return _failed_tick(result, control_error)
	_sync_systems(next)
	if capture_phases:
		result.control_snapshot = next.copy()
	next.frog.old_position_16 = next.frog.position_16
	_frog.move(next, result.events)
	if not _frog.callback_error.is_empty():
		return _failed_tick(result, _frog.callback_error)
	if next.frog.flags & FrogFlags.ON_ENTITY and next.attachment.current_entity_index >= 0:
		_frog.contacts.mark_carry(_frog, next, next.attachment.current_entity_index)
	_update_camera_zone(next)
	if _tick_guard != null:
		var guard_error: String = _check_guard(TickGuard.Phase.MOVEMENT, next)
		if not guard_error.is_empty():
			return _failed_tick(result, guard_error)
	_sync_systems(next)
	if capture_phases:
		result.move_snapshot = next.copy()
	TerrainModifiers.update(next)
	var continue_entities: bool = true
	if _collision_enabled:
		continue_entities = _frog.collide(next, result.events)
	if not _frog.callback_error.is_empty():
		return _failed_tick(result, _frog.callback_error)
	if continue_entities and _candidate_entities != null:
		if _tick_guard != null:
			var animated_issue: String = _check_guard(TickGuard.Phase.BEFORE_CONTACT, next)
			if not animated_issue.is_empty():
				return _failed_tick(result, animated_issue)
		var entity_error: String = _frog.contacts.contact_entities(_frog, next, result)
		if not entity_error.is_empty():
			return _failed_tick(result, entity_error)
	if not _frog.callback_error.is_empty():
		return _failed_tick(result, _frog.callback_error)
	FrogTint.update(next.frog, _cave_light, _frog.collision_bounds, _frog.theme)
	_sync_systems(next)
	if capture_phases:
		result.collision_snapshot = next.copy()
	if _candidate_camera != null:
		var camera_input := GameplayCameraTick.new()
		camera_input.frog_world = next.frog.world_position
		camera_input.frog_mode = next.frog.mode
		camera_input.remaining_ticks = next.frog.remaining_ticks
		camera_input.old_y = next.frog.old_y
		camera_input.target_y = next.frog.target_y
		camera_input.freefall = next.frog.flags & FrogFlags.FREEFALL != 0
		camera_input.superjump = next.frog.flags & FrogFlags.SUPERJUMP != 0
		camera_input.start_timer = next.frog.start_timer
		camera_input.camera_zone = ZoneQueries.definition_for(_camera_zones, next.frog.camera_zone_index)
		camera_input.on_entity = next.attachment.current_entity_index >= 0
		if camera_input.on_entity:
			camera_input.entity_matrix12 = _frog.contacts.platform_pose(_frog, next).matrix12.duplicate()
		result.error = _candidate_camera.step(camera_input)
		if not result.error.is_empty():
			return _failed_tick(result, result.error)
		next.camera = _candidate_camera.snapshot()
		next.attachment.entity_angle = (next.attachment.entity_angle + next.camera.entity_angle_delta) & 3
	if capture_phases:
		result.camera_snapshot = next.copy()
	if _candidate_animation != null:
		next.frog.no_input_timer = _candidate_animation.update_scripts(next.frog.no_input_timer)
		_sync_systems(next)
		next.frog.animation_condition_counter = _candidate_animation.context.if_counter
	if capture_phases:
		result.scripts_snapshot = next.copy()
	if _candidate_animation != null:
		_candidate_animation.advance_pose()
		if not _candidate_animation.error.is_empty():
			result.error = _candidate_animation.error
			return _failed_tick(result, result.error)
		next.animation = _candidate_animation.state.copy()
		next.frog.animation_condition_counter = _candidate_animation.context.if_counter
	if next.frog.frog_collision_pose != null:
		var pose_issue: String = next.frog.frog_collision_pose.refresh(_entity_collision.frog_collision, next.animation.action, next.animation.cel, next.frog.matrix12)
		if not pose_issue.is_empty():
			return _failed_tick(result, pose_issue)
	if _candidate_entities != null:
		_candidate_entities.advance_animations()
		var primitive_issue: String = _candidate_entities.refresh_primitive_poses(_entity_collision.contacts)
		if not primitive_issue.is_empty():
			return _failed_tick(result, primitive_issue)
		next.entities = _candidate_entities.snapshot()
	var tongue_issue: String = TongueController.advance(_frog, next, _candidate_entities, result.events)
	if not tongue_issue.is_empty():
		return _failed_tick(result, tongue_issue)
	if _candidate_entities != null and _entity_collision.lifecycle != null:
		var visibility_error: String = _candidate_entities.apply_visibility(next.camera, next.entity_environment, next.flow.gold_collected)
		if not visibility_error.is_empty():
			return _failed_tick(result, visibility_error)
		next.entities = _candidate_entities.snapshot()
		var sound_issue: String = _synchronize_sound_entities(next)
		if not sound_issue.is_empty():
			return _failed_tick(result, sound_issue)
	if next.sky_drift != null:
		next.sky_drift.step(next.game_timer, _candidate_random)
	var play_frame: bool = true
	if _frog.flow_enabled:
		var checkpoint_flow: bool = next.flow.phase == LevelFlowState.Phase.CHECKPOINT
		play_frame = _state.frog.start_timer_hold == 0 and next.flow.phase in [LevelFlowState.Phase.PLAY, LevelFlowState.Phase.DEATH]
		var flow: LevelFlow = LevelFlow.advance(_frog, next, _candidate_entities, result.events, _demo_playback, _candidate_random, _level_time, command.recorded_input_byte < 0 and bool(command.pressed_mask & TickCommand.SUPER_HOP))
		if not flow.error.is_empty():
			return _failed_tick(result, flow.error)
		if flow.reset != LevelFlow.Reset.NONE:
			var reset_issue: String = _reset_in_level(next, flow.reset == LevelFlow.Reset.CHECKPOINT, result.events)
			if not reset_issue.is_empty():
				return _failed_tick(result, reset_issue)
		if checkpoint_flow or flow.reset != LevelFlow.Reset.NONE:
			next.entities = _candidate_entities.snapshot() if _candidate_entities != null else null
		play_frame = play_frame and flow.reset == LevelFlow.Reset.NONE
	if play_frame:
		next.game_timer = (next.game_timer + 1) & 0xffffffff
	next.rng_state = _candidate_random.state
	next.diagnostics.rng_draw_count = _candidate_random.draw_count
	if _tick_guard != null:
		var guard_error: String = _check_guard(TickGuard.Phase.FINAL, next)
		if not guard_error.is_empty():
			return _failed_tick(result, guard_error)
	result.rng_consumers.assign(_candidate_random.consumers)
	next.tick_index += 1
	_state = next
	_camera = _candidate_camera
	_random = _candidate_random
	_animation = _candidate_animation
	if _candidate_entities != null:
		_entities.commit_candidate(_candidate_entities)
		_candidate_entities = null
	if _camera != null:
		_frog.controller_directions = next.camera.controller_directions.duplicate()
	result.consumed_demo_byte = _frog.consumed_demo_byte
	result.final_snapshot = next.copy()
	return result

func _update_entity_scripts(state: GameplayState, events: Array[TickEvent]) -> String:
	if _candidate_entities == null or not _has_entity_updates:
		return ""
	for slot: int in _candidate_entities.update_slots():
		var visiting: bool = _candidate_entities.begin_update(slot, state.attachment.current_entity_index, _grid)
		if not _candidate_entities.error.is_empty():
			return _candidate_entities.error
		if not visiting:
			state.entities = _candidate_entities.snapshot()
			var sound_issue: String = _synchronize_sound_entities(state)
			if not sound_issue.is_empty():
				return sound_issue
			continue
		state.entities.entities[slot] = _candidate_entities.entity_snapshot(slot)
		var previous_flags: int = state.entities.entities[slot].live_flags
		var was_alive: bool = state.frog.mode != FrogMode.DYING and not state.frog.flags & FrogFlags.MUST_DIE
		var issue: String = _visit_entity(slot, previous_flags, state, events)
		if not issue.is_empty():
			return issue
		var killed: bool = was_alive and bool(state.frog.flags & FrogFlags.MUST_DIE)
		if _cave_light:
			_candidate_entities.apply_cave_fade(slot, Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]), state.entity_environment)
		if killed:
			events.append(TickEvent.make(TickEvent.Kind.DEATH_PGEN).for_entity(_entity_collision.entities[slot].entity_index))
		_candidate_entities.finish_update(slot, previous_flags, _candidate_random, state.requests.sound_requests, state.entity_environment, killed, _capture_phases)
		state.entities.entities[slot] = _candidate_entities.entity_snapshot(slot)
	_candidate_entities.sync_update_observations(state.entities)
	return ""

func _visit_entity(slot: int, previous_flags: int, state: GameplayState, events: Array[TickEvent]) -> String:
	var definition: EntityDefinition = _entity_collision.entities[slot]
	if definition.behavior.has_custom_update():
		var frog_position := Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
		var background: EntityCustomResult = _candidate_entities.update_custom(definition.entity_index, state.entity_environment, _candidate_random, frog_position, _state.attachment.entity_hit_indices.has(definition.entity_index), _entity_collision.contacts, state, _grid, _entity_collision)
		if not background.error.is_empty():
			return background.error
		if background.environment.collision_disabled != state.entity_environment.collision_disabled:
			_candidate_entities.apply_checkpoint_collision(background.environment.collision_disabled)
			state.entities = _candidate_entities.snapshot()
		if not background.target_effects.is_empty():
			state.entities = _candidate_entities.snapshot()
		if background.stop_moving_sound and state.sound != null:
			state.sound.retire_moving(definition.entity_index)
		state.entity_environment = background.environment
		if not background.frog_matrix12.is_empty():
			state.frog.matrix12 = background.frog_matrix12.duplicate()
		_candidate_random.state = background.random.state
		_candidate_random.draw_count = background.random.draw_count
		_candidate_random.consumers.assign(background.random.consumers)
		state.entities.entities[slot] = _candidate_entities.entity_snapshot(slot)
		if background.frog_fall_requested:
			var fall_issue: String = _frog.eject(state, 0, 0, events)
			if not fall_issue.is_empty():
				return fall_issue
			state.frog.cell = GridQueries.world_to_cell(_grid, state.frog.matrix12[9], state.frog.matrix12[11])
			var stack: GridStackDefinition = _grid.stack_at(state.frog.cell)
			if stack != null and stack.square_count > 0:
				state.frog.square_index = stack.first_square_index
				state.frog.flags |= FrogFlags.FREEFALL
		if background.death_animation >= 0:
			_frog.kill(state, background.death_animation, false, events)
		for request: TickEvent in background.entity.requests:
			if request.kind == TickEvent.Kind.REWARD:
				if request.reward_id < 0 or request.reward_id >= _frog.rewards.size():
					return "Entity requested an unknown reward"
				var reward_issue: String = GameplayRewards.apply(_frog.rewards[request.reward_id], state, events, _candidate_random)
				if not reward_issue.is_empty():
					return reward_issue
			elif request.kind == TickEvent.Kind.GOLD_FROG_COLLECT:
				var gold_issue: String = CheckpointCollection.collect_gold(_frog, state, _candidate_random, events)
				if not gold_issue.is_empty():
					return gold_issue
			var sound_issue: String = _apply_entity_sound(state, background.entity, request)
			if not sound_issue.is_empty():
				return sound_issue
			events.append(request.for_entity(definition.entity_index))
	if definition.script_definition == null:
		return ""
	var context := EntityUpdateContext.new()
	var runtime: EntityScriptRuntime = null
	if state.sound != null:
		runtime = EntityScriptRuntime.new()
		runtime.state = state
		runtime.frog = _frog
		runtime.events = events
		runtime.entity_index = definition.entity_index
		runtime.generation = state.entities.entities[slot].generation
		context.sound_allocation_enabled = state.flow.phase != LevelFlowState.Phase.GAME_OVER
		context.moving_allocation_enabled = context.sound_allocation_enabled and state.frog.mode not in [FrogMode.HIT_CHECKPOINT, FrogMode.CHECKPOINT_COLLECTED]
		var moving: LogicalMovingSound = state.sound.moving_for(definition.entity_index)
		context.moving_voice_active = moving != null and moving.voice_tag >= 0
	context.entity_index = definition.entity_index
	context.form_id = definition.form_id
	context.base_matrix = state.entities.entities[slot].matrix12.duplicate()
	context.frog_position = Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
	context.frog_mode = state.frog.mode
	context.previous_hit = bool(previous_flags & EntityLiveFlags.HIT_FROG_0)
	context.previous_carry = bool(previous_flags & EntityLiveFlags.CARRIES_FROG_0)
	context.has_path = definition.path_definition != null
	context.no_display = bool(state.entities.entities[slot].entity_flags & EntityDefinition.NO_DISPLAY)
	context.environment = state.entity_environment
	context.fade_bounds = PackedInt32Array([_frog.collision_bounds.position.x, _frog.collision_bounds.end.x, _frog.collision_bounds.position.y, _frog.collision_bounds.end.y])
	var update: EntityUpdateResult = _candidate_entities.update_candidate_script(slot, context, _candidate_random, runtime)
	if not update.error.is_empty():
		return "Entity %d script: %s" % [definition.entity_index, update.error]
	if update.environment != null:
		state.entity_environment = update.environment
	if update.checkpoint_collision_changed:
		_candidate_entities.apply_checkpoint_collision(update.environment.collision_disabled)
		state.entities = _candidate_entities.snapshot()
	if update.random != _candidate_random:
		_candidate_random.state = update.random.state
		_candidate_random.draw_count = update.random.draw_count
		_candidate_random.consumers.assign(update.random.consumers)
	for effect: EntityScriptEffect in update.effects:
		if effect.applied:
			continue
		if effect.eject:
			var issue: String = _frog.eject(state, effect.grid_delta, effect.jump_duration, events)
			if not issue.is_empty():
				return issue
		elif effect.death_animation >= 0:
			_frog.kill(state, effect.death_animation, false, events)
		else:
			var request: TickEvent = effect.notification
			events.append(request.for_entity(definition.entity_index))
			if request.kind == TickEvent.Kind.SOUND:
				state.requests.sound_requests += 1
	state.entities.entities[slot] = _candidate_entities.entity_snapshot(slot)
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

## Restarts the frog after a death or checkpoint as frozen C's LevelEnd/LevelStart does,
## holding the 30-tick start timer for the two extra logic ticks of C's catch-up frame.
func _reset_in_level(state: GameplayState, checkpoint: bool, events: Array[TickEvent]) -> String:
	if _candidate_entities != null:
		var entity_issue: String = _candidate_entities.reset_in_level(checkpoint, state.entity_environment, state.flow.gold_collected)
		if not entity_issue.is_empty():
			return entity_issue
		state.entities = _candidate_entities.snapshot()
		var sound_issue: String = _synchronize_sound_entities(state)
		if not sound_issue.is_empty():
			return sound_issue
	if state.sky_drift != null:
		state.sky_drift.clear()
	var start := RunStart.new()
	start.spawn_cell = state.frog.initial_cell
	start.spawn_direction = _default_direction
	start.start_mode = RunStart.Mode.FAST_RESET
	start.lives = state.frog.lives
	var prepared: Frog.StartResult = _frog.prepare_start(start, _default_cell, _default_direction)
	if not prepared.error.is_empty():
		return prepared.error
	var old: FrogState = state.frog
	state.frog = prepared.state.frog
	state.frog.velocity_16 = old.velocity_16
	state.frog.current_input = old.current_input
	state.frog.target_16 = old.target_16
	state.frog.buffered_direction = old.buffered_direction
	state.frog.user_target_cell = old.user_target_cell
	state.frog.animation_condition_counter = old.animation_condition_counter
	state.frog.no_input_timer = old.no_input_timer
	state.frog.scale = old.scale
	state.frog.scale_timer = old.scale_timer
	state.frog.death_count = old.death_count
	state.frog.death_equate = old.death_equate
	state.frog.croak_radius_max = old.croak_radius_max
	state.frog.croak_radius_min = old.croak_radius_min
	state.frog.croak_rate = old.croak_rate
	state.frog.start_timer = 30
	state.frog.start_timer_hold = 2
	state.frog.matrix12 = TerrainMatrix.update(PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, state.frog.world_position.x, state.frog.world_position.y, state.frog.world_position.z]), state.frog.flags, state.frog.direction, null)
	var primitive_transpose: CollisionTransposeCache = state.attachment.primitive_transpose
	state.attachment = AttachmentState.new()
	state.attachment.primitive_transpose = primitive_transpose
	_frog.sync_facts(state)
	state.tongue.reset()
	state.completed = false
	state.requests.life_decrement_requested = false
	state.requests.game_mode_request = -1
	state.flow.phase = LevelFlowState.Phase.PLAY
	state.flow.remaining_time = _level_time
	state.flow.elapsed_time = 0
	state.flow.timer_speed = 65536
	state.flow.timer_fraction = 0
	state.flow.timer_count_up = true
	state.flow.timeout_ticks = 60
	state.flow.bonus_stage = 0
	_update_camera_zone(state)
	if _candidate_animation != null:
		_candidate_animation.initialise(FrogAnimationCatalog.PANT)
		state.frog.no_input_timer = _candidate_animation.update_scripts(state.frog.no_input_timer)
		if not _candidate_animation.error.is_empty():
			return _candidate_animation.error
		state.animation = _candidate_animation.state.copy()
		state.frog.animation_condition_counter = _candidate_animation.context.if_counter
	if _camera_definition != null:
		_candidate_camera = GameplayCamera.create(_camera_definition, state.frog.world_position, true)
		if not _candidate_camera.error.is_empty():
			return _candidate_camera.error
		var input := GameplayCameraTick.new()
		input.frog_world = state.frog.world_position
		input.frog_mode = state.frog.mode
		input.old_y = state.frog.old_y
		input.target_y = state.frog.target_y
		input.start_timer = 30
		input.camera_zone = ZoneQueries.definition_for(_camera_zones, state.frog.camera_zone_index)
		var camera_issue: String = _candidate_camera.step(input)
		if not camera_issue.is_empty():
			return camera_issue
		state.camera = _candidate_camera.snapshot()
	if old.frog_collision_pose != null:
		state.frog.frog_collision_pose = old.frog_collision_pose.copy()
		var pose_issue: String = state.frog.frog_collision_pose.refresh(_entity_collision.frog_collision, state.animation.action, state.animation.cel, state.frog.matrix12)
		if not pose_issue.is_empty():
			return pose_issue
	events.append(TickEvent.transition(LevelFlowState.Phase.PLAY, state.flow.last_checkpoint if checkpoint else -1))
	return ""

func _failed_tick(result: TickResult, issue: String) -> TickResult:
	result.error = issue
	result.consumed_demo_byte = -1
	result.control_snapshot = null
	result.move_snapshot = null
	result.collision_snapshot = null
	result.camera_snapshot = null
	result.scripts_snapshot = null
	result.final_snapshot = null
	result.entity_contacts.clear()
	result.primitive_contacts.clear()
	result.events.clear()
	result.rng_consumers.clear()
	return result

func _sync_systems(state: GameplayState) -> void:
	if _has_entity_updates:
		_candidate_entities.set_contact_flags(state.attachment.entity_hit_indices, state.attachment.entity_carry_indices, state.entities)
	state.camera = _candidate_camera.snapshot() if _candidate_camera != null else null
	state.animation = _candidate_animation.state.copy() if _candidate_animation != null else null
	state.rng_state = _candidate_random.state
	state.diagnostics.rng_draw_count = _candidate_random.draw_count
	_frog.sync_facts(state)

func _check_guard(phase: TickGuard.Phase, state: GameplayState) -> String:
	return _tick_guard.check(phase, TickGuardCandidate.from_state(state, phase == TickGuard.Phase.ENTITY_UPDATE)) if _tick_guard != null else ""

func _apply_entity_sound(state: GameplayState, entity: EntitySnapshot, request: TickEvent) -> String:
	if state.sound == null:
		return ""
	var runtime := EntityScriptRuntime.new()
	runtime.state = state
	runtime.entity_index = entity.entity_index
	runtime.generation = entity.generation
	return runtime.sound(request, _candidate_random, _entity_sound_position(entity))

func _entity_sound_position(entity: EntitySnapshot) -> Vector3i:
	if entity.custom_state != null and entity.custom_state.swarm != null and entity.custom_state.mode != EntityHive.Mode.WAITING:
		var matrix: PackedInt32Array = entity.custom_state.swarm.matrix12
		return Vector3i(matrix[9], matrix[10], matrix[11])
	return Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])

func _synchronize_sound_entities(state: GameplayState) -> String:
	if state.sound == null:
		return ""
	state.sound.listener = Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
	state.sound.old_listener = state.sound.listener
	if state.entities == null:
		return ""
	var by_id: Dictionary[int, EntitySnapshot] = {}
	for entity: EntitySnapshot in state.entities.entities:
		by_id[entity.entity_index] = entity
	var previous: Array[LogicalMovingSound] = state.sound.moving.duplicate()
	for moving: LogicalMovingSound in previous:
		var entity: EntitySnapshot = by_id.get(moving.owner)
		if entity == null or not entity.live or entity.generation != moving.generation:
			state.sound.retire_moving(moving.owner)
		else:
			moving.position = _entity_sound_position(entity)
			moving.old_position = moving.position
	var ordered: Array[EntitySnapshot] = []
	for event: TickEvent in state.entities.lifecycle_events:
		if event.kind == TickEvent.Kind.CREATE and by_id.has(event.entity_index):
			ordered.append(by_id[event.entity_index])
	if state.tick_index == 0 and ordered.is_empty():
		ordered.assign(state.entities.entities)
	for entity: EntitySnapshot in ordered:
		if not entity.live or entity.custom_state == null or entity.custom_state.moving_sound.is_empty() or state.sound.moving_for(entity.entity_index) != null:
			continue
		var sound: PackedInt32Array = entity.custom_state.moving_sound
		var issue: String = _apply_entity_sound(state, entity, TickEvent.moving_sound(sound[0], sound[1], sound[2]))
		if not issue.is_empty():
			return issue
	return ""
