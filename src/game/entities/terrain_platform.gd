class_name TerrainPlatform
extends RefCounted
## Source platform-local landing, carrying and departure selection on private state.

const LANDED_CLEAR: int = 2 | 16 | 32 | 64 | 128 | 256 | 65536 | 16384
const DIRECTIONS: Array[Vector3i] = [Vector3i(0, 0, 4096), Vector3i(4096, 0, 0), Vector3i(0, 0, -4096), Vector3i(-4096, 0, 0)]

## Completes SAFE alignment after the coordinator has applied the fall reaction.
static func land(state: RunSnapshot, definition: FormContactDefinition, contact: FormContactResult, pose: EntitySnapshot, camera: GameplayCamera, previous: PackedInt32Array) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var matrix: PackedInt32Array = pose.matrix12
	var inverse: PackedInt32Array = PlatformMath.transpose(matrix)
	var local: Vector3i = contact.local_position
	state.entity_cell = contact.cell
	state.entity_offset_16 = Vector3i(local.x, contact.height, local.z) * 65536
	var target := Vector3i(local.x, contact.height, local.z)
	var centring: bool = false
	if not definition.form_book_flags & 64 or absi(local.x) > (definition.dimensions.x - 1) * 128:
		target.x = definition.offsets.x + contact.cell.x * 256 + 128
		centring = true
	if not definition.form_book_flags & 128 or absi(local.z) > (definition.dimensions.y - 1) * 128:
		target.z = definition.offsets.y + contact.cell.y * 256 + 128
		centring = true
	state.target_16 = target * 65536
	if centring:
		var delta := Vector3i(PlatformMath.s16(target.x - local.x), 0, PlatformMath.s16(target.z - local.z))
		result.animation_ids.append(FrogAnimationCatalog.STRUGGLE if absi(target.x - local.x) >= 96 or absi(target.z - local.z) >= 96 else FrogAnimationCatalog.PANT)
		var length: int = floori(sqrt(float(PlatformMath.s32(delta.x * delta.x + delta.z * delta.z))))
		state.mode = FrogMode.CENTRING
		state.remaining_ticks = PlatformMath.divide(length, 15) + 1
		state.velocity_16 = Vector3i(PlatformMath.divide(delta.x << 16, state.remaining_ticks), 0, PlatformMath.divide(delta.z << 16, state.remaining_ticks))
		state.position_16 = PlatformMath.world(matrix, state.entity_offset_16) * 65536
	state.world_position = Vector3i(state.position_16.x >> 16, state.position_16.y >> 16, state.position_16.z >> 16)
	state.target_y = state.world_position.y
	state.old_y = state.target_y
	if not definition.form_book_flags & 2:
		var forward: Vector3i = PlatformMath.apply(inverse, Vector3i(state.matrix12[2], state.matrix12[5], state.matrix12[8]))
		forward.y = 0
		state.direction = PlatformMath.quadrant(EntityTransform._normalise(forward))
		_replace_rotation(state, PlatformMath.multiply(PlatformMath.yaw(state.direction << 10), matrix))
	else:
		var z: Vector3i = EntityTransform._normalise(Vector3i(state.matrix12[2], 0, state.matrix12[8]))
		var y := Vector3i(matrix[1], matrix[4], matrix[7])
		var x: Vector3i = EntityTransform._normalise(EntityTransform._cross12(y, z))
		_replace_rotation(state, PackedInt32Array([x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, 0, 0, 0]))
	if not definition.form_book_flags & 4:
		state.entity_angle = PlatformMath.quadrant(PlatformMath.apply(inverse, camera.snapshot().direction_vectors_12[0]))
	state.flags = (state.flags & ~LANDED_CLEAR) | FrogFlags.ON_ENTITY
	state.entity_transform12 = PlatformMath.project(PlatformMath.multiply(state.matrix12, inverse))
	if state.current_entity_index != pose.entity_index:
		result.error = camera.transition_attachment(previous, matrix, not definition.form_book_flags & 2)
	elif not definition.form_book_flags & 2:
		camera.align_y()
	state.current_entity_index = pose.entity_index
	return result

## Carries or centres using advanced entity position, including source coordinate narrowing.
static func carry(state: RunSnapshot, pose: EntitySnapshot) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	if state.mode == FrogMode.CENTRING:
		state.remaining_ticks -= 1
		if state.remaining_ticks == 0:
			state.velocity_16 = Vector3i.ZERO
			state.mode = FrogMode.STATIONARY
			state.entity_offset_16 = state.target_16
			result.animation_ids.append(FrogAnimationCatalog.PANT)
		else:
			state.entity_offset_16 += state.velocity_16
	state.position_16 = PlatformMath.world(pose.matrix12, state.entity_offset_16) * 65536
	return result

## Applies the source attached matrix branch without changing cached translation.
static func update_matrix(state: RunSnapshot, pose: EntitySnapshot) -> void:
	_replace_rotation(state, PlatformMath.multiply(pose.matrix12, state.entity_transform12))

## Advances local airborne XZ with the frozen wide-accumulator matrix operation.
static func airborne(state: RunSnapshot, pose: EntitySnapshot) -> void:
	state.entity_offset_16.x += state.velocity_16.x
	state.entity_offset_16.z += state.velocity_16.z
	var transformed: Vector3i = PlatformMath.apply_fixed(pose.matrix12, state.entity_offset_16)
	state.position_16.x = (pose.matrix12[9] << 16) + transformed.x
	state.position_16.z = (pose.matrix12[11] << 16) + transformed.z
	state.position_16.y += state.velocity_16.y

