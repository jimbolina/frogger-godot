class_name TongueCurve
extends RefCounted
## Frozen effect Bezier evaluation, including source signed narrowing.

## Evaluates the current tip using the target's current position on each tick.
static func tip(matrix: PackedInt32Array, section: int, target: Vector3i, has_target: bool) -> Vector3i:
	var origin := Vector3i(matrix[9], matrix[10], matrix[11])
	var p1: Vector3i = _narrow(origin + PlatformMath.apply(matrix, Vector3i(0, -32, 48)))
	var p2 := Vector3i.ZERO
	var p3 := Vector3i.ZERO
	var p4: Vector3i = _narrow(target) if has_target else _narrow(origin + PlatformMath.apply(matrix, Vector3i(8, -80, 48)))
	for axis: int in 3:
		if has_target:
			p2[axis] = PlatformMath.s16(p1[axis] + (matrix[axis * 3 + 2] >> 4))
			p3[axis] = (p4[axis] + p2[axis]) >> 1
		else:
			p2[axis] = PlatformMath.s16(p1[axis] + (matrix[axis * 3 + 2] >> 5) + (matrix[axis * 3] >> 5))
			p3[axis] = PlatformMath.s16(p1[axis] + (matrix[axis * 3 + 2] >> 5) - (matrix[axis * 3] >> 5))
	var t: int = section * 256
	var t2: int = PlatformMath.s32(t * t) >> 3
	var t3: int = PlatformMath.s32(t2 * t) >> 11
	var result := Vector3i.ZERO
	for axis: int in 3:
		var u: int = p1[axis] >> 3
		var v: int = PlatformMath.s16((p2[axis] >> 3) * 3)
		var upper_u: int = PlatformMath.s16((p3[axis] >> 3) * 3)
		var upper_v: int = p4[axis] >> 3
		var a: int = -u + v - upper_u + upper_v
		var d: int = u
		u = PlatformMath.s16(u * 3)
		var b: int = u - 2 * v + upper_u
		var c: int = -u + v
		result[axis] = PlatformMath.s16((PlatformMath.s32(t3 * a) >> 16) + (PlatformMath.s32(t2 * b) >> 16) + (PlatformMath.s32(t * c) >> 8) + (d << 3))
	return result

static func _narrow(value: Vector3i) -> Vector3i:
	return Vector3i(PlatformMath.s16(value.x), PlatformMath.s16(value.y), PlatformMath.s16(value.z))
