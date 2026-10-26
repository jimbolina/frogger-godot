class_name TerrainCliffRoll
extends RefCounted
## Frozen cliff setup/movement, including its distinct FROG_FALL transition.

static func setup(state: RunSnapshot, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var delta: Vector2i = _downhill(state, grid.squares[state.square_index])
	if delta == Vector2i.ZERO:
		result.kill_animation = 2
		return result
	return _destination(state, grid, delta, true)

static func move(state: RunSnapshot, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	if state.square_index < 0:
		state.mode = FrogMode.JUMPING
		state.remaining_ticks = 65535
		state.velocity_16 = Vector3i.ZERO
		state.flags = (state.flags & ~FrogFlags.LANDED_ON_LAND_CLEAR_MASK) | FrogFlags.FREEFALL
		result.animation_ids.assign([11, 6])
		return result
	if state.remaining_ticks == 0:
		state.position_16 = state.target_16
		state.target_y = state.position_16.y >> 16
		state.old_y = state.target_y
		if not grid.squares[state.square_index].flags & GridSquareFlags.CLIFF:
			result.kill_animation = 2
			return result
		var delta: Vector2i = _downhill(state, grid.squares[state.square_index])
		if delta == Vector2i.ZERO:
			result.kill_animation = 2
			return result
		return _destination(state, grid, delta, false)
	state.position_16 += state.velocity_16
	state.remaining_ticks -= 1
	state.matrix12 = TerrainMatrix.update(state.matrix12, 0, state.direction, grid.squares[state.square_index])
	var info: GridSurfaceInfo = GridQueries.info_at(grid, state.world_position.x, state.world_position.z)
	if info == null:
		result.error = "Cliff alignment requires an authored first layer"
		return result
	state.world_position.y = info.height - 30
	state.matrix12[10] = state.world_position.y
	result.callback_flags = TerrainCallbackResult.UPDATE_POS
	return result

static func _downhill(state: RunSnapshot, square: GridSquareDefinition) -> Vector2i:
	var normal: Vector3i = GridQueries.average_normal(square)
	if absi(normal.x) > absi(normal.z):
		if normal.x > 256:
			state.direction = 1
			return Vector2i(1, 0)
		if normal.x < -256:
			state.direction = 3
			return Vector2i(-1, 0)
	else:
		if normal.z > 256:
			state.direction = 0
			return Vector2i(0, 1)
		if normal.z < -256:
			state.direction = 2
			return Vector2i(0, -1)
	return Vector2i.ZERO

static func _destination(state: RunSnapshot, grid: GridDefinition, delta: Vector2i, initial: bool) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var destination: Vector2i = state.cell + delta
	var stack: GridStackDefinition = grid.stack_at(destination)
	if stack == null:
		result.error = "Cliff destination lies outside authored storage"
		return result
	if initial and stack.square_count == 0:
		state.square_index = -1
		return result
	for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
		var square: GridSquareDefinition = grid.squares[index]
		if not square.flags & GridSquareFlags.USABLE:
			if not initial:
				result.error = "Source cliff continuation stalls on an unusable authored layer"
				return result
			continue
		if initial and square.flags == GridSquareFlags.USABLE:
			state.square_index = -1
			return result
		var height: int = GridQueries.square_height(square)
		if state.world_position.y >= height:
			continue
		state.flags &= ~(FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_TO_LAND)
		state.cell = destination
		state.square_index = index
		state.target_16 = Vector3i((destination.x << 8) + grid.base.x + 128, height, (destination.y << 8) + grid.base.y + 128) * 65536
		state.remaining_ticks = 20
		state.velocity_16 = TerrainGridSlip._divide_delta(state.target_16, state.position_16, 20)
		if initial:
			state.mode = FrogMode.CLIFF_ROLL
			state.flags &= ~FrogFlags.MUST_DIE
			result.animation_ids.append(34)
		return result
	result.kill_animation = 2
	return result
