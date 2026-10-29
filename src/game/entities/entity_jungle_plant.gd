class_name EntityJunglePlant
extends RefCounted
## Jungle snapping plant that waits for a nearby frog, snaps after a delay and repeats its snap sound.

enum Mode { WAITING, WAITING_TO_SNAP, SNAPPING, DELAY_AFTER_SNAPPING }

## Source JUN_PLANT_HIT_DISTANCE.
const HIT_DISTANCE: int = 356
const SNAP_SOUND: int = 93
const SNAP_SOUND_DISTANCE: int = 30
const SNAP_SOUND_INTERVAL: int = 15

## Clears the mode, timer and snap timer and selects cel zero.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.WAITING
	custom.timer = 0
	custom.count = 0
	if entity.animation != null:
		entity.animation.cel = 0

## Advances one plant step; custom.timer is the signed 16-bit jp_timer and custom.count the 32-bit jp_snap_timer.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	var jungle: EntityJungleDefinition = definition.jungle
	if jungle == null:
		return "Jungle plant requires its snap time and delay"
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.action < 0 or entity.animation.action >= entity.animation.lengths.size():
		return "Jungle plant requires its snapping animation"
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.WAITING:
			entity.animation.stepping = false
			if EntityFrogDistance.distance(entity.matrix12, Vector3i.ZERO, frog) < HIT_DISTANCE:
				custom.mode = Mode.WAITING_TO_SNAP
				custom.timer = jungle.snap_time
		Mode.WAITING_TO_SNAP:
			if _expired(custom):
				entity.animation.stepping = true
				custom.mode = Mode.SNAPPING
				_snap_sound(entity, frog)
				custom.count = SNAP_SOUND_INTERVAL
		Mode.SNAPPING:
			if entity.animation.finished():
				custom.mode = Mode.DELAY_AFTER_SNAPPING
				custom.timer = jungle.snap_delay
			_repeat_sound(entity, frog)
		Mode.DELAY_AFTER_SNAPPING:
			if _expired(custom):
				entity.animation.cel = 0
				entity.animation.stepping = false
				custom.mode = Mode.WAITING
			_repeat_sound(entity, frog)
	return ""

static func _expired(custom: EntityCustomState) -> bool:
	var previous: int = custom.timer
	custom.timer = PlatformMath.s16(previous - 1)
	return previous == 0

static func _repeat_sound(entity: EntitySnapshot, frog: GameplayState) -> void:
	var custom: EntityCustomState = entity.custom_state
	if custom.count == 0:
		_snap_sound(entity, frog)
		custom.count = SNAP_SOUND_INTERVAL
	else:
		custom.count -= 1

static func _snap_sound(entity: EntitySnapshot, frog: GameplayState) -> void:
	if EntityDistanceSound.within(Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]), frog, SNAP_SOUND_DISTANCE):
		entity.requests.append(TickEvent.sound(SNAP_SOUND))
