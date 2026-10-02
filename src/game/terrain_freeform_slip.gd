class_name TerrainFreeformSlip
extends RefCounted
## Frozen non-grid terrain slipping. Tongue/entity interaction is P8/P10.

static func setup(state: RunSnapshot) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	state.velocity_16 = state.position_16 - state.old_position_16
	state.velocity_16.y = 0
	state.shadow_hidden = true
	result.create_slide_particles = true
	return result

## Held steering uses the previous matrix and previous virtual animation action.
static func control(state: RunSnapshot, command: TickCommand, directions: PackedInt32Array, theme: int) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var key: int = 128
	for direction: int in range(4):
		if command.held_mask & (1 << direction):
			key = direction
			break
	if key == 128:
		return result
	var relative: int = (directions[key] - state.direction) & 3
	var local: Vector3i = Vector3i(-15, 0, 0) if relative == 3 else Vector3i(15, 0, 0) if relative == 1 else Vector3i(0, 0, 10) if relative == 0 else Vector3i(0, 0, -15)
	var speed: Vector3i = _apply(state.matrix12, local)
	if relative in [1, 3]:
		state.velocity_16.x += speed.x << 14
		state.velocity_16.z += speed.z << 14
		var animation_id: int = 24 if relative == 1 else 25
		if state.animation == null or state.animation.action != animation_id:
			result.animation_ids.append(animation_id)
			result.start_slipping_sound = theme == 7
	elif relative == 0:
		# Caller supplies terrain average normal to this branch below.
		result.forward_steering = true
	else:
		state.velocity_16.x = _brake(state.velocity_16.x, speed.x)
		state.velocity_16.z = _brake(state.velocity_16.z, speed.z)
	return result

static func forward_control(state: RunSnapshot, square: GridSquareDefinition) -> void:
	var speed: Vector3i = _apply(state.matrix12, Vector3i(0, 0, 10))
	var normal: Vector3i = GridQueries.average_normal(square)
	if (speed.x > 0 and normal.x < 0) or (speed.x < 0 and normal.x > 0):
		speed.x = 0
	if (speed.z > 0 and normal.z < 0) or (speed.z < 0 and normal.z > 0):
		speed.z = 0
	state.velocity_16.x += speed.x << 14
	state.velocity_16.z += speed.z << 14

static func move(state: RunSnapshot, grid: GridDefinition) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	result.callback_flags = 3
	if grid.stack_at(state.cell) == null:
		result.kill_animation = 2
		return result
	var cell: Vector2i = GridQueries.world_to_cell(grid, state.world_position.x, state.world_position.z)
	var stack: GridStackDefinition = grid.stack_at(cell)
	if stack == null:
		result.error = "Freeform cached translation lies outside authored storage"
		return result
	if stack.square_count == 0:
		if not state.flags & 128:
			state.flags |= 128 | 8192
			state.remaining_ticks = 0x7FFFFFF
			state.square_index = -1
		state.mode = 1
		result.kill_slide_particles = true
		return result
	var info: GridSurfaceInfo = GridQueries.info_at(grid, state.world_position.x, state.world_position.z)
	var acceleration: Vector3i = GridQueries._cross12(info.x_slope, info.z_slope)
	state.velocity_16.x = _accelerate(state.velocity_16.x, info.x_slope.y, acceleration.x)
	state.velocity_16.z = _accelerate(state.velocity_16.z, info.z_slope.y, acceleration.z)
	state.velocity_16.y += 0x80000
	state.matrix12 = TerrainMatrix.update(state.matrix12, 0, state.direction, null)
	var direction: int = (1 if state.velocity_16.x > 0 else 3) if absi(state.velocity_16.x) > absi(state.velocity_16.z) else (0 if state.velocity_16.z > 0 else 2)
	if direction != state.direction:
		state.direction = direction
		result.callback_flags |= 8
	state.position_16 += state.velocity_16
	var floor_16: int = Vector3i(0, info.height << 16, 0).y
	if state.position_16.y > floor_16:
		state.position_16.y = floor_16
		state.velocity_16.y = 0
	for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
		var square: GridSquareDefinition = grid.squares[index]
		if not square.flags & 1:
			continue
		var height: int = GridQueries.square_height(square)
		var difference: int = state.world_position.y - height
		if (square.flags & 4096 and absi(difference) < 196) or (square.flags & 4 and ((square.flags & 128 and difference > 196) or (not square.flags & 128 and absi(difference) < 128))):
			state.position_16 = state.old_position_16
			result.kill_animation = 2
			return result
		if square.flags & 2048:
			result.kill_slide_particles = true
			result.setup_mode_request = 269
			return result
		if difference < 512:
			state.world_position.y = height
			state.matrix12[10] = height
			state.square_index = index
			state.cell = cell
			if not square.flags & 128:
				state.target_y = state.position_16.y >> 16
				state.old_y = state.target_y
				state.shadow_hidden = false
				state.mode = 0
				result.kill_slide_particles = true
			return result
		if square.flags & 128:
			result.kill_animation = 2
			return result
	state.target_y = state.position_16.y >> 16
	state.old_y = state.target_y
	if not state.flags & 128:
		state.flags |= 128 | 8192
		state.remaining_ticks = 0x7FFFFFF
	result.kill_slide_particles = true
	state.mode = 1
	return result

static func _apply(matrix: PackedInt32Array, vector: Vector3i) -> Vector3i:
	return Vector3i((matrix[0] * vector.x + matrix[1] * vector.y + matrix[2] * vector.z) >> 12, (matrix[3] * vector.x + matrix[4] * vector.y + matrix[5] * vector.z) >> 12, (matrix[6] * vector.x + matrix[7] * vector.y + matrix[8] * vector.z) >> 12)

static func _brake(velocity: int, speed: int) -> int:
	if speed == 0:
		return velocity
	var next: int = velocity + (speed << 13)
	return maxi(next, 0) if velocity > 0 else mini(next, 0)

static func _accelerate(velocity: int, slope_y: int, acceleration: int) -> int:
	if (velocity > 0 and slope_y < -3500) or (velocity < 0 and slope_y > 3500):
		@warning_ignore("integer_division")
		velocity /= 3
	return mini(velocity + (acceleration << 3), 0x500000) if velocity > 0 else maxi(velocity + (acceleration << 3), -0x500000)
