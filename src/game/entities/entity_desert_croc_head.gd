class_name EntityDesertCrocHead
extends RefCounted
## Desert croc head rise, snap and sink cycle that bites carried frogs while deadly.

enum Mode { PAUSE3, RISE, PAUSE1, SNAP, PAUSE2, FALL }

const SNAP_SOUND: int = 62
const MUNCH_SOUND: int = 63
const SNAP_TICKS: int = 10
const SNAP_NEAR: int = 512
const SNAP_FAR: int = 1536

## Starts submerged and deadly, keeping the unsigned 16-bit start height and a one-shot head animation.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.PAUSE3
	custom.target.y = entity.matrix12[10] & 65535
	custom.count = 0
	custom.deadly = true
	if entity.animation != null:
		entity.animation.one_shot = true

## Advances one cycle step and bites the carried frog while deadly; moves only the matrix Y.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	var desert: EntityDesertDefinition = definition.desert
	if desert == null:
		return "Desert croc head requires rise, snap, pause and submerged operands"
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.lengths.is_empty():
		return "Desert croc head requires animation action zero"
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.PAUSE3:
			if _waited(custom, desert.submerged_delay):
				custom.mode = Mode.RISE
				custom.deadly = false
		Mode.RISE:
			entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] - desert.rise_speed)
			var top: int = custom.target.y - desert.rise_height
			if entity.matrix12[10] < top:
				entity.matrix12[10] = top
				custom.count = 0
				custom.mode = Mode.PAUSE1
		Mode.PAUSE1:
			if _waited(custom, desert.snap_delay):
				if desert.snap_flag == 1:
					custom.mode = Mode.SNAP
					custom.deadly = true
				else:
					custom.mode = Mode.PAUSE2
		Mode.SNAP:
			custom.count = (custom.count + 1) & 0xffffffff
			if custom.count == 1:
				entity.animation.select(0)
			if custom.count == SNAP_TICKS:
				custom.count = 0
				custom.mode = Mode.PAUSE2
				custom.deadly = false
				if custom.moving_sound.is_empty():
					custom.moving_sound = PackedInt32Array([SNAP_SOUND, SNAP_NEAR, SNAP_FAR])
					entity.requests.append(TickEvent.moving_sound(SNAP_SOUND, SNAP_NEAR, SNAP_FAR))
		Mode.PAUSE2:
			if _waited(custom, desert.pause_delay):
				custom.mode = Mode.FALL
		Mode.FALL:
			entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] + desert.rise_speed)
			if entity.matrix12[10] > custom.target.y:
				custom.mode = Mode.PAUSE3
				custom.deadly = true
	if custom.deadly and entity.live_flags & EntityLiveFlags.CARRIES_FROG_0:
		result.death_animation = FrogAnimationCatalog.BITTEN
		entity.requests.append(TickEvent.sound(MUNCH_SOUND))
	return ""

static func _waited(custom: EntityCustomState, delay: int) -> bool:
	custom.count = (custom.count + 1) & 0xffffffff
	if custom.count != delay:
		return false
	custom.count = 0
	return true
