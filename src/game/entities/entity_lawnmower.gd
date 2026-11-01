class_name EntityLawnmower
extends RefCounted
## Suburbia lawnmower's mowing sound, one-shot frog chop and continuous path movement.

enum Mode { MOWING, CHOPPING, DO_NOTHING }

## Source SFX_SUB_MOWER and its PlayMovingSound radii.
const SOUND: int = 159
const SOUND_NEAR: int = 512
const SOUND_FAR: int = 1536
## Source SFX_SUB_FROG_MOWED, played as a 2D sound when the mower hits a frog.
const MOWED_SOUND: int = 156
## Frog offset along the mower's local Z axis while chopping.
const CHOP_OFFSET: int = 128

## Applies the source mode on the previous pose, then the moving update that never pauses the path.
static func update(_definition: EntityDefinition, result: EntityCustomResult, hit: bool, grid: GridDefinition = null) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.custom_state == null or entity.path == null:
		return "Lawnmower requires its path"
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.MOWING:
			if custom.moving_sound.is_empty():
				custom.moving_sound = PackedInt32Array([SOUND, SOUND_NEAR, SOUND_FAR])
				entity.requests.append(TickEvent.moving_sound(SOUND, SOUND_NEAR, SOUND_FAR))
			if hit:
				custom.mode = Mode.CHOPPING
				entity.requests.append(TickEvent.sound(MOWED_SOUND))
		Mode.CHOPPING:
			var offset: Vector3i = PlatformMath.apply(entity.matrix12, Vector3i(0, 0, CHOP_OFFSET))
			result.frog_matrix12 = entity.matrix12.duplicate()
			for axis: int in 3:
				result.frog_matrix12[9 + axis] = PlatformMath.s32(entity.matrix12[9 + axis] + PlatformMath.s16(offset[axis]))
			custom.mode = Mode.DO_NOTHING
	entity.matrix12 = EntityTransform.moving_on_land(entity.path, entity.entity_flags, grid)
	if entity.matrix12.is_empty():
		return "Lawnmower projected path requires a valid first terrain square"
	return ""
