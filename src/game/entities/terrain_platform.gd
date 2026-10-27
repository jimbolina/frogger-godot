class_name TerrainPlatform
extends RefCounted
## Source platform-local landing, carrying and departure selection on private state.

const LANDED_CLEAR: int = 2 | 16 | 32 | 64 | 128 | 256 | 65536 | 16384
const DIRECTIONS: Array[Vector3i] = [Vector3i(0, 0, 4096), Vector3i(4096, 0, 0), Vector3i(0, 0, -4096), Vector3i(-4096, 0, 0)]

## Completes SAFE alignment after the coordinator has applied the fall reaction.
static func land(state: GameplayState, definition: FormContactDefinition, contact: FormContactResult, pose: EntitySnapshot, camera: GameplayCamera, previous: PackedInt32Array) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	var matrix: PackedInt32Array = pose.matrix12
	var inverse: PackedInt32Array = PlatformMath.transpose(matrix)
	var local: Vector3i = contact.local_position
	state.attachment.entity_cell = contact.cell
	state.attachment.entity_offset_16 = Vector3i(local.x, contact.height, local.z) * 65536
	var target := Vector3i(local.x, contact.height, local.z)
	var centring: bool = false
	if not definition.form_book_flags & FormContactDefinition.DONT_CENTER_X or absi(local.x) > (definition.dimensions.x - 1) * 128:
		target.x = definition.offsets.x + contact.cell.x * 256 + 128
		centring = true
	if not definition.form_book_flags & FormContactDefinition.DONT_CENTER_Z or absi(local.z) > (definition.dimensions.y - 1) * 128:
		target.z = definition.offsets.y + contact.cell.y * 256 + 128
		centring = true
	state.frog.target_16 = target * 65536
	if centring:
		var delta := Vector3i(PlatformMath.s16(target.x - local.x), 0, PlatformMath.s16(target.z - local.z))
		result.animation_ids.append(FrogAnimationCatalog.STRUGGLE if absi(target.x - local.x) >= 96 or absi(target.z - local.z) >= 96 else FrogAnimationCatalog.PANT)
		var length: int = floori(sqrt(float(PlatformMath.s32(delta.x * delta.x + delta.z * delta.z))))
		state.frog.mode = FrogMode.CENTRING
		state.frog.remaining_ticks = PlatformMath.divide(length, 15) + 1
		state.frog.velocity_16 = Vector3i(PlatformMath.divide(delta.x << 16, state.frog.remaining_ticks), 0, PlatformMath.divide(delta.z << 16, state.frog.remaining_ticks))
		state.frog.position_16 = PlatformMath.world(matrix, state.attachment.entity_offset_16) * 65536
	state.frog.world_position = Vector3i(state.frog.position_16.x >> 16, state.frog.position_16.y >> 16, state.frog.position_16.z >> 16)
	state.frog.target_y = state.frog.world_position.y
	state.frog.old_y = state.frog.target_y
	if not definition.form_book_flags & FormContactDefinition.NO_ROTATION_SNAPPING:
		var forward: Vector3i = PlatformMath.apply(inverse, Vector3i(state.frog.matrix12[2], state.frog.matrix12[5], state.frog.matrix12[8]))
		forward.y = 0
		state.frog.direction = PlatformMath.quadrant(EntityTransform._normalise(forward))
		_replace_rotation(state, PlatformMath.multiply(PlatformMath.yaw(state.frog.direction << 10), matrix))
	else:
		var z: Vector3i = EntityTransform._normalise(Vector3i(state.frog.matrix12[2], 0, state.frog.matrix12[8]))
		var y := Vector3i(matrix[1], matrix[4], matrix[7])
		var x: Vector3i = EntityTransform._normalise(EntityTransform._cross12(y, z))
		_replace_rotation(state, PackedInt32Array([x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, 0, 0, 0]))
	if not definition.form_book_flags & FormContactDefinition.NO_ENTITY_ANGLE:
		state.attachment.entity_angle = PlatformMath.quadrant(PlatformMath.apply(inverse, camera.snapshot().direction_vectors_12[0]))
	state.frog.flags = (state.frog.flags & ~LANDED_CLEAR) | FrogFlags.ON_ENTITY
	state.attachment.entity_transform12 = PlatformMath.project(PlatformMath.multiply(state.frog.matrix12, inverse))
	if state.attachment.current_entity_index != pose.entity_index:
		result.error = camera.transition_attachment(previous, matrix, not definition.form_book_flags & FormContactDefinition.NO_ROTATION_SNAPPING)
	elif not definition.form_book_flags & FormContactDefinition.NO_ROTATION_SNAPPING:
		camera.align_y()
	state.attachment.current_entity_index = pose.entity_index
	return result

