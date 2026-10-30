class_name PlatformMath
extends RefCounted
## Fixed-width matrix operations shared by detached platform and camera rules.

## Source signed 16-bit narrowing.
static func s16(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

## Source signed 32-bit narrowing.
static func s32(value: int) -> int:
	return ((value + 2147483648) & 4294967295) - 2147483648

## C signed division truncates toward zero.
static func divide(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	return value / divisor

## Validates source matrix storage before a transactional operation.
static func valid(matrix: PackedInt32Array) -> bool:
	if matrix.size() != 12:
		return false
	for index: int in 12:
		if matrix[index] != (s16(matrix[index]) if index < 9 else s32(matrix[index])):
			return false
	return true

## Transposes only the source rotation.
static func transpose(matrix: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	for row: int in 3:
		for column: int in 3:
			result[row * 3 + column] = matrix[column * 3 + row]
	return result

## Applies a rotation, with a signed32 dot product followed by arithmetic shift.
static func apply(matrix: PackedInt32Array, vector: Vector3i) -> Vector3i:
	return Vector3i(s32(matrix[0] * vector.x + matrix[1] * vector.y + matrix[2] * vector.z) >> 12,
		s32(matrix[3] * vector.x + matrix[4] * vector.y + matrix[5] * vector.z) >> 12,
		s32(matrix[6] * vector.x + matrix[7] * vector.y + matrix[8] * vector.z) >> 12)

## Frozen ApplyMatrixLV uses wide accumulators for full 16.16 input vectors.
static func apply_fixed(matrix: PackedInt32Array, vector: Vector3i) -> Vector3i:
	return Vector3i(s32((matrix[0] * vector.x + matrix[1] * vector.y + matrix[2] * vector.z) >> 12),
		s32((matrix[3] * vector.x + matrix[4] * vector.y + matrix[5] * vector.z) >> 12),
		s32((matrix[6] * vector.x + matrix[7] * vector.y + matrix[8] * vector.z) >> 12))

## Multiplies source rotations and narrows each result to the matrix field width.
static func multiply(left: PackedInt32Array, right: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	for column: int in 3:
		var vector: Vector3i = apply(left, Vector3i(right[column], right[3 + column], right[6 + column]))
		result[column] = s16(vector.x)
		result[3 + column] = s16(vector.y)
		result[6 + column] = s16(vector.z)
	return result

## Source yaw projection normalizes the projected forward axis, then its cross axis.
static func project(matrix: PackedInt32Array) -> PackedInt32Array:
	var z: Vector3i = EntityTransform._normalise(Vector3i(matrix[2], 0, matrix[8]))
	var x: Vector3i = EntityTransform._normalise(EntityTransform._cross12(Vector3i(0, 4096, 0), z))
	return PackedInt32Array([x.x, 0, z.x, x.y, 4096, z.y, x.z, 0, z.z, 0, 0, 0])

## Builds the frozen stub's rounded fixed-12 Y rotation.
static func yaw(angle: int) -> PackedInt32Array:
	var cosine: int = roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var sine: int = roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	return PackedInt32Array([cosine, 0, sine, 0, 4096, 0, -sine, 0, cosine, 0, 0, 0])

## Builds the rounded fixed-12 MRRot_matrix_X, rows (1, 0, 0), (0, cos, -sin), (0, sin, cos).
static func x_rotation(angle: int) -> PackedInt32Array:
	var cosine: int = roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var sine: int = roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	return PackedInt32Array([4096, 0, 0, 0, cosine, -sine, 0, sine, cosine, 0, 0, 0])

## Builds the rounded fixed-12 MRRot_matrix_Z, rows (cos, -sin, 0), (sin, cos, 0), (0, 0, 1).
static func z_rotation(angle: int) -> PackedInt32Array:
	var cosine: int = roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var sine: int = roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	return PackedInt32Array([cosine, -sine, 0, sine, cosine, 0, 0, 0, 4096, 0, 0, 0])

## Source MRMulMatrixABA(matrix, MRRot_matrix_X): rotation becomes matrix x Rot, translation is retained.
static func rotate_x(matrix: PackedInt32Array, angle: int) -> PackedInt32Array:
	var result: PackedInt32Array = multiply(matrix, x_rotation(angle))
	for axis: int in 3:
		result[9 + axis] = matrix[9 + axis]
	return result

## Mathematical reconstruction verified against every frozen MR_ACOS table entry.
static func acos12(value: int) -> int:
	var bounded: int = clampi(value, -4096, 4096)
	return 1023 if bounded == 0 else mini(2047, floori(acos(float(bounded) / 4096.0) * 2048.0 / PI))

## Chooses the source cardinal quadrant, with X winning diagonal ties.
static func quadrant(vector: Vector3i) -> int:
	return (0 if vector.z > 0 else 2) if absi(vector.z) > absi(vector.x) else (1 if vector.x > 0 else 3)

## Transforms local whole-unit position using signed-short input coordinates.
static func world(matrix: PackedInt32Array, local_16: Vector3i) -> Vector3i:
	return apply(matrix, Vector3i(s16(local_16.x >> 16), s16(local_16.y >> 16), s16(local_16.z >> 16))) + Vector3i(matrix[9], matrix[10], matrix[11])
