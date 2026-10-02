class_name TerrainGridSlip
extends RefCounted
## Frozen grid/simple slipping callbacks. Run dispatches stationary controls.

const SPEEDS: Array[int] = [1, 1, 2, 2, 3, 3, 4, 4, 5]
const DELTAS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

## Selects the authored destination and linear velocity without advancing a tick.
static func setup(state: RunSnapshot, grid: GridDefinition, simple: bool, theme: int) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var delta: Vector2i = DELTAS[state.direction]
	var count: int = 10
	if not simple:
		var shifted: Vector2i = Vector2i((state.matrix12[2] * 25) >> 12, (state.matrix12[8] * 25) >> 12)
		var sensed: Vector2i = GridQueries.world_to_cell(grid, state.world_position.x + shifted.x, state.world_position.z + shifted.y)
		var sensed_stack: GridStackDefinition = grid.stack_at(sensed)
		if sensed_stack != null:
			for index: int in range(sensed_stack.first_square_index, sensed_stack.first_square_index + sensed_stack.square_count):
				var square: GridSquareDefinition = grid.squares[index]
				if (square.flags & 1) != 0 and absi(state.world_position.y - GridQueries.square_height(square)) <= 448:
					state.cell = sensed
					state.square_index = index
					break
		var normal: Vector3i = GridQueries.average_normal(grid.squares[state.square_index])
		delta = Vector2i(_sign_threshold(normal.x), _sign_threshold(normal.z))
		if delta == Vector2i.ZERO:
			if state.velocity_16.x != 0:
				delta = Vector2i(-1 if state.velocity_16.x < 0 else 1, 0)
			elif state.velocity_16.z != 0:
				delta = Vector2i(0, -1 if state.velocity_16.z < 0 else 1)
			else:
				delta = DELTAS[state.direction]
		else:
			count = SPEEDS[maxi((-normal.y) >> 9, 0)]
	var destination: Vector2i = state.cell + delta
	var stack: GridStackDefinition = grid.stack_at(destination)
	if stack == null:
		result.error = "Grid slipping destination lies outside authored storage"
		return result
	for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
		var square: GridSquareDefinition = grid.squares[index]
		var height: int = GridQueries.square_height(square)
		if (square.flags & 1) == 0 or state.world_position.y - height > (448 if simple else 496) or height - state.world_position.y > 256:
			continue
		state.flags &= ~66
		state.cell = destination
		state.square_index = index
		state.target_16 = Vector3i((destination.x << 8) + grid.base.x + 128, height, (destination.y << 8) + grid.base.y + 128) * 65536
		state.remaining_ticks = count
		state.velocity_16 = _divide_delta(state.target_16, state.position_16, count)
		result.animation_ids.append(22)
		result.start_slipping_sound = theme == 7
		result.create_slide_particles = not simple
		return result
	if not simple:
		state.flags &= ~82422
		state.velocity_16 = Vector3i.ZERO
	state.remaining_ticks = 0
	state.mode = 0
	state.target_16 = Vector3i(state.position_16.x >> 16, state.position_16.y >> 16, state.position_16.z >> 16) * 65536
	return result

## Slides once; source tests count before decrement, so snapping occurs next call.
static func move(state: RunSnapshot, grid: GridDefinition, align: bool = true) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	if state.remaining_ticks == 0:
		state.position_16 = state.target_16
		state.target_y = state.position_16.y >> 16
		state.old_y = state.target_y
		state.mode = 0
		result.kill_looping_sound = true
		result.animation_ids.append(14)
		result.react_flags = grid.squares[state.square_index].flags
		result.callback_flags = 7
	else:
		state.position_16 += state.velocity_16
		state.remaining_ticks -= 1
		result.callback_flags = 1
	if align:
		state.matrix12 = TerrainMatrix.update(state.matrix12, 0, state.direction, grid.squares[state.square_index])
	return result

static func _sign_threshold(value: int) -> int:
	return 1 if value > 256 else (-1 if value < -256 else 0)

static func _divide_delta(target: Vector3i, origin: Vector3i, divisor: int) -> Vector3i:
	var difference: Vector3i = target - origin
	@warning_ignore("integer_division")
	return Vector3i(difference.x / divisor, difference.y / divisor, difference.z / divisor)
