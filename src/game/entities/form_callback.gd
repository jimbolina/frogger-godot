class_name FormCallback
extends RefCounted
## Typed source FORM reactions, independent of executable addresses.

enum Kind { NONE, BLOCK, WATERFALL_BLOCK, FALL_BLOCK, ORG_FLY_SCORE, UNKNOWN }

## Applies a verified primitive callback to the private gameplay candidate.
static func apply(kind: Kind, frog: Frog, state: GameplayState, entity_index: int, events: Array[TickEvent]) -> String:
	if kind == Kind.ORG_FLY_SCORE:
		return GameplayRewards.apply(frog.rewards[8], state, events, frog.random)
	if kind == Kind.BLOCK and state.frog.mode != FrogMode.STATIONARY:
		frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
		state.frog.remaining_ticks = 0
		state.frog.velocity_16 = Vector3i.ZERO
		return ""
	if not state.frog.flags & FrogFlags.ACTIVE:
		return ""
	match kind:
		Kind.NONE:
			return ""
		Kind.BLOCK:
			state.frog.position_16 = state.frog.old_position_16
			frog.update_world(state)
			state.frog.cell = GridQueries.world_to_cell(frog.grid, state.frog.world_position.x, state.frog.world_position.z)
			if state.attachment.current_entity_index >= 0:
				var pose: EntitySnapshot = frog.contacts.platform_pose(frog, state)
				var form: FormContactDefinition = frog.contacts.platform_definition(frog, state)
				if pose == null or form == null:
					return "Block callback requires the current entity pose and FORM"
				var delta := Vector3i.ZERO
				for axis: int in 3:
					delta[axis] = PlatformMath.s16(state.frog.matrix12[9 + axis] - pose.matrix12[9 + axis])
				var local: Vector3i = PlatformMath.apply(PlatformMath.transpose(pose.matrix12), delta)
				state.attachment.entity_offset_16.x = local.x << 16
				state.attachment.entity_offset_16.z = local.z << 16
				state.attachment.entity_cell = Vector2i((local.x - form.offsets.x) >> 8, (local.z - form.offsets.y) >> 8)
			state.frog.flags |= FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY
			state.frog.remaining_ticks = 1
		Kind.WATERFALL_BLOCK:
			if state.attachment.current_entity_index >= 0:
				return frog.eject(state, 0, 0, events)
		Kind.FALL_BLOCK:
			var cell: Vector2i = GridQueries.world_to_cell(frog.grid, state.frog.matrix12[9], state.frog.matrix12[11])
			var stack: GridStackDefinition = frog.grid.stack_at(cell)
			if stack == null:
				return "Fall-block callback grid lookup lies outside authored storage"
			if frog.theme == 1:
				for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
					if frog.grid.squares[index].flags & GridSquareFlags.DEADLY:
						state.attachment.current_entity_index = -1
						state.frog.mode = FrogMode.JUMPING
						state.frog.flags &= ~FrogFlags.LANDED_ON_LAND_CLEAR_MASK
						state.frog.square_index = index
						state.frog.cell = Vector2i(cell.y, cell.y)
						state.frog.remaining_ticks = 65535
						state.attachment.forbidden_entity_index = entity_index
						state.frog.velocity_16.x >>= 1
						state.frog.velocity_16.z >>= 1
						state.frog.flags |= FrogFlags.JUMP_FROM_COLLPRIM | FrogFlags.FREEFALL
						break
			else:
				var issue: String = frog.eject(state, 0, 0, events)
				if not issue.is_empty():
					return issue
				state.frog.cell = cell
				state.frog.square_index = -1
				for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
					if frog.grid.squares[index].flags & GridSquareFlags.USABLE:
						state.frog.square_index = index
						state.frog.flags |= FrogFlags.FREEFALL
						break
		_:
			return "Unsupported typed FORM collision callback"
	return ""
