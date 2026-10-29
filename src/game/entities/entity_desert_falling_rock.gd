class_name EntityDesertFallingRock
extends RefCounted
## Frozen Desert falling rock: delay, gravity arcs between resolved targets, explosion and reset.

## Source DES_C_ACTION_FALLING_ROCK_* order; START is declared by the source but never entered.
enum Mode { CHECKING, DELAY, START, TARGETS, EXPLODE, EXPLODING }

## Source DES_ROCK_RADIUS lift of the drawn translation above the integrated position.
const RADIUS: int = 0x80
## Source fr_rotation step about the local X axis per TARGETS update.
const ROLL_STEP: int = 0x60
## Source SFX_DES_ROCK_BOUNCE and SFX_DES_ROCK_BREAK flat sound ids.
const BOUNCE_SOUND: int = 50
const BREAK_SOUND: int = 51
## Source PlaySoundDistance range for both rock sounds.
const SOUND_DISTANCE: int = 30

## Source ENTSTRDesCreateFallingRock: authored matrix, 16.16 map position, zero velocity, CHECKING.
## The source leaves fr_rotation and fr_curr_time uninitialized; both start at zero here.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	if entity.custom_state == null:
		entity.custom_state = EntityCustomState.new()
	var custom: EntityCustomState = entity.custom_state
	entity.matrix12 = definition.matrix12.duplicate()
	custom.offset_16 = _origin_16(definition)
	custom.velocity_16 = Vector3i.ZERO
	custom.mode = Mode.CHECKING
	custom.count = 0
	custom.timer = 0
	custom.direction = 0
	custom.overlay_animation = null
	custom.model_hidden = false
	custom.shadow_visible = false

## Source ENTSTRDesFallingRockCalculateInitialVelocity: u = (s - 1/2 a t^2) / t with truncating
## signed 32-bit division, and Y reduced by WORLD_GRAVITY * (t >> 1).
static func initial_velocity(position_16: Vector3i, target: Vector3i, time: int) -> Vector3i:
	var vx: int = PlatformMath.divide(PlatformMath.s32((target.x << 16) - position_16.x), time)
	var vy: int = PlatformMath.divide(PlatformMath.s32((target.y << 16) - position_16.y), time)
	var vz: int = PlatformMath.divide(PlatformMath.s32((target.z << 16) - position_16.z), time)
	return Vector3i(PlatformMath.s32(vx), PlatformMath.s32(vy - PlatformMath.s32(EntityVelocity.WORLD_GRAVITY * (time >> 1))), PlatformMath.s32(vz))

## TARGETS rotation: forward axes from the whole-unit velocity, then MRMulMatrixABA by Rot_X(angle).
## Returns twelve entries with zero translation.
static func pose(velocity_16: Vector3i, angle: int) -> PackedInt32Array:
	var axes: PackedInt32Array = EntityTransform.from_forward(Vector3i(velocity_16.x >> 16, velocity_16.y >> 16, velocity_16.z >> 16))
	return PlatformMath.rotate_x(axes, angle)

