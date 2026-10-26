class_name TerrainWallBounce
extends RefCounted
## Source terrain-reachable BOUNCY_COBWEB rebound callback.

static func setup(state: GameplayState, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var destination: Vector3i = Vector3i((state.frog.user_target_cell.x << 8) + grid.base.x + 128, 0, (state.frog.user_target_cell.y << 8) + grid.base.y + 128) * 65536
	state.frog.target_16.x = ((state.frog.cell.x << 8) + grid.base.x + 128) * 65536
	state.frog.target_16.z = ((state.frog.cell.y << 8) + grid.base.y + 128) * 65536
	state.frog.remaining_ticks = 6
	state.frog.target_y = GridQueries.square_height(grid.squares[state.frog.square_index])
	state.frog.velocity_16 = TerrainGridSlip._divide_delta(destination, state.frog.position_16, 6)
	var height_delta: int = Vector3i(0, (state.frog.target_y - state.frog.old_y) << 16, 0).y
	@warning_ignore("integer_division")
	state.frog.velocity_16.y = height_delta / 7 - ((0x100000 * 7) >> 1)
	result.animation_ids.append(16)
	return result

static func move(state: GameplayState, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	result.callback_flags = TerrainCallbackResult.UPDATE_MATRIX
	if state.frog.remaining_ticks == 0:
		return result
	state.frog.remaining_ticks -= 1
	if state.frog.remaining_ticks == 0:
		state.frog.position_16.x = state.frog.target_16.x
		state.frog.position_16.z = state.frog.target_16.z
		result.land_requested = true
		result.callback_flags |= (TerrainCallbackResult.UPDATE_POS | TerrainCallbackResult.UPDATE_OLD_POS | TerrainCallbackResult.REACT_WITH_FLAGS)
		result.react_flags = grid.squares[state.frog.square_index].flags
		return result
	if state.frog.remaining_ticks == 3:
		state.frog.velocity_16.x = -state.frog.velocity_16.x
		state.frog.velocity_16.z = -state.frog.velocity_16.z
	state.frog.velocity_16.y += 0x100000
	state.frog.position_16 += state.frog.velocity_16
	result.callback_flags |= TerrainCallbackResult.UPDATE_POS
	return result
