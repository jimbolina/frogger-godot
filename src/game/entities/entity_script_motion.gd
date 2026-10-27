class_name EntityScriptMotion
extends RefCounted
## Source-width script translations and path-relative rotations.

## Advances each source axis after instruction execution and before callbacks.
static func advance(state: EntityScriptState) -> void:
	for axis: int in 3:
		var motion: Vector3i = _advance(state.offsets[axis], state.deltas[axis], state.counts[axis], state.destinations[axis], false)
		state.offsets[axis] = motion.x
		state.deltas[axis] = motion.y
		state.counts[axis] = motion.z
		motion = _advance(state.angles[axis], state.angular_deltas[axis], state.angular_counts[axis], state.angular_destinations[axis], true)
		state.angles[axis] = motion.x
		state.angular_deltas[axis] = motion.y
		state.angular_counts[axis] = motion.z

## Applies path-relative or authored-matrix motion according to the script type.
static func transform(state: EntityScriptState, base: PackedInt32Array, authored: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var result: PackedInt32Array = base.duplicate()
	var origin: PackedInt32Array = base
	if state.entity_type == 1:
		origin = authored
		if state.angles != Vector3i.ZERO:
			var rotation: PackedInt32Array = PlatformMath.multiply(_rotation(0, state.angles.x), _rotation(1, state.angles.y))
			rotation = PlatformMath.multiply(rotation, _rotation(2, state.angles.z))
			result = PlatformMath.multiply(rotation, authored)
	else:
		for axis: int in 3:
			if state.angles[axis] != 0:
				result = PlatformMath.multiply(result, _rotation(axis, state.angles[axis]))
	for axis: int in 3:
		result[9 + axis] = PlatformMath.s32(origin[9 + axis] + state.offsets[axis])
	return result

static func _advance(value: int, delta: int, count: int, destination: int, angular: bool) -> Vector3i:
	if count == 0 or (count < 0 and delta == 0):
		return Vector3i(value, delta, count)
	value = PlatformMath.s16(value + (delta if angular else delta >> 8))
	if count < 0:
		if (delta > 0 and value >= destination) or (delta < 0 and value <= destination):
			value = destination & 4095 if angular else destination
			delta = 0
			count = 0
	else:
		if angular:
			value &= 4095
		count = PlatformMath.s16(count - 1)
		if count == 0:
			delta = 0
	return Vector3i(value, delta, count)

static func _rotation(axis: int, angle: int) -> PackedInt32Array:
	var cosine: int = roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var sine: int = roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	match axis:
		0:
			return PackedInt32Array([4096, 0, 0, 0, cosine, -sine, 0, sine, cosine, 0, 0, 0])
		1:
			return PackedInt32Array([cosine, 0, sine, 0, 4096, 0, -sine, 0, cosine, 0, 0, 0])
	return PackedInt32Array([cosine, -sine, 0, sine, cosine, 0, 0, 0, 4096, 0, 0, 0])
