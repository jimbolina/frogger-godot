class_name EntityTransform
extends RefCounted
## Builds the generic moving MOF matrix from the frozen source path axes.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]

## Returns the generic moving MOF matrix for an evaluated path position.
static func moving(path: PathSnapshot, flags: int) -> PackedInt32Array:
	var result: PackedInt32Array = IDENTITY.duplicate()
	result[9] = path.position.x
	result[10] = path.position.y
	result[11] = path.position.z
	if flags & EntityDefinition.ALIGN_TO_WORLD:
		return result
	var axis_z: Vector3i = path.tangent
	var axis_x: Vector3i = _normalise(_cross12(Vector3i(0, 4096, 0), axis_z))
	var axis_y: Vector3i = _cross12(axis_z, axis_x)
	result[0] = _signed16(axis_x.x)
	result[1] = _signed16(axis_y.x)
	result[2] = _signed16(axis_z.x)
	result[3] = _signed16(axis_x.y)
	result[4] = _signed16(axis_y.y)
	result[5] = _signed16(axis_z.y)
	result[6] = _signed16(axis_x.z)
	result[7] = _signed16(axis_y.z)
	result[8] = _signed16(axis_z.z)
	return result

static func _cross12(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(_signed32(a.y * b.z - a.z * b.y) >> 12, _signed32(a.z * b.x - a.x * b.z) >> 12, _signed32(a.x * b.y - a.y * b.x) >> 12)

static func _normalise(value: Vector3i) -> Vector3i:
	var magnitude: float = sqrt(float(value.x) * value.x + float(value.y) * value.y + float(value.z) * value.z)
	if magnitude < 0.000001:
		return Vector3i.ZERO
	return Vector3i(roundi(value.x * 4096.0 / magnitude), roundi(value.y * 4096.0 / magnitude), roundi(value.z * 4096.0 / magnitude))

static func _signed16(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low
