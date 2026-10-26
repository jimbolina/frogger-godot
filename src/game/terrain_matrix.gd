class_name TerrainMatrix
extends RefCounted
## Pure surface-facing branch of frozen UpdateFrogMatrix, including departure facing.

## Updates rotation while retaining cached translation; freefall preserves rotation.
static func update(previous: PackedInt32Array, flags: int, direction: int, square: GridSquareDefinition, facing_override: Vector3i = Vector3i.ZERO) -> PackedInt32Array:
	var result: PackedInt32Array = previous.duplicate()
	if (flags & FrogFlags.FREEFALL) != 0:
		return result
	var normal: Vector3i
	if square == null:
		normal = GridQueries._normal(Vector3i(-previous[1], -previous[4], -previous[7]))
	else:
		normal = GridQueries.average_normal(square)
	var facing: Vector3i = [Vector3i(0, 0, 4096), Vector3i(4096, 0, 0), Vector3i(0, 0, -4096), Vector3i(-4096, 0, 0)][direction]
	if facing_override != Vector3i.ZERO:
		facing = facing_override
	var local_x: Vector3i = GridQueries._normal(GridQueries._cross12(facing, normal))
	var local_z: Vector3i = GridQueries._cross12(normal, local_x)
	result[0] = local_x.x
	result[3] = local_x.y
	result[6] = local_x.z
	result[1] = -normal.x
	result[4] = -normal.y
	result[7] = -normal.z
	result[2] = local_z.x
	result[5] = local_z.y
	result[8] = local_z.z
	return result
