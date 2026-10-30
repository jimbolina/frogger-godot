class_name EntitySwampPress
extends RefCounted
## Swamp vertical press that waits its delay, then stamps up and down with crush sounds.

## Source SWAMP_PRESS_MOVING_UP and SWAMP_PRESS_MOVING_DOWN runtime directions.
const MOVING_UP: int = 0
const MOVING_DOWN: int = 1
## Source authored SWAMP_PRESS_UP and SWAMP_PRESS_DOWN directions, then the WAITING and CRUSHING actions.
const UP: int = 0
const DOWN: int = 1
const WAITING: int = 2
const CRUSHING: int = 3
## Source WORLD_SHIFT applied to the authored speed.
const WORLD_SHIFT: int = 8
## Source SFX_SWP_MACHINE and its PlayMovingSound radii.
const SOUND: int = 124
const SOUND_NEAR: int = 768
const SOUND_FAR: int = 1280
## Source SFX_SWP_FROG_CRUSH, SFX_SWP_CRUSHER and SWP_PRESS_DISTANCE.
const FROG_CRUSH_SOUND: int = 123
const CRUSH_SOUND: int = 105
const CRUSH_DISTANCE: int = 1536

## Copies the authored matrix, loads the unsigned delay and starts the moving sound.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = definition.matrix12.duplicate()
	var custom: EntityCustomState = entity.custom_state
	custom.direction = MOVING_UP
	custom.timer = (definition.swamp.delay & 0xffff) if definition.swamp != null else 0
	custom.mode = WAITING
	custom.moving_sound = PackedInt32Array([SOUND, SOUND_NEAR, SOUND_FAR])

## Advances one press step; custom.direction, custom.timer and custom.mode are the unsigned
## 16-bit pr_direction, pr_time and pr_action. Returning to the authored height plays the
## frog-crush sound while carrying a frog, else the crusher sound strictly inside its distance.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	var swamp: EntitySwampDefinition = definition.swamp
	if swamp == null:
		return "Swamp press requires its speed, distance, direction and delay"
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	if custom.mode == WAITING:
		var previous: int = custom.timer
		custom.timer = (previous - 1) & 0xffff
		if previous == 0:
			custom.mode = CRUSHING
		return ""
	var polarity: int = 0
	match swamp.direction:
		UP:
			polarity = -1
		DOWN:
			polarity = 1
		_:
			return ""
	var step: int = swamp.speed >> WORLD_SHIFT
	var origin: int = definition.matrix12[10]
	if custom.direction == MOVING_UP:
		entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] + polarity * step)
		var limit: int = origin + polarity * swamp.distance
		if (entity.matrix12[10] > limit) if polarity > 0 else (entity.matrix12[10] < limit):
			custom.direction = MOVING_DOWN
		return ""
	entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] - polarity * step)
	if (entity.matrix12[10] < origin) if polarity > 0 else (entity.matrix12[10] > origin):
		custom.direction = MOVING_UP
		if entity.live_flags & EntityLiveFlags.CARRIES_FROG:
			entity.requests.append(TickEvent.sound(FROG_CRUSH_SOUND))
		elif EntityFrogDistance.distance(entity.matrix12, Vector3i.ZERO, frog) < CRUSH_DISTANCE:
			entity.requests.append(TickEvent.sound(CRUSH_SOUND))
	return ""
