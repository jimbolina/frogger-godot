class_name EntityCaveFade
extends RefCounted
## Frozen FadeLiveEntity cave ramp and SetLiveEntityScaleColours policy.

const FORM_NO_MODEL: int = 1
const FORM_NO_COLOUR_FADE: int = 256

## Grey level from the XZ squared distance against unsigned radii; nominally 0..128.
static func colour(entity_position: Vector3i, frog_position: Vector3i, light_min: int, light_max: int) -> int:
	var x_distance: int = PlatformMath.s32(frog_position.x - entity_position.x)
	var z_distance: int = PlatformMath.s32(frog_position.z - entity_position.z)
	var squared: int = (x_distance * x_distance + z_distance * z_distance) & 0xffffffff
	var minimum: int = light_min & 0xffffffff
	var maximum: int = light_max & 0xffffffff
	if squared <= minimum:
		return 128
	if squared >= maximum:
		return 0
	var offset: int = PlatformMath.s32(squared - minimum)
	var fall: int = PlatformMath.divide(128 << 16, PlatformMath.s32(maximum - minimum))
	return maxi(0, 128 - (PlatformMath.s32(offset * fall) >> 16))

## Applies the model or sprite colour-scale rule to one live snapshot.
static func apply(entity: EntitySnapshot, definition: EntityDefinition, col: int) -> void:
	if entity.entity_flags & EntityDefinition.NO_DISPLAY:
		return
	if not entity.live_flags & EntityLiveFlags.ANIMATED and definition.form_flags & FORM_NO_MODEL:
		if definition.form_flags & FORM_NO_COLOUR_FADE or entity.live_flags & EntityLiveFlags.NO_COLOUR_FADE:
			return
		var level: int = mini(128, PlatformMath.s32(col << 2)) & 255
		entity.colour_scale = Vector3i(level, level, level)
	elif entity.live_flags & EntityLiveFlags.RESPECT_SCALE_COLOURS:
		var scale: Vector3i = entity.colour_scale
		entity.colour_scale = Vector3i((scale.x * col >> 7) & 255, (scale.y * col >> 7) & 255, (scale.z * col >> 7) & 255)
	else:
		var packed: int = ((col << 16) + (col << 8) + col) & 0xffffffff
		entity.colour_scale = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
	entity.colour_scaled = true
