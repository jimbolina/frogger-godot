class_name EntityBonusFly
extends RefCounted
## Generic pickup creation, source frame bobbing and allocated-voice pitch changes.

const REWARD_IDS: PackedInt32Array = [1, 2, 3, 5, 7, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]

## Creates the logical particle pickup and its initially voiceless moving sound.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = EntityTransform.IDENTITY.duplicate()
	for axis: int in 3:
		entity.matrix12[9 + axis] = definition.matrix12[9 + axis]
	entity.animation = null
	entity.live_flags = EntityLiveFlags.NO_COLOUR_FADE
	var sound: int = 44 if definition.pickup_type == 8 else 21
	entity.custom_state.moving_sound = PackedInt32Array([sound, 256, 768])
	entity.custom_state.moving_voice_active = false
	entity.requests.append(TickEvent.moving_sound(sound, 256, 768))

## Advances a detached pickup; only a logically allocated voice consumes pitch RNG.
static func update(definition: EntityDefinition, result: EntityCustomResult, frame_number: int) -> void:
	var entity: EntitySnapshot = result.entity
	if entity.entity_flags & EntityDefinition.NO_MOVEMENT:
		return
	var angle: int = (((definition.unique_id & 7) << 7) + ((frame_number & 65535) << 6)) & 4095
	entity.matrix12[10] = definition.matrix12[10] + (sine(angle) >> 6) + 64
	if not entity.custom_state.moving_sound.is_empty() and entity.custom_state.moving_voice_active:
		var pitch: int = 64 - (result.random.next_value("entity:%d:pickup_pitch_base" % definition.entity_index) & 15)
		pitch += (result.random.next_value("entity:%d:pickup_pitch_mod" % definition.entity_index) & 3) * 8
		pitch -= sine(frame_number << 8) >> 8
		entity.requests.append(TickEvent.pitch_bend(pitch))

## Port approximation of the source rsin table shared by pickup-style bobbing.
static func sine(angle: int) -> int:
	return roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
