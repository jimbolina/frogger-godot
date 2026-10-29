class_name EntityScaleColours
extends RefCounted
## Frozen SetLiveEntityScaleColours model and sprite colour-scale policy.

const FORM_NO_MODEL: int = 1
const FORM_NO_COLOUR_FADE: int = 256

## Applies one grey level to a live snapshot using its form-book flags.
static func apply(entity: EntitySnapshot, form_flags: int, colour: int) -> void:
	if not entity.live_flags & EntityLiveFlags.ANIMATED and form_flags & FORM_NO_MODEL:
		if form_flags & FORM_NO_COLOUR_FADE or entity.live_flags & EntityLiveFlags.NO_COLOUR_FADE:
			return
		var level: int = mini(128, PlatformMath.s32(colour << 2)) & 255
		entity.colour_scale = Vector3i(level, level, level)
	elif entity.live_flags & EntityLiveFlags.RESPECT_SCALE_COLOURS:
		var scale: Vector3i = entity.colour_scale
		entity.colour_scale = Vector3i((scale.x * colour >> 7) & 255, (scale.y * colour >> 7) & 255, (scale.z * colour >> 7) & 255)
	else:
		var packed: int = ((colour << 16) + (colour << 8) + colour) & 0xffffffff
		entity.colour_scale = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
	entity.colour_scaled = true
