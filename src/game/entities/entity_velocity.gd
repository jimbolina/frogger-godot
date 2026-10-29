class_name EntityVelocity
extends RefCounted
## Frozen UpdateEntityWithVelocity gravity integration over 16.16 custom position and velocity.

## Source WORLD_GRAVITY, (2560 << 16) / (30 * 30) rounded, in 16.16 units per tick.
const WORLD_GRAVITY: int = 0x2d800

## Skips a NO_MOVEMENT entity; otherwise adds gravity to velocity Y first, then adds the whole
## velocity to offset_16 (each component wrapping as signed 32-bit), and finally writes the
## arithmetic-shifted whole-unit offset into the matrix translation.
static func step(entity: EntitySnapshot, custom: EntityCustomState) -> void:
	if entity.entity_flags & EntityDefinition.NO_MOVEMENT:
		return
	custom.velocity_16.y = PlatformMath.s32(custom.velocity_16.y + WORLD_GRAVITY)
	for axis: int in 3:
		custom.offset_16[axis] = PlatformMath.s32(custom.offset_16[axis] + custom.velocity_16[axis])
		entity.matrix12[9 + axis] = custom.offset_16[axis] >> 16