## Carries or centres using advanced entity position, including source coordinate narrowing.
static func carry(state: GameplayState, pose: EntitySnapshot) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	if state.frog.mode == FrogMode.CENTRING:
		state.frog.remaining_ticks -= 1
		if state.frog.remaining_ticks == 0:
			state.frog.velocity_16 = Vector3i.ZERO
			state.frog.mode = FrogMode.STATIONARY
			state.attachment.entity_offset_16 = state.frog.target_16
			result.animation_ids.append(FrogAnimationCatalog.PANT)
		else:
			state.attachment.entity_offset_16 += state.frog.velocity_16
	state.frog.position_16 = PlatformMath.world(pose.matrix12, state.attachment.entity_offset_16) * 65536
	return result

## Applies the source attached matrix branch without changing cached translation.
static func update_matrix(state: GameplayState, pose: EntitySnapshot) -> void:
	_replace_rotation(state, PlatformMath.multiply(pose.matrix12, state.attachment.entity_transform12))

## Advances local airborne XZ with the frozen wide-accumulator matrix operation.
static func airborne(state: GameplayState, pose: EntitySnapshot) -> void:
	state.attachment.entity_offset_16.x += state.frog.velocity_16.x
	state.attachment.entity_offset_16.z += state.frog.velocity_16.z
	var transformed: Vector3i = PlatformMath.apply_fixed(pose.matrix12, state.attachment.entity_offset_16)
	state.frog.position_16.x = (pose.matrix12[9] << 16) + transformed.x
	state.frog.position_16.z = (pose.matrix12[11] << 16) + transformed.z
	state.frog.position_16.y += state.frog.velocity_16.y

