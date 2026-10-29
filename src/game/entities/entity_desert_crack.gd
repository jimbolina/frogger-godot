class_name EntityDesertCrack
extends RefCounted
## Desert crack hop counter, one-shot opening, rider drop and darkening sink.

enum Mode { WAITING_FOR_HITS, WAITING_TO_FALL, FALLING, FINISHED }

const ANIMATED_TEXTURES: int = 3
const CRACK_SOUND: int = 48
const HOLE_SOUND: int = 53
const HOLE_DISTANCE: int = 30
const OPEN_WAIT: int = 2
const SINK_ACCELERATION_16: int = (Frog.GRAVITY_16 * 5) >> 2
const SINK_LIMIT: int = 1024
const COLOUR_BASE: int = 0x80

## Holds cel 0 without stepping and enables collision for a fresh crack.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.WAITING_FOR_HITS
	custom.timer = 0
	custom.count = 0
	custom.velocity_16.y = 0
	if entity.animation != null:
		entity.animation.stepping = false
		entity.animation.cel = 0
	entity.entity_flags &= ~EntityDefinition.NO_COLLISION

## Advances one crack from the previous tick's HIT; moves only the matrix Y.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool) -> String:
	var desert: EntityDesertDefinition = definition.desert
	if desert == null:
		return "Desert crack requires its hop count"
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.action < 0 or entity.animation.action >= entity.animation.lengths.size():
		return "Desert crack requires its opening flipbook"
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.WAITING_FOR_HITS:
			if hit:
				custom.texture_animation_cel = (ANIMATED_TEXTURES - (desert.hops_before - custom.count)) & 65535
				custom.count = (custom.count + 1) & 255
				entity.requests.append(TickEvent.sound(CRACK_SOUND))
				if custom.count >= desert.hops_before:
					custom.timer = OPEN_WAIT
					custom.mode = Mode.WAITING_TO_FALL
		Mode.WAITING_TO_FALL:
			custom.timer = (custom.timer - 1) & 65535
			if custom.timer != 0:
				entity.animation.stepping = true
				entity.animation.one_shot = true
				if EntityDistanceSound.within(Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]), frog, HOLE_DISTANCE):
					entity.requests.append(TickEvent.sound(HOLE_SOUND))
				custom.mode = Mode.FALLING
				custom.offset_16.y = PlatformMath.s32(entity.matrix12[10] << 16)
		Mode.FALLING:
			if not entity.animation.finished():
				return ""
			if custom.timer > 0:
				custom.timer = (custom.timer - 1) & 65535
				if custom.timer == 0:
					entity.entity_flags |= EntityDefinition.NO_COLLISION
					result.frog_fall_requested = frog != null and frog.attachment.current_entity_index == entity.entity_index
				return ""
			custom.velocity_16.y = PlatformMath.s32(custom.velocity_16.y + SINK_ACCELERATION_16)
			if entity.matrix12[10] < SINK_LIMIT:
				custom.offset_16.y = PlatformMath.s32(custom.offset_16.y + custom.velocity_16.y)
				entity.matrix12[10] = custom.offset_16.y >> 16
			else:
				custom.mode = Mode.FINISHED
			entity.live_flags |= EntityLiveFlags.NO_SCREEN_FADE
			var colour: int = maxi(0, (PlatformMath.s32(definition.matrix12[10] - entity.matrix12[10]) >> 3) + COLOUR_BASE)
			EntityScaleColours.apply(entity, definition.form_flags, colour)
	return ""
