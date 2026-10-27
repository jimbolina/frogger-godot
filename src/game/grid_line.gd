class_name GridLine
extends RefCounted
## Frozen GRID.C tile walk used by tongue line of sight.

enum Mode { START, PROCESS, END, DONE }
var mode: Mode = Mode.START
var position: Vector3i
var step: Vector3i
var tile: Vector2i
var end_tile: Vector2i
var current_step: int = 0
var steps: int
var grid: GridDefinition

## Initializes signed-short endpoints and the source whole-unit step vector.
static func create(definition: GridDefinition, start: Vector3i, end: Vector3i) -> GridLine:
	var result := GridLine.new()
	result.grid = definition
	result.position = _short(start)
	var destination: Vector3i = _short(end)
	var delta: Vector3i = destination - result.position
	result.steps = maxi(1, int(sqrt(float(delta.x) * delta.x + float(delta.y) * delta.y + float(delta.z) * delta.z)) >> 8)
	var normal: Vector3i = EntityTransform._normalise(delta)
	result.step = Vector3i(normal.x << 8, normal.y << 8, normal.z << 8)
	result.end_tile = GridQueries.world_to_cell(definition, destination.x, destination.z)
	return result

## Returns the next source cell, retaining the height used for obstruction tests.
func advance() -> Vector2i:
	if mode == Mode.START:
		tile = GridQueries.world_to_cell(grid, position.x, position.z)
		mode = Mode.DONE if steps == 1 else Mode.PROCESS
		return tile
	while mode != Mode.DONE:
		var previous: Vector2i = tile
		var movement := Vector3i(step.x >> 12, step.y >> 12, step.z >> 12)
		if mode == Mode.END:
			tile = end_tile
		else:
			position += movement
			tile = GridQueries.world_to_cell(grid, position.x, position.z)
		if tile.x == previous.x and absi(tile.y - previous.y) > 1:
			tile.y = (tile.y + previous.y) >> 1
			break
		if tile.y == previous.y and absi(tile.x - previous.x) > 1:
			tile.x = (tile.x + previous.x) >> 1
			break
		if tile.x != previous.x and tile.y != previous.y:
			var direction := Vector3i(step.x >> 8, step.y >> 8, step.z >> 8)
			if _intersects(position, direction, Vector2i(tile.x, previous.y)):
				position -= movement
				tile.y = previous.y
				break
			if _intersects(position, direction, Vector2i(previous.x, tile.y)):
				position -= movement
				tile.x = previous.x
				break
		current_step += 1
		if current_step >= steps:
			mode = Mode.DONE if tile == end_tile else Mode.END
			break
		if tile != previous:
			break
	return tile

func _intersects(start: Vector3i, direction: Vector3i, cell: Vector2i) -> bool:
	var origin: Vector3i = _short(start)
	var normal: Vector3i = EntityTransform._normalise(Vector3i(PlatformMath.s16(direction.x), 0, PlatformMath.s16(direction.z)))
	var left: int = PlatformMath.s16(grid.base.x + (cell.x << 8))
	var right: int = PlatformMath.s16(grid.base.x + ((cell.x + 1) << 8))
	var bottom: int = PlatformMath.s16(grid.base.y + (cell.y << 8))
	var top: int = PlatformMath.s16(grid.base.y + ((cell.y + 1) << 8))
	if normal.x:
		for edge: int in [left, right]:
			var k: int = PlatformMath.divide((edge - origin.x) << 12, normal.x)
			var z: int = PlatformMath.s16(origin.z + (PlatformMath.s32(normal.z * k) >> 12))
			if z >= bottom and z <= top:
				return true
	if normal.z:
		for edge: int in [bottom, top]:
			var k: int = PlatformMath.divide((edge - origin.z) << 12, normal.z)
			var x: int = PlatformMath.s16(origin.x + (PlatformMath.s32(normal.x * k) >> 12))
			if x >= left and x <= right:
				return true
	return false

static func _short(value: Vector3i) -> Vector3i:
	return Vector3i(PlatformMath.s16(value.x), PlatformMath.s16(value.y), PlatformMath.s16(value.z))