## Selects local or terrain targets; the coordinator applies ordered hop requests.
static func prepare_jump(state: RunSnapshot, definition: FormContactDefinition, pose: EntitySnapshot, grid: GridDefinition, directions: PackedInt32Array, input: int, is_super: bool, distance: int) -> PlatformJumpResult:
	var result := PlatformJumpResult.new()
	var original: Vector2i = state.entity_cell
	var world_direction: int = directions[input]
	var target_cell: Vector2i
	state.flags &= ~FrogFlags.ON_ENTITY
	if definition.form_book_flags & 4:
		var step_vector: Vector3i = DIRECTIONS[world_direction] * distance / 16
		state.target_16 = (state.world_position + step_vector) * 65536
		state.direction = world_direction
		target_cell = GridQueries.world_to_cell(grid, state.target_16.x >> 16, state.target_16.z >> 16)
	else:
		state.direction = (input + state.entity_angle) & 3
		var offset: Vector3i = DIRECTIONS[state.direction] / 4096
		state.entity_cell += Vector2i(offset.x, offset.z) * distance
		var cell: Vector2i = state.entity_cell
		if cell.x >= 0 and cell.y >= 0 and cell.x < definition.dimensions.x and cell.y < definition.dimensions.y:
			var flags: int = definition.grid_flags[cell.y * definition.dimensions.x + cell.x]
			if flags & GridSquareFlags.USABLE:
				if not _supported_destination(flags, definition.death_type):
					result.error = "Platform hop destination requires an unsupported FORM reaction"
					return result
				state.flags |= FrogFlags.JUMP_FROM_ENTITY | FrogFlags.JUMP_TO_ENTITY
				state.target_16 = Vector3i(definition.offsets.x + cell.x * 256 + 128, definition.height, definition.offsets.y + cell.y * 256 + 128) * 65536
				state.target_y = PlatformMath.apply(pose.matrix12, Vector3i(0, definition.height, 0)).y + pose.matrix12[10]
				result.moved = true
				return result
			if not flags & GridSquareFlags.BOUNCE_WALL_N:
				_block(state, original, result)
				return result
		state.flags = (state.flags & ~FrogFlags.JUMP_TO_ENTITY) | FrogFlags.JUMP_FROM_ENTITY
		var offset_world: Vector3i = DIRECTIONS[world_direction] / 4096
		target_cell = state.cell + Vector2i(offset_world.x, offset_world.z) * distance
	state.forbidden_entity_index = state.current_entity_index
	var stack: GridStackDefinition = grid.stack_at(target_cell)
	if stack == null:
		result.error = "Source platform departure stack lookup lies outside authored storage"
		return result
	var allowed: int = 448 if is_super else 255 if state.square_index >= 0 and grid.squares[state.square_index].flags & GridSquareFlags.EXTEND_HOP_HEIGHT else 200
	for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
		var square: GridSquareDefinition = grid.squares[index]
		if not square.flags & GridSquareFlags.USABLE:
			_block(state, original, result)
			return result
		var height: int = GridQueries.square_height(square)
		var delta: int = state.world_position.y - height
		if not square.flags & GridSquareFlags.WATER and ((delta >= 0 and delta <= allowed) or (delta <= 0 and -delta <= 256)):
			state.flags |= FrogFlags.JUMP_TO_LAND
			state.cell = target_cell
			state.square_index = index
			state.direction = world_direction
			state.target_16.x = (target_cell.x * 256 + grid.base.x + 128) << 16
			state.target_16.z = (target_cell.y * 256 + grid.base.y + 128) << 16
			state.target_y = height
			result.moved = true
			return result
	state.cell = target_cell
	state.square_index = -1
	state.flags = (state.flags | FrogFlags.JUMP_FROM_ENTITY) & ~(FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_TO_ENTITY)
	state.target_y = state.world_position.y
	if definition.form_book_flags & 4:
		result.detach = true
		state.flags &= ~FrogFlags.JUMP_FROM_ENTITY
	else:
		state.target_16 = Vector3i(definition.offsets.x + state.entity_cell.x * 256 + 128, definition.height, definition.offsets.y + state.entity_cell.y * 256 + 128) * 65536
	result.moved = true
	return result

static func _supported_destination(flags: int, death_type: int) -> bool:
	if flags & (GridSquareFlags.CHECKPOINT | GridSquareFlags.CLIFF):
		return false
	if flags & GridSquareFlags.SAFE or flags & GridSquareFlags.POPDEATH:
		return true
	if flags & GridSquareFlags.DEADLY:
		return death_type == 5
	return not flags & (GridSquareFlags.SLIPPY | GridSquareFlags.BOUNCY | GridSquareFlags.FREEFORM_SLIPPY | GridSquareFlags.SIMPLE_SLIPPY)

static func _block(state: RunSnapshot, original: Vector2i, result: PlatformJumpResult) -> void:
	state.entity_cell = original
	state.velocity_16 = Vector3i.ZERO
	state.flags = (state.flags & ~FrogFlags.JUMP_FROM_ENTITY) | FrogFlags.ON_ENTITY
	state.entity_transform12 = PlatformMath.yaw(state.direction << 10)
	result.blocked = true

static func _replace_rotation(state: RunSnapshot, rotation: PackedInt32Array) -> void:
	for index: int in 9:
		state.matrix12[index] = rotation[index]