## Source ENTSTRDesUpdateFallingRock for one tick. Requires resolved targets and the explosion
## flipbook; on error nothing is changed. Rock sounds pass the PlaySoundDistance gate for frog.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	var issue: String = _validate(definition, result.entity)
	if not issue.is_empty():
		return issue
	var desert: EntityDesertDefinition = definition.desert
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.CHECKING:
			custom.timer = desert.rock_delay & 65535
			custom.mode = Mode.DELAY
			custom.shadow_visible = true
		Mode.DELAY:
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 65535
			if expired:
				_launch(desert, custom)
				custom.mode = Mode.TARGETS
				custom.model_hidden = false
				custom.shadow_visible = true
		Mode.TARGETS:
			EntityVelocity.step(entity, custom)
			entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] - RADIUS)
			custom.direction = (custom.direction - ROLL_STEP) & 4095
			var matrix: PackedInt32Array = pose(custom.velocity_16, custom.direction)
			for axis: int in 3:
				matrix[9 + axis] = entity.matrix12[9 + axis]
			entity.matrix12 = matrix
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 65535
			if expired:
				custom.count += 1
				var sound: int = BREAK_SOUND
				if custom.count < desert.rock_bounces:
					var landed: Vector3i = desert.rock_targets[custom.count - 1]
					custom.offset_16.x = PlatformMath.s32(landed.x << 16)
					custom.offset_16.z = PlatformMath.s32(landed.z << 16)
					_launch(desert, custom)
					sound = BOUNCE_SOUND
				else:
					custom.mode = Mode.EXPLODE
				var origin := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
				if EntityDistanceSound.within(origin, frog, SOUND_DISTANCE):
					entity.requests.append(TickEvent.sound(sound, origin))
			custom.shadow_visible = true
		Mode.EXPLODE:
			EntityDesertExplosion.start(entity, desert.explosion_action_lengths, Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]))
			for index: int in 9:
				entity.matrix12[index] = EntityTransform.IDENTITY[index]
			custom.mode = Mode.EXPLODING
			custom.shadow_visible = false
		Mode.EXPLODING:
			if not EntityDesertExplosion.done(custom):
				return ""
			custom.timer = 0
			custom.mode = Mode.DELAY
			custom.count = 0
			EntityDesertExplosion.finish(custom, false)
			custom.offset_16 = _origin_16(definition)
			for axis: int in 3:
				entity.matrix12[9 + axis] = definition.matrix12[9 + axis]
	return ""

static func _launch(desert: EntityDesertDefinition, custom: EntityCustomState) -> void:
	var time: int = desert.rock_times[custom.count]
	custom.velocity_16 = initial_velocity(custom.offset_16, desert.rock_targets[custom.count], time)
	custom.timer = time & 65535

static func _origin_16(definition: EntityDefinition) -> Vector3i:
	return Vector3i(PlatformMath.s32(definition.matrix12[9] << 16), PlatformMath.s32(definition.matrix12[10] << 16), PlatformMath.s32(definition.matrix12[11] << 16))

static func _validate(definition: EntityDefinition, entity: EntitySnapshot) -> String:
	var desert: EntityDesertDefinition = definition.desert
	if desert == null:
		return "Falling rock requires decoded Desert rock operands"
	if entity == null or entity.custom_state == null:
		return "Falling rock requires initialized custom state"
	if definition.matrix12.size() != 12 or entity.matrix12.size() != 12:
		return "Falling rock requires a twelve-entry matrix"
	if not desert.rock_targets_resolved:
		return "Falling rock targets must be projected onto the landscape before update"
	var limit: int = mini(desert.rock_targets.size(), desert.rock_times.size())
	if desert.rock_bounces < 1 or desert.rock_bounces > limit:
		return "Falling rock requires 1 to %d bounces with targets and times, got %d" % [limit, desert.rock_bounces]
	for index: int in desert.rock_bounces:
		if desert.rock_times[index] <= 0 or desert.rock_times[index] > 65535:
			return "Falling rock target %d time must be 1 to 65535, got %d" % [index, desert.rock_times[index]]
	if not EntityDesertExplosion.valid(desert.explosion_action_lengths):
		return "Falling rock requires an explosion flipbook with a nonempty first action"
	var custom: EntityCustomState = entity.custom_state
	if custom.mode < Mode.CHECKING or custom.mode > Mode.EXPLODING or custom.mode == Mode.START:
		return "Falling rock has an unknown mode %d" % custom.mode
	var landed: bool = custom.mode == Mode.EXPLODE or custom.mode == Mode.EXPLODING
	if custom.count < 0 or custom.count > desert.rock_bounces or (custom.count == desert.rock_bounces and not landed):
		return "Falling rock bounce index %d is outside its %d targets" % [custom.count, desert.rock_bounces]
	if custom.mode == Mode.EXPLODING and custom.overlay_animation == null:
		return "Exploding falling rock has no explosion flipbook"
	return ""
