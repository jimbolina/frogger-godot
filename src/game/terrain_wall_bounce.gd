class_name TerrainWallBounce
extends RefCounted
## Source terrain-reachable BOUNCY_COBWEB rebound callback.

static func setup(state: RunSnapshot, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var destination: Vector3i = Vector3i((state.user_target_cell.x << 8) + grid.base.x + 128, 0, (state.user_target_cell.y << 8) + grid.base.y + 128) * 65536
	state.target_16.x = ((state.cell.x << 8) + grid.base.x + 128) * 65536
	state.target_16.z = ((state.cell.y << 8) + grid.base.y + 128) * 65536
	state.remaining_ticks = 6
	state.target_y = GridQueries.square_height(grid.squares[state.square_index])
	state.velocity_16 = TerrainGridSlip._divide_delta(destination, state.position_16, 6)
	var height_delta: int = Vector3i(0, (state.target_y - state.old_y) << 16, 0).y
	@warning_ignore("integer_division")
	state.velocity_16.y = height_delta / 7 - ((0x100000 * 7) >> 1)
	result.animation_ids.append(16)
	return result

static func move(state: RunSnapshot, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	result.callback_flags = TerrainCallbackResult.UPDATE_MATRIX
	if state.remaining_ticks == 0:
		return result
	state.remaining_ticks -= 1
	if state.remaining_ticks == 0:
		state.position_16.x = state.target_16.x
		state.position_16.z = state.target_16.z
		result.land_requested = true
		result.callback_flags |= (TerrainCallbackResult.UPDATE_POS | TerrainCallbackResult.UPDATE_OLD_POS | TerrainCallbackResult.REACT_WITH_FLAGS)
		result.react_flags = grid.squares[state.square_index].flags
		return result
	if state.remaining_ticks == 3:
		state.velocity_16.x = -state.velocity_16.x
		state.velocity_16.z = -state.velocity_16.z
	state.velocity_16.y += 0x100000
	state.position_16 += state.velocity_16
	result.callback_flags |= TerrainCallbackResult.UPDATE_POS
	return result
