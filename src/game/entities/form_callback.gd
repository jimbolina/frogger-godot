class_name FormCallback
extends RefCounted
## Typed source FORM reactions, independent of executable addresses.

enum Kind { NONE, BLOCK, WATERFALL_BLOCK, FALL_BLOCK, ORG_FLY_SCORE, UNKNOWN, BUTTERFLY_SCORE, VOL_COLOUR_SWITCH, CAV_FIREFLY_SCORE, CRUSHER_BOUNCE_BACK, TRIGGER }

const CRUSHER_JUMP_TICKS: int = 6
## Source cr_count left by a user-mode Swamp retarget.
const CRUSHER_USER_COUNT: int = 4
const SWAMP_THEME: int = 7

## Applies a verified primitive callback to the private gameplay candidate.
static func apply(kind: Kind, frog: Frog, state: GameplayState, entity_index: int, events: Array[TickEvent]) -> String:
	if kind == Kind.VOL_COLOUR_SWITCH:
		if frog.candidate_entities == null:
			return "Colour-switch callback requires candidate entities"
		var result: EntityCustomResult = frog.candidate_entities.contact_colour_switch(entity_index, state)
		if not result.error.is_empty():
			return result.error
		state.entities = frog.candidate_entities.snapshot()
		if not result.frog_matrix12.is_empty():
			state.frog.matrix12 = result.frog_matrix12.duplicate()
		return ""
	if kind == Kind.TRIGGER:
		if frog.candidate_entities == null:
			return "Trigger callback requires candidate entities"
		var trigger_issue: String = frog.candidate_entities.contact_trigger(entity_index)
		if not trigger_issue.is_empty():
			return trigger_issue
		state.entities = frog.candidate_entities.snapshot()
		state.attachment.forbidden_entity_index = entity_index
		state.frog.flags |= FrogFlags.JUMP_FROM_COLLPRIM
		return ""
	if kind == Kind.ORG_FLY_SCORE:
		events.append(TickEvent.reward(8).for_entity(entity_index))
		return GameplayRewards.apply(frog.rewards[8], state, events, frog.random)
	if kind == Kind.CAV_FIREFLY_SCORE:
		if state.entity_environment == null:
			return "Firefly callback requires the shared entity environment"
		events.append(TickEvent.reward(8).for_entity(entity_index))
		var issue: String = GameplayRewards.apply(frog.rewards[8], state, events, frog.random)
		if not issue.is_empty():
			return issue
		state.entity_environment.light_max_squared = (state.entity_environment.light_max_squared + 8) & 0xffffffff
		state.entity_environment.light_min_squared = (state.entity_environment.light_min_squared + 8) & 0xffffffff
		return ""
	if kind == Kind.BUTTERFLY_SCORE:
		if frog.entity_collision != null:
			for definition: EntityDefinition in frog.entity_collision.entities:
				if definition.entity_index == entity_index and definition.butterfly_reward != null and definition.butterfly_type >= 0 and definition.butterfly_type < EntityBonusFly.REWARD_IDS.size():
					events.append(TickEvent.reward(EntityBonusFly.REWARD_IDS[definition.butterfly_type]).for_entity(entity_index))
					return GameplayRewards.apply(definition.butterfly_reward, state, events, frog.random)
		return "Butterfly callback requires its decoded pickup reward"
	if kind == Kind.CRUSHER_BOUNCE_BACK:
		if frog.theme == SWAMP_THEME:
			if frog.candidate_entities == null:
				return "Swamp crusher callback requires candidate entities"
			var crusher_issue: String = frog.candidate_entities.contact_swamp_crusher(entity_index, frog, state, events)
			if not crusher_issue.is_empty():
				return crusher_issue
			state.entities = frog.candidate_entities.snapshot()
			return ""
		return crusher_bounce_back(frog.grid, state, entity_index)
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


## Returns the source crusher step away from a facing: cell delta in XY and the new facing in Z.
static func crusher_step(direction: int) -> Vector3i:
	match direction:
		0:
			return Vector3i(0, -1, 2)
		1:
			return Vector3i(-1, 0, 3)
		2:
			return Vector3i(0, 1, 0)
		3:
			return Vector3i(1, 0, 1)
	return Vector3i(0, 0, direction)


## Applies the non-Swamp SwpCrusherCallback handler, which tests only the target stack's first square.
static func crusher_bounce_back(grid: GridDefinition, state: GameplayState, entity_index: int) -> String:
	var step: Vector3i = crusher_step(state.frog.direction)
	return crusher_bounce_to(grid, state, entity_index, state.frog.cell + Vector2i(step.x, step.y), step)


## Applies the shared SwpCrusherCallback bounce to a target cell, testing only its stack's first square;
## step.z is the facing for a normal jump. A user-mode retarget sets the supplied crusher count to 4,
## which only the Swamp branch passes.
static func crusher_bounce_to(grid: GridDefinition, state: GameplayState, entity_index: int, cell: Vector2i, step: Vector3i, crusher: EntityCustomState = null) -> String:
	var stack: GridStackDefinition = grid.stack_at(cell) if grid != null else null
	if stack == null:
		return "Crusher callback grid lookup lies outside authored storage"
	if stack.square_count == 0 or not grid.squares[stack.first_square_index].flags & GridSquareFlags.USABLE:
		return ""
	var index: int = stack.first_square_index
	var target_x: int = PlatformMath.s16((cell.x << 8) + grid.base.x + 128)
	var target_z: int = PlatformMath.s16((cell.y << 8) + grid.base.y + 128)
	state.frog.cell = cell
	state.frog.square_index = index
	if state.frog.mode >= FrogMode.THROW_1:
		state.frog.remaining_ticks = CRUSHER_JUMP_TICKS
		state.frog.target_16 = Vector3i(target_x, PlatformMath.s16(GridQueries.square_height(grid.squares[index])), target_z) * 65536
		var velocity := Vector3i.ZERO
		for axis: int in 3:
			velocity[axis] = PlatformMath.divide(PlatformMath.s32(state.frog.target_16[axis] - state.frog.position_16[axis]), CRUSHER_JUMP_TICKS)
		state.frog.velocity_16 = velocity
		if crusher != null:
			crusher.count = CRUSHER_USER_COUNT
		return ""
	state.frog.flags |= FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_FROM_COLLPRIM
	state.frog.direction = step.z
	state.frog.target_16.x = target_x << 16
	state.frog.target_16.z = target_z << 16
	state.frog.mode = FrogMode.JUMPING
	state.attachment.forbidden_entity_index = entity_index
	state.frog.remaining_ticks = CRUSHER_JUMP_TICKS
	state.frog.old_y = state.frog.target_y
	var rise: int = PlatformMath.s32((state.frog.target_y - state.frog.matrix12[10]) << 16)
	state.frog.velocity_16.x = PlatformMath.divide(PlatformMath.s32(state.frog.target_16.x - state.frog.position_16.x), CRUSHER_JUMP_TICKS)
	state.frog.velocity_16.y = PlatformMath.divide(rise, CRUSHER_JUMP_TICKS + 1) - ((Frog.GRAVITY_16 * (CRUSHER_JUMP_TICKS + 1)) >> 1)
	state.frog.velocity_16.z = PlatformMath.divide(PlatformMath.s32(state.frog.target_16.z - state.frog.position_16.z), CRUSHER_JUMP_TICKS)
	state.frog.matrix12[9] += state.frog.velocity_16.x >> 15
	state.frog.matrix12[11] += state.frog.velocity_16.z >> 15
	return ""
