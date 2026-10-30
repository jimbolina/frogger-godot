class_name EntitySwampRat
extends RefCounted
## Swamp rat that jumps in a sine arc, rolls, runs and jumps again between four authored targets.

## Source SWAMP_RAT_MODE_* values held in custom.mode.
enum Mode { INIT_FIRST_JUMP, JUMP1, INIT_ROLL, ROLL, RUN, JUMP2, RESTART }
## Source SWAMP_RAT_ANIM_* actions.
enum Action { RUN, JUMP, ROLL }

## Source roll length in frames before the run starts.
const ROLL_FRAMES: int = 24
## Source jump arc height in world units, scaled by the sine of the jump position.
const JUMP_HEIGHT: int = 250
## Source Y at or above which the second jump splashes; world Y points down, so this is lower.
const SPLASH_HEIGHT: int = -255
const SCALE_COLOUR: int = 128
const SPLASH_AMBIENT: Vector3i = Vector3i(255, 0, 255)
const NORMAL_AMBIENT: Vector3i = Vector3i(255, 255, 255)

## Source ENTSTRSwpCreateRat: the authored matrix with its translation at the start target, the
## <<4 position there and the restart mode that the first update resolves.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = definition.matrix12.duplicate()
	var custom: EntityCustomState = entity.custom_state
	if definition.swamp == null or definition.swamp.rat_targets.size() != 4 or custom == null:
		return
	var start: Vector3i = definition.swamp.rat_targets[0]
	entity.matrix12[9] = start.x
	entity.matrix12[10] = start.y
	entity.matrix12[11] = start.z
	custom.previous_y = start.y
	custom.mode = Mode.RESTART
	custom.position_4 = Vector3i(start.x << 4, start.y << 4, start.z << 4)

## Source ENTSTRSwpUpdateRat: one mode step, then the translation becomes the arithmetic >>4 of
## the fixed-point position. custom.count is the unsigned 16-bit ra_count. The second jump's
## splash requests the water splash sprite at the >>4 position, as Rat_splash_matrix does.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	var swamp: EntitySwampDefinition = definition.swamp
	if swamp == null or swamp.rat_targets.size() != 4:
		return "Swamp rat requires its speed and four targets"
	if swamp.jump1_time == 0 or swamp.run_time == 0 or swamp.jump2_time == 0:
		return "Swamp rat requires nonzero jump and run durations"
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.lengths.size() < EntitySwampDefinition.RAT_ACTIONS:
		return "Swamp rat requires its run, jump and roll actions"
	var custom: EntityCustomState = entity.custom_state
	if custom == null:
		return "Swamp rat requires its custom state"
	match custom.mode:
		Mode.INIT_FIRST_JUMP:
			_set_action(entity, Action.JUMP, true)
			custom.count = 0
			custom.sine_positions = Vector2i.ZERO
			custom.previous_y = custom.position_4.y
			custom.mode = Mode.JUMP1
		Mode.JUMP1:
			_jump(custom, swamp.jump1_velocity_4, custom.sine_positions.x)
			custom.sine_positions.x = PlatformMath.s32(custom.sine_positions.x + swamp.jump1_sine_step)
			custom.count = (custom.count + 1) & 65535
			if custom.count == swamp.jump1_time:
				custom.mode = Mode.INIT_ROLL
		Mode.INIT_ROLL:
			_set_action(entity, Action.ROLL, true)
			custom.count = 0
			custom.mode = Mode.ROLL
		Mode.ROLL:
			custom.count = (custom.count + 1) & 65535
			if custom.count == ROLL_FRAMES:
				_set_action(entity, Action.RUN, false)
				custom.count = 0
				custom.mode = Mode.RUN
		Mode.RUN:
			var velocity: Vector3i = swamp.run_velocity_4
			custom.position_4 = Vector3i(PlatformMath.s32(custom.position_4.x + velocity.x), PlatformMath.s32(custom.position_4.y + velocity.y), PlatformMath.s32(custom.position_4.z + velocity.z))
			custom.count = (custom.count + 1) & 65535
			if custom.count == swamp.run_time:
				_set_action(entity, Action.JUMP, true)
				custom.count = 0
				custom.previous_y = custom.position_4.y
				custom.mode = Mode.JUMP2
		Mode.JUMP2:
			_jump(custom, swamp.jump2_velocity_4, custom.sine_positions.y)
			if custom.position_4.y >> 4 >= SPLASH_HEIGHT and not custom.splashed:
				custom.splashed = true
				EntityScaleColours.apply(entity, definition.form_flags, SCALE_COLOUR)
				_custom_ambient(entity, SPLASH_AMBIENT)
				entity.requests.append(TickEvent.splash(Vector3i(custom.position_4.x >> 4, custom.position_4.y >> 4, custom.position_4.z >> 4)))
			custom.sine_positions.y = PlatformMath.s32(custom.sine_positions.y + swamp.jump2_sine_step)
			custom.count = (custom.count + 1) & 65535
			if custom.count == swamp.jump2_time:
				custom.mode = Mode.RESTART
		Mode.RESTART:
			var start: Vector3i = swamp.rat_targets[0]
			custom.position_4 = Vector3i(start.x << 4, start.y << 4, start.z << 4)
			EntityScaleColours.apply(entity, definition.form_flags, SCALE_COLOUR)
			_custom_ambient(entity, NORMAL_AMBIENT)
			custom.splashed = false
			custom.previous_y = custom.position_4.y
			custom.mode = Mode.INIT_FIRST_JUMP
	entity.matrix12[9] = custom.position_4.x >> 4
	entity.matrix12[10] = custom.position_4.y >> 4
	entity.matrix12[11] = custom.position_4.z >> 4
	return ""

static func _jump(custom: EntityCustomState, velocity: Vector3i, sine_position: int) -> void:
	var y: int = PlatformMath.s32(custom.previous_y + velocity.y)
	custom.previous_y = y
	var lift: int = (EntityBonusFly.sine(sine_position) * JUMP_HEIGHT >> 12) << 4
	custom.position_4 = Vector3i(PlatformMath.s32(custom.position_4.x + velocity.x), PlatformMath.s32(y - lift), PlatformMath.s32(custom.position_4.z + velocity.z))

static func _set_action(entity: EntitySnapshot, action: Action, one_shot: bool) -> void:
	entity.animation.select(action)
	entity.animation.one_shot = one_shot

static func _custom_ambient(entity: EntitySnapshot, colour: Vector3i) -> void:
	if entity.live_flags & EntityLiveFlags.RESPECT_AMBIENT_COLOURS:
		var ambient: Vector3i = entity.ambient
		entity.ambient = Vector3i((ambient.x * colour.x >> 7) & 255, (ambient.y * colour.y >> 7) & 255, (ambient.z * colour.z >> 7) & 255)
	else:
		entity.ambient = colour