## Selects local or terrain targets; the coordinator applies ordered hop requests.
static func prepare_jump(state: GameplayState, definition: FormContactDefinition, pose: EntitySnapshot, grid: GridDefinition, directions: PackedInt32Array, input: int, is_super: bool, distance: int, forced: bool = false) -> PlatformJumpResult:
	var result := PlatformJumpResult.new()
	var original: Vector2i = state.attachment.entity_cell
	var world_direction: int = directions[input]
	var target_cell: Vector2i
	state.frog.flags &= ~FrogFlags.ON_ENTITY
	if definition.form_book_flags & FormContactDefinition.NO_ENTITY_ANGLE:
		var step_vector: Vector3i = DIRECTIONS[world_direction] * distance / 16
		state.frog.target_16 = (state.frog.world_position + step_vector) * 65536
		state.frog.direction = world_direction
		target_cell = GridQueries.world_to_cell(grid, state.frog.target_16.x >> 16, state.frog.target_16.z >> 16)
	else:
		state.frog.direction = (input + state.attachment.entity_angle) & 3
		var offset: Vector3i = DIRECTIONS[state.frog.direction] / 4096
		state.attachment.entity_cell += Vector2i(offset.x, offset.z) * distance
		var cell: Vector2i = state.attachment.entity_cell
		if cell.x >= 0 and cell.y >= 0 and cell.x < definition.dimensions.x and cell.y < definition.dimensions.y:
			var flags: int = definition.grid_flags[cell.y * definition.dimensions.x + cell.x]
			if flags & GridSquareFlags.USABLE:
				if not _supported_destination(flags, definition.death_type):
					result.error = "Platform hop destination requires an unsupported FORM reaction"
					return result
				state.frog.flags |= FrogFlags.JUMP_FROM_ENTITY | FrogFlags.JUMP_TO_ENTITY
				state.frog.target_16 = Vector3i(definition.offsets.x + cell.x * 256 + 128, definition.height, definition.offsets.y + cell.y * 256 + 128) * 65536
				state.frog.target_y = PlatformMath.apply(pose.matrix12, Vector3i(0, definition.height, 0)).y + pose.matrix12[10]
				result.moved = true
				return result
			if not flags & GridSquareFlags.BOUNCE_WALL_N:
				_block(state, original, result)
				return result
		state.frog.flags = (state.frog.flags & ~FrogFlags.JUMP_TO_ENTITY) | FrogFlags.JUMP_FROM_ENTITY
		var offset_world: Vector3i = DIRECTIONS[world_direction] / 4096
		target_cell = state.frog.cell + Vector2i(offset_world.x, offset_world.z) * distance
	state.attachment.forbidden_entity_index = state.attachment.current_entity_index
	var stack: GridStackDefinition = grid.stack_at(target_cell)
	if stack == null:
		result.error = "Source platform departure stack lookup lies outside authored storage"
		return result
	var allowed: int = 448 if is_super else 32767 if forced else 255 if state.frog.square_index >= 0 and grid.squares[state.frog.square_index].flags & GridSquareFlags.EXTEND_HOP_HEIGHT else 200
	for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
		var square: GridSquareDefinition = grid.squares[index]
		if not square.flags & GridSquareFlags.USABLE:
			_block(state, original, result)
			return result
		var height: int = GridQueries.square_height(square)
		var delta: int = state.frog.world_position.y - height
		if not square.flags & GridSquareFlags.WATER and ((delta >= 0 and delta <= allowed) or (delta <= 0 and -delta <= 256)):
			state.frog.flags |= FrogFlags.JUMP_TO_LAND
			state.frog.cell = target_cell
			state.frog.square_index = index
			state.frog.direction = world_direction
			state.frog.target_16.x = (target_cell.x * 256 + grid.base.x + 128) << 16
			state.frog.target_16.z = (target_cell.y * 256 + grid.base.y + 128) << 16
			state.frog.target_y = height
			result.moved = true
			return result
	state.frog.cell = target_cell
	state.frog.square_index = -1
	state.frog.flags = (state.frog.flags | FrogFlags.JUMP_FROM_ENTITY) & ~(FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_TO_ENTITY)
	state.frog.target_y = state.frog.world_position.y
	if definition.form_book_flags & FormContactDefinition.NO_ENTITY_ANGLE:
		result.detach = true
		state.frog.flags &= ~FrogFlags.JUMP_FROM_ENTITY
	else:
		state.frog.target_16 = Vector3i(definition.offsets.x + state.attachment.entity_cell.x * 256 + 128, definition.height, definition.offsets.y + state.attachment.entity_cell.y * 256 + 128) * 65536
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

static func _block(state: GameplayState, original: Vector2i, result: PlatformJumpResult) -> void:
	state.attachment.entity_cell = original
	state.frog.velocity_16 = Vector3i.ZERO
	state.frog.flags = (state.frog.flags & ~FrogFlags.JUMP_FROM_ENTITY) | FrogFlags.ON_ENTITY
	state.attachment.entity_transform12 = PlatformMath.yaw(state.frog.direction << 10)
	result.blocked = true

static func _replace_rotation(state: GameplayState, rotation: PackedInt32Array) -> void:
	for index: int in 9:
		state.frog.matrix12[index] = rotation[index]
