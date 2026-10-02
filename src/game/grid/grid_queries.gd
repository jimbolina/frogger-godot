class_name GridQueries
extends RefCounted
## Frozen GRID.C static queries. Inputs are integer game coordinates, never render units.

## Converts world XZ using C's arithmetic right shift, including negative edges.
static func world_to_cell(grid: GridDefinition, x: int, z: int) -> Vector2i:
	var relative: Vector2i = Vector2i(x, z) - grid.base
	return Vector2i(relative.x >> 8, relative.y >> 8)

## Returns the authored cliff byte scaled as GetGridStackHeight does.
static func stack_height(stack: GridStackDefinition) -> int:
	return stack.cliff_height_byte << 6

## Averages all four stored calculation corners with an arithmetic shift.
static func square_height(square: GridSquareDefinition) -> int:
	return (square.vertices[0].y + square.vertices[1].y + square.vertices[2].y + square.vertices[3].y) >> 2

## Snaps the four-corner average XZ to its cell centre, retaining average Y.
static func square_centre(grid: GridDefinition, square: GridSquareDefinition) -> Vector3i:
	var sum := Vector3i.ZERO
	for v: Vector3i in square.vertices:
		sum += v
	var cell: Vector2i = world_to_cell(grid, sum.x >> 2, sum.z >> 2)
	return Vector3i(_signed16((cell.x << 8) + 128 + grid.base.x), _signed16(square_height(square)), _signed16((cell.y << 8) + 128 + grid.base.y))

static func _signed16(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

## Projects onto C's two semi-infinite triangles and returns normalized slopes.
static func square_info(square: GridSquareDefinition, x: int, z: int) -> GridSurfaceInfo:
	var result := GridSurfaceInfo.new()
	var dx: int = x & 255
	var dz: int = z & 255
	var y0: int = square.vertices[0].y
	var y1: int = square.vertices[1].y
	var y2: int = square.vertices[2].y
	var y3: int = square.vertices[3].y
	if dz >= dx:
		result.height = y0 + ((dx * (y1 - y0)) >> 8) + (((256 - dz) * (y2 - y0)) >> 8)
		result.x_slope = _normal(Vector3i(256, y1 - y0, 0))
		result.z_slope = _normal(Vector3i(0, y0 - y2, 256))
	else:
		result.height = y3 + (((256 - dx) * (y2 - y3)) >> 8) + ((dz * (y1 - y3)) >> 8)
		result.x_slope = _normal(Vector3i(256, y3 - y2, 0))
		result.z_slope = _normal(Vector3i(0, y1 - y3, 256))
	return result

## Queries the first authored layer; empty and out-of-board cells return null.
static func info_at(grid: GridDefinition, x: int, z: int) -> GridSurfaceInfo:
	var stack: GridStackDefinition = grid.stack_at(world_to_cell(grid, x, z))
	if stack == null or stack.square_count == 0:
		return null
	return _layer_info(grid, stack.first_square_index, x, z)

## Chooses the highest layer with any corner Y >= input, falling back to lowest.
static func height_at(grid: GridDefinition, x: int, y: int, z: int) -> GridSurfaceInfo:
	y = Vector3i(0, y, 0).y
	var stack: GridStackDefinition = grid.stack_at(world_to_cell(grid, x, z))
	if stack == null or stack.square_count == 0:
		return null
	for index: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
		for v: Vector3i in grid.squares[index].vertices:
			if v.y >= y:
				return _layer_info(grid, index, x, z)
	return _layer_info(grid, stack.first_square_index, x, z)

## Averages normalized effective triangle normals; a repeated last corner is a tri.
static func average_normal(square: GridSquareDefinition) -> Vector3i:
	var v: Array[Vector3i] = square.vertices
	var edge0: Vector3i = (v[1] - v[0]) * 16
	var edge1: Vector3i = (v[2] - v[0]) * 16
	var normal0: Vector3i = _cross12(edge1, edge0)
	edge0 = (v[1] - v[3]) * 16
	edge1 = (v[2] - v[3]) * 16
	if edge1 == Vector3i.ZERO:
		return _normal(normal0)
	var combined: Vector3i = _normal(normal0) + _normal(_cross12(edge0, edge1))
	return _normal(Vector3i(combined.x >> 1, combined.y >> 1, combined.z >> 1))

static func _layer_info(grid: GridDefinition, index: int, x: int, z: int) -> GridSurfaceInfo:
	var info: GridSurfaceInfo = square_info(grid.squares[index], x, z)
	info.square_index = index
	return info

static func _cross12(a: Vector3i, b: Vector3i) -> Vector3i:
	var product: Vector3i = Vector3i(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
	return Vector3i(product.x >> 12, product.y >> 12, product.z >> 12)

static func _normal(v: Vector3i) -> Vector3i:
	var length: float = sqrt(float(v.x) * v.x + float(v.y) * v.y + float(v.z) * v.z)
	if length < 0.000001:
		return Vector3i.ZERO
	var scale: float = 4096.0 / length
	return Vector3i(roundi(v.x * scale), roundi(v.y * scale), roundi(v.z * scale))
