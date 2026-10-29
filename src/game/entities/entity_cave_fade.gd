class_name EntityCaveFade
extends RefCounted
## Frozen FadeLiveEntity cave ramp and its displayed-entity colour-scale gate.

const FORM_NO_MODEL: int = EntityScaleColours.FORM_NO_MODEL
const FORM_NO_COLOUR_FADE: int = EntityScaleColours.FORM_NO_COLOUR_FADE

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

## Applies the shared colour-scale rule to one displayed live snapshot.
static func apply(entity: EntitySnapshot, definition: EntityDefinition, col: int) -> void:
	if entity.entity_flags & EntityDefinition.NO_DISPLAY:
		return
	EntityScaleColours.apply(entity, definition.form_flags, col)
