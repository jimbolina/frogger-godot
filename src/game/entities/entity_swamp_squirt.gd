class_name EntitySwampSquirt
extends RefCounted
## Swamp acid drip that waits once, then falls from its matrix to its target and snaps back forever.

enum Mode { WAITING, FALL_PREPARE, FALLING }

## Source SFX_SWP_ACID_DRIP and SWP_SQUIRT_DISTANCE.
const DRIP_SOUND: int = 114
const DRIP_DISTANCE: int = 1536

## Copies the authored matrix, loads the signed once-off delay and clears the velocity.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = definition.matrix12.duplicate()
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.WAITING
	custom.timer = PlatformMath.s16(definition.swamp.time_delay) if definition.swamp != null else 0
	custom.velocity_16 = Vector3i.ZERO

## Advances one squirt step; custom.timer is the signed 16-bit sq_curr_time and
## custom.velocity_16 the signed 32-bit 16.16 sq_velocity.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	var swamp: EntitySwampDefinition = definition.swamp
	if swamp == null:
		return "Swamp squirt requires its delay, drop time and target"
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.WAITING:
			if custom.timer > 0:
				custom.timer = PlatformMath.s16(custom.timer - 1)
			else:
				custom.mode = Mode.FALL_PREPARE
		Mode.FALL_PREPARE:
			if swamp.drop_time == 0:
				return "Swamp squirt has zero drop time"
			var velocity := Vector3i.ZERO
			for axis: int in 3:
				var position: int = PlatformMath.s32(entity.matrix12[9 + axis] << 16)
				velocity[axis] = PlatformMath.divide(PlatformMath.s32((swamp.target[axis] << 16) - position), swamp.drop_time)
			custom.velocity_16 = velocity
			custom.timer = PlatformMath.s16(swamp.drop_time)
			custom.mode = Mode.FALLING
			if EntityFrogDistance.distance(entity.matrix12, Vector3i.ZERO, frog) < DRIP_DISTANCE:
				entity.requests.append(TickEvent.sound(DRIP_SOUND))
		Mode.FALLING:
			for axis: int in 3:
				entity.matrix12[9 + axis] = PlatformMath.s32(entity.matrix12[9 + axis] + (custom.velocity_16[axis] >> 16))
			var previous: int = custom.timer
			custom.timer = PlatformMath.s16(previous - 1)
			if previous <= 0:
				custom.mode = Mode.FALL_PREPARE
				entity.matrix12 = definition.matrix12.duplicate()
		_:
			return "Swamp squirt has an unknown action"
	return ""
