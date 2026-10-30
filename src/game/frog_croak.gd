class_name FrogCroak
extends RefCounted
## Frozen single-player croak: throat scale, cave light swell and the nearest checkpoint's answer.

## Source FROG_CROAK_* modes.
enum Mode { NONE, INFLATE, HOLD, DEFLATE }

const INFLATE_TIME: int = 6
const HOLD_TIME: int = 4
const DEFLATE_TIME: int = 6
## Source FROG_CROAK_MIN_SCALE; the scale grows by SCALE_RANGE over the inflation.
const MIN_SCALE: int = 0x200
const SCALE_RANGE: int = 0xA00
## Source FROG_CROAK_TARGET_RADIUS2: sixteen grid squares squared.
const TARGET_RADIUS_SQUARED: int = (16 * 0x100) * (16 * 0x100)
const SOUND_CROAK: int = 3
const SOUND_BABY_FROG: int = 16
const SOUND_GOLD_FROG_CROAK: int = 18
const UNSIGNED32: int = 0xffffffff

## Source FrogUpdateCroak (FROG.C:2941-3042), run at the end of ControlFrog every tick.
## Recorded demos skip the whole update, as GAME_FLAG_DEMO_RUNNING does.
static func update(frog: Frog, state: GameplayState, command: TickCommand, events: Array[TickEvent]) -> String:
	if command.recorded_input_byte >= 0 or command.recorded_input_exhausted:
		return ""
	var frog_state: FrogState = state.frog
	var environment: EntityEnvironmentState = state.entity_environment
	match frog_state.croak_mode:
		Mode.NONE:
			if frog_state.flags & FrogFlags.CONTROL_ACTIVE and frog_state.mode != FrogMode.HIT_CHECKPOINT and command.pressed_mask & TickCommand.CROAK:
				frog_state.croak_mode = Mode.INFLATE
				frog_state.croak_timer = INFLATE_TIME
				frog_state.croak_radius_max = environment.light_max_squared if environment != null else 0
				frog_state.croak_radius_min = environment.light_min_squared if environment != null else 0
				@warning_ignore("integer_division")
				frog_state.croak_rate = frog_state.croak_radius_max / INFLATE_TIME
				if environment != null:
					environment.light_switch = false
				var issue: String = frog.play_sound(state, SOUND_CROAK)
				if not issue.is_empty():
					return issue
				state.requests.sound_requests += 1
				events.append(TickEvent.make(TickEvent.Kind.CROAK))
		Mode.INFLATE:
			frog_state.croak_timer -= 1
			_shift_light(environment, frog_state.croak_rate)
			@warning_ignore("integer_division")
			frog_state.croak_scale = ((INFLATE_TIME - frog_state.croak_timer) * SCALE_RANGE) / INFLATE_TIME + MIN_SCALE
			if frog_state.croak_timer == 0:
				frog_state.croak_mode = Mode.HOLD
				frog_state.croak_timer = HOLD_TIME
		Mode.HOLD:
			frog_state.croak_timer -= 1
			if frog_state.croak_timer == 0:
				frog_state.croak_mode = Mode.DEFLATE
				frog_state.croak_timer = DEFLATE_TIME
		Mode.DEFLATE:
			frog_state.croak_timer -= 1
			_shift_light(environment, -frog_state.croak_rate)
			@warning_ignore("integer_division")
			frog_state.croak_scale = (frog_state.croak_timer * SCALE_RANGE) / DEFLATE_TIME + MIN_SCALE
			if frog_state.croak_timer == 0:
				frog_state.croak_mode = Mode.NONE
				if environment != null:
					environment.light_switch = true
					environment.light_max_squared = frog_state.croak_radius_max
					environment.light_min_squared = frog_state.croak_radius_min
				return _answer(frog, state, events)
	return ""

## Source FrogGetNearestCheckpoint (FROG.C:3066-3105): the closest uncollected checkpoint within
## TARGET_RADIUS_SQUARED of the frog translation, replaced by an uncollected gold frog that is
## closer still. Returns the selected definition, or null.
static func nearest_checkpoint(frog: Frog, state: GameplayState) -> EntityDefinition:
	var environment: EntityEnvironmentState = state.entity_environment
	if environment == null or frog.entity_collision == null:
		return null
	var translation := Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
	var result: EntityDefinition = null
	var closest: int = TARGET_RADIUS_SQUARED
	for index: int in environment.checkpoint_positions.size():
		if environment.collected & (1 << index):
			continue
		var checkpoint: EntityDefinition = _checkpoint_definition(frog, index)
		if checkpoint == null:
			continue
		var distance: int = _distance_squared(environment.checkpoint_positions[index], translation)
		if distance < closest:
			result = checkpoint
			closest = distance
	if not state.flow.gold_collected:
		for definition: EntityDefinition in frog.entity_collision.entities:
			if definition.behavior.kind != EntityBehavior.Kind.GOLD_FROG:
				continue
			var position := Vector3i(definition.matrix12[9], definition.matrix12[10], definition.matrix12[11])
			if _distance_squared(position, translation) < closest:
				result = definition
			break
	return result

## Returns the source cp_id of a checkpoint definition: its form identity, less 11 for multipoints.
static func checkpoint_id(definition: EntityDefinition) -> int:
	var index: int = definition.form_id & 32767
	return index - 11 if index > 4 else index

static func _answer(frog: Frog, state: GameplayState, events: Array[TickEvent]) -> String:
	var target: EntityDefinition = nearest_checkpoint(frog, state)
	if target == null:
		return ""
	var sound_id: int = SOUND_GOLD_FROG_CROAK
	if target.behavior.kind != EntityBehavior.Kind.GOLD_FROG:
		var index: int = checkpoint_id(target)
		state.entity_environment.croak_modes[index] = Mode.INFLATE
		sound_id = SOUND_BABY_FROG
	var entity: EntitySnapshot = _live_entity(state, target.entity_index)
	if entity == null:
		return ""
	var request: TickEvent = TickEvent.moving_sound(sound_id, -1, -1)
	if state.sound != null:
		var runtime := EntityScriptRuntime.new()
		runtime.state = state
		runtime.entity_index = entity.entity_index
		runtime.generation = entity.generation
		var issue: String = runtime.sound(request, frog.random, Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]))
		if not issue.is_empty():
			return issue
	events.append(request.for_entity(entity.entity_index))
	return ""

static func _checkpoint_definition(frog: Frog, index: int) -> EntityDefinition:
	for definition: EntityDefinition in frog.entity_collision.entities:
		if definition.behavior.kind == EntityBehavior.Kind.CHECKPOINT and checkpoint_id(definition) == index:
			return definition
	return null

static func _live_entity(state: GameplayState, entity_index: int) -> EntitySnapshot:
	if state.entities == null:
		return null
	for entity: EntitySnapshot in state.entities.entities:
		if entity.entity_index == entity_index:
			return entity if entity.live else null
	return null

static func _shift_light(environment: EntityEnvironmentState, delta: int) -> void:
	if environment == null:
		return
	environment.light_max_squared = (environment.light_max_squared + delta) & UNSIGNED32
	environment.light_min_squared = (environment.light_min_squared + delta) & UNSIGNED32

static func _distance_squared(position: Vector3i, translation: Vector3i) -> int:
	var delta: Vector3i = position - translation
	return PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
