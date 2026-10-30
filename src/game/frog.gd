class_name Frog
extends RefCounted
## Frog control, movement, terrain reactions and death over a candidate state.
## Definitions are shared after setup; camera, animation and RNG are tick candidates.

const GRAVITY_16: int = 0x100000
const NO_INPUT: int = 128
var flow_enabled: bool = false
var rewards: Array[RewardDefinition] = GameplayRewards.component_definitions()
var contacts: FrogContacts = FrogContacts.new()
var grid: GridDefinition = null
var controller_directions: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])
var collision_bounds: Rect2i = Rect2i()
var death_height: int = 30000
var theme: int = 0
var map_index: int = -1
var candidate_entities: EntityRun = null
var entity_collision: EntityCollisionDefinition = null
var source_id: String = ""
var resource_id: int = -1
var tick_guard: TickGuard = null
var callback_error: String = ""
var consumed_demo_byte: int = -1
var camera: GameplayCamera = null
var music_pitch_offset: int = 0
var random: SourceRandom = null
var animation_system: FrogAnimationController = null
## Signed map-header frog colour that ResetFrog applies as the custom ambient.
var frog_ambient: Vector3i = Vector3i.ZERO

## Selects the systems belonging to the current transaction.
func begin_tick(next_camera: GameplayCamera, next_random: SourceRandom, next_animation: FrogAnimationController, directions: PackedInt32Array) -> void:
	camera = next_camera
	random = next_random
	animation_system = next_animation
	controller_directions = directions
	callback_error = ""
	consumed_demo_byte = -1

## Validates an isolated observation at a contact boundary.
func check_guard(phase: TickGuard.Phase, state: GameplayState) -> String:
	return tick_guard.check(phase, TickGuardCandidate.from_state(state)) if tick_guard != null else ""

## Selects the first source-ordered directional input.
func first_direction(mask: int) -> int:
	for direction: int in 4:
		if mask & (1 << direction):
			return direction
	return NO_INPUT


## Applies command input to the candidate frog, then advances the croak as ControlFrog does.
func control(state: GameplayState, command: TickCommand, events: Array[TickEvent]) -> String:
	var issue: String = _control_mode(state, command, events)
	if not issue.is_empty():
		return issue
	return FrogCroak.update(self, state, command, events)

func _control_mode(state: GameplayState, command: TickCommand, events: Array[TickEvent]) -> String:
	if state.frog.flags & FrogFlags.MUST_DIE:
		state.frog.flags &= ~FrogFlags.MUST_DIE
		if state.frog.mode != FrogMode.JUMPING or not state.frog.flags & FrogFlags.JUMP_TO_LAND:
			state.frog.remaining_ticks = 0
		state.frog.mode = FrogMode.DYING
		state.frog.death_count = 70
		if camera != null:
			camera.request_death()
		events.append(TickEvent.make(TickEvent.Kind.CAMERA_DEATH))
	if state.frog.start_timer != 0 or not state.frog.flags & FrogFlags.CONTROL_ACTIVE:
		return ""
	if state.frog.mode == FrogMode.SLIPPING_LAND_NONGRID:
		if command.recorded_input_byte < 0 and not command.recorded_input_exhausted and first_direction(command.held_mask) == NO_INPUT and command.pressed_mask & TickCommand.TONGUE:
			var slip_tongue_issue: String = TongueController.start(self, state, events, false)
			if not slip_tongue_issue.is_empty():
				return slip_tongue_issue
		var callback: TerrainCallbackResult = TerrainFreeformSlip.control(state, command, controller_directions, theme)
		if callback.forward_steering:
			if state.frog.square_index < 0:
				return "Freeform forward steering requires a current authored square"
			TerrainFreeformSlip.forward_control(state, grid.squares[state.frog.square_index])
		apply_requests(state, callback, events)
		return callback_error
	if state.frog.mode not in [FrogMode.STATIONARY, FrogMode.JUMPING, FrogMode.CENTRING, FrogMode.SLIPPING_LAND_GRID, FrogMode.SIMPLE_SLIPPING_LAND_GRID]:
		return ""
	if state.frog.mode == FrogMode.JUMPING:
		if command.recorded_input_byte >= 0 or command.recorded_input_exhausted:
			return ""
		if command.pressed_mask & TickCommand.TONGUE:
			var jump_tongue_issue: String = TongueController.start(self, state, events)
			if not jump_tongue_issue.is_empty():
				return jump_tongue_issue
		var pressed: int = first_direction(command.pressed_mask)
		if pressed == NO_INPUT and command.pressed_mask & TickCommand.SUPER_HOP:
			pressed = 8
		if pressed != NO_INPUT and state.frog.buffered_keys < 1:
			state.frog.buffered_keys = 1
			state.frog.buffered_direction = (pressed - controller_directions[0]) & 3 if pressed != 8 else 8
		return ""
	var input: int = NO_INPUT
	state.frog.no_input_timer += 1
	var buffered_mask: int = 16 if state.frog.buffered_direction == 8 else 1 << state.frog.buffered_direction
	if command.recorded_input_byte < 0 and not command.recorded_input_exhausted and state.frog.buffered_keys > 0 and command.held_mask & buffered_mask:
		input = state.frog.buffered_direction
		state.frog.buffered_input_count += 1
	elif state.frog.buffered_input_count > 0:
		state.frog.buffered_input_count -= 1
	state.frog.buffered_keys = 0
	if input == NO_INPUT:
		input = first_direction(command.pressed_mask)
		if input == NO_INPUT and command.pressed_mask & TickCommand.SUPER_HOP:
			input = 8 | NO_INPUT
		if input & NO_INPUT:
			if command.pressed_mask & TickCommand.CAMERA_CLOCKWISE:
				input |= 32
			if command.pressed_mask & TickCommand.CAMERA_ANTICLOCKWISE:
				input |= 64
		if state.frog.powerup_flags & PowerupFlags.AUTO_HOP:
			var held_direction: int = first_direction(command.held_mask)
			if held_direction != NO_INPUT:
				input = held_direction
		if command.pressed_mask & TickCommand.TONGUE:
			input |= 16
		if command.recorded_input_byte >= 0 or command.recorded_input_exhausted:
			if command.recorded_input_exhausted:
				return "Demo input buffer exhausted before duration elapsed"
			input = command.recorded_input_byte
			consumed_demo_byte = input
		if input & 96 and camera == null:
			return "Demo camera action requires an integrated camera definition"
		if input & 96 and camera.allows_manual_turn():
			var entity_matrix: PackedInt32Array = PackedInt32Array()
			if state.attachment.current_entity_index >= 0:
				entity_matrix = contacts.platform_pose(self, state).matrix12
			var clockwise_bit: int = 64 if command.recorded_input_byte >= 0 else 32
			var clockwise: bool = bool(input & clockwise_bit)
			var failure: String = camera.request_turn(1 if clockwise else -1, state.frog.camera_zone_index >= 0, entity_matrix)
			if not failure.is_empty():
				return failure
			state.frog.mode = FrogMode.WAIT_FOR_CAMERA
			events.append(TickEvent.make(TickEvent.Kind.CAMERA_CLOCKWISE) if clockwise else TickEvent.make(TickEvent.Kind.CAMERA_ANTICLOCKWISE))
			return ""
		if input & 16:
			var tongue_issue: String = TongueController.start(self, state, events)
			if not tongue_issue.is_empty():
				return tongue_issue
	if command.recorded_input_byte >= 0 and not input & (NO_INPUT | 8) and (input & ~16) > 3:
		return "Demo directional action contains unsupported reserved bits"
	var is_super: bool = input & 8 != 0
	if is_super:
		input = (state.frog.direction - (state.attachment.entity_angle if state.frog.flags & FrogFlags.ON_ENTITY else controller_directions[0])) & 3
	if not input & NO_INPUT:
		if input & 16 and state.frog.flags & FrogFlags.ON_ENTITY:
			var platform: FormContactDefinition = contacts.platform_definition(self, state)
			if platform != null and platform.form_book_flags & FormContactDefinition.NO_ENTITY_ANGLE:
				return "Simultaneous tongue and directional input on NO_ENTITY_ANGLE indexes outside the source direction table"
		state.frog.no_input_timer = 0
		var failure: String = jump(state, input & 3, events, is_super)
		if not failure.is_empty():
			return failure
	state.frog.current_input = input
	return ""


## Prepares a terrain or platform jump.
func jump(state: GameplayState, direction: int, events: Array[TickEvent], is_super: bool = false, forced: bool = false, distance: int = 1, duration: int = 0) -> String:
	if state.frog.flags & FrogFlags.ON_ENTITY:
		return contacts.jump_platform(self, state, direction, events, is_super, distance, duration, forced)
	direction = controller_directions[direction]
	var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var target_cell: Vector2i = state.frog.cell + offsets[direction] * distance
	for attempt: int in range(distance):
		if grid.stack_at(target_cell) != null:
			break
		target_cell += offsets[direction]
	var stack: GridStackDefinition = grid.stack_at(target_cell)
	var wall: bool = false
	if stack != null:
		if direction in [0, 1] and state.frog.square_index >= 0:
			wall = grid.squares[state.frog.square_index].flags & (GridSquareFlags.BOUNCE_WALL_N if direction == 0 else GridSquareFlags.BOUNCE_WALL_E) != 0
		elif direction in [2, 3]:
			for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
				wall = wall or grid.squares[candidate].flags & (GridSquareFlags.BOUNCE_WALL_N if direction == 2 else GridSquareFlags.BOUNCE_WALL_E) != 0
		if not wall:
			for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
				if grid.squares[candidate].flags & GridSquareFlags.USABLE and grid.squares[candidate].flags & GridSquareFlags.CLIFF and state.frog.world_position.y >= -(stack.cliff_height_byte << 6):
					wall = true
					break
	if wall:
		state.frog.user_target_cell = target_cell
		state.frog.direction = direction
		apply_requests(state, TerrainWallBounce.setup(state, grid), events)
		state.frog.mode = FrogMode.BOUNCY_COBWEB
		return callback_error
	var current_height: int = state.frog.matrix12[10]
	var allowed_up: int = 448 if is_super else 32767 if forced else 200
	if not is_super and not forced and state.frog.square_index >= 0 and grid.squares[state.frog.square_index].flags & GridSquareFlags.EXTEND_HOP_HEIGHT:
		allowed_up = 255
	var index: int = -1
	var height: int = current_height
	var smooth: bool = false
	if stack != null:
		for candidate: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
			var square: GridSquareDefinition = grid.squares[candidate]
			var candidate_height: int = GridQueries.square_height(square)
			if square.flags & GridSquareFlags.USABLE and ((current_height >= candidate_height and current_height - candidate_height <= allowed_up) or (candidate_height >= current_height and candidate_height - current_height <= 256)):
				index = candidate
				height = candidate_height
				smooth = true
				break
		if index < 0:
			for candidate: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
				if grid.squares[candidate].flags & GridSquareFlags.USABLE and GridQueries.square_height(grid.squares[candidate]) >= current_height:
					index = candidate
					height = GridQueries.square_height(grid.squares[candidate])
					break
	if stack != null and stack.square_count > 0 and index < 0 and forced:
		index = stack.first_square_index - 1
		if index < 0 or index >= grid.squares.size():
			return "Source forced-hop leftover layer pointer lies outside authored global storage"
	if stack != null and stack.square_count > 0 and index < 0:
		state.frog.direction = direction
		state.requests.animation_requests += 1
		request_animation(FrogAnimationCatalog.OUCH, state)
		events.append(TickEvent.make(TickEvent.Kind.OUCH))
		return ""
	var roll_request: bool = state.frog.direction == direction and state.frog.buffered_input_count > 3
	if roll_request:
		state.frog.buffered_input_count = 0
	state.frog.direction = direction
	state.frog.cell = target_cell
	state.frog.square_index = index
	if smooth:
		state.frog.flags |= FrogFlags.JUMP_TO_LAND
	else:
		state.frog.flags &= ~FrogFlags.JUMP_TO_LAND
	if is_super:
		state.frog.flags |= FrogFlags.SUPERJUMP
	state.frog.mode = FrogMode.JUMPING
	state.frog.remaining_ticks = 15 if is_super else 3 if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else 6
	if duration > 0:
		state.frog.remaining_ticks = duration
	state.frog.old_y = state.frog.target_y
	state.frog.target_y = height if smooth else current_height
	state.frog.target_16 = Vector3i((target_cell.x * 256 + grid.base.x + 128) * 65536, state.frog.target_16.y, (target_cell.y * 256 + grid.base.y + 128) * 65536)
	var delta: Vector3i = state.frog.target_16 - state.frog.position_16
	@warning_ignore("integer_division")
	state.frog.velocity_16.x = delta.x / state.frog.remaining_ticks
	@warning_ignore("integer_division")
	state.frog.velocity_16.z = delta.z / state.frog.remaining_ticks
	@warning_ignore("integer_division")
	state.frog.velocity_16.y = ((state.frog.target_y - current_height) * 65536) / (state.frog.remaining_ticks + 1) - ((GRAVITY_16 * (state.frog.remaining_ticks + 1)) >> 1)
	var sound_issue: String = play_sound(state, 7 if is_super else 6, 0 if is_super else (state.tick_index & 3) << 7)
	if not sound_issue.is_empty():
		return sound_issue
	state.requests.animation_requests += 1
	request_animation(FrogAnimationCatalog.SUPERJUMP if is_super else FrogAnimationCatalog.SUPERHOP if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else FrogAnimationCatalog.AUTOHOP if state.frog.powerup_flags & PowerupFlags.AUTO_HOP else FrogAnimationCatalog.ROLL if roll_request else FrogAnimationCatalog.HOP, state)
	state.requests.sound_requests += 1
	if is_super or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP or not state.frog.powerup_flags & PowerupFlags.AUTO_HOP:
		state.requests.score_requests += 1
	events.append(TickEvent.make(TickEvent.Kind.SUPER_HOP) if is_super else TickEvent.make(TickEvent.Kind.QUICK_HOP) if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else TickEvent.make(TickEvent.Kind.AUTO_HOP) if state.frog.powerup_flags & PowerupFlags.AUTO_HOP else TickEvent.make(TickEvent.Kind.ROLL) if roll_request else TickEvent.make(TickEvent.Kind.HOP))
	events.append(TickEvent.make(TickEvent.Kind.HOP_SOUND))
	if is_super or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP or not state.frog.powerup_flags & PowerupFlags.AUTO_HOP:
		var reward_issue: String = GameplayRewards.apply(rewards[1 if is_super else 3 if roll_request or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else 0], state, events, random)
		if not reward_issue.is_empty():
			return reward_issue
		events.append(TickEvent.make(TickEvent.Kind.SCORE_10_REQUEST) if is_super else TickEvent.make(TickEvent.Kind.SCORE_50_REQUEST) if roll_request or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else TickEvent.make(TickEvent.Kind.SCORE_5_REQUEST))
	return ""


## Advances the current movement mode by one tick. A landing keeps the grid cell its
## reaction stored (a slip destination), because frozen C's MoveFrog refreshes
## fr_grid_x/z before ReactFrogWithGridFlags and not after it (FROG.C:858-865).
func move(state: GameplayState, events: Array[TickEvent]) -> void:
	if state.attachment.current_entity_index >= 0 and state.frog.mode in [FrogMode.STATIONARY, FrogMode.WAIT_FOR_CAMERA, FrogMode.CENTRING] and state.frog.flags & FrogFlags.ON_ENTITY:
		var was_centring: bool = state.frog.mode == FrogMode.CENTRING
		apply_requests(state, TerrainPlatform.carry(state, contacts.platform_pose(self, state)), events)
		update_world(state)
		if not was_centring:
			state.frog.target_y = state.frog.world_position.y
		if was_centring:
			update_matrix(state)
			return
	if state.frog.mode == FrogMode.SLIPPING_LAND_NONGRID:
		apply_callback(state, TerrainFreeformSlip.move(state, grid), events)
		return
	if state.frog.mode == FrogMode.BOUNCY_COBWEB:
		apply_callback(state, TerrainWallBounce.move(state, grid), events)
		return
	if state.frog.mode in [FrogMode.LEVEL_START_BOUNCE, FrogMode.LEVEL_START_COME_TO_REST]:
		apply_callback(state, TerrainStartup.move(state), events)
		return
	if state.frog.mode in [FrogMode.SLIPPING_LAND_GRID, FrogMode.SIMPLE_SLIPPING_LAND_GRID]:
		apply_callback(state, TerrainGridSlip.move(state, grid), events)
		return
	if state.frog.mode == FrogMode.BOUNCE:
		var callback: TerrainCallbackResult = TerrainGridSlip.move(state, grid, false)
		callback.kill_looping_sound = false
		apply_callback(state, callback, events)
		return
	if state.frog.mode == FrogMode.CLIFF_ROLL:
		apply_callback(state, TerrainCliffRoll.move(state, grid), events)
		return
	if state.frog.mode == FrogMode.STUNNED:
		state.frog.remaining_ticks -= 1
		if state.frog.remaining_ticks == 0:
			state.frog.mode = FrogMode.STATIONARY
			state.requests.animation_requests += 1
			request_animation(FrogAnimationCatalog.PANT, state)
			events.append(TickEvent.make(TickEvent.Kind.PANT))
		update_matrix(state)
		return
	if state.frog.mode == FrogMode.HIT_CHECKPOINT:
		if state.frog.remaining_ticks != 0:
			move_jumping(state, events, false)
		else:
			update_matrix(state)
		state.frog.mode = FrogMode.HIT_CHECKPOINT
		update_world(state)
		return
	if state.frog.mode == FrogMode.DYING:
		var continuing_jump: bool = state.frog.remaining_ticks != 0
		if state.attachment.current_entity_index >= 0 and state.frog.flags & FrogFlags.ON_ENTITY:
			state.frog.position_16 = PlatformMath.world(contacts.platform_pose(self, state).matrix12, state.attachment.entity_offset_16) * 65536
		state.frog.death_count -= 1
		if state.frog.death_count == 0:
			state.frog.flags &= ~FrogFlags.CONTROL_ACTIVE
			state.requests.game_mode_request = 3
			state.completed = true
			events.append(TickEvent.make(TickEvent.Kind.DEATH_COMPLETE))
			events.append(TickEvent.make(TickEvent.Kind.SINGLE_FROG_DIED_REQUEST))
		if state.frog.remaining_ticks != 0:
			move_jumping(state, events, false)
			state.frog.mode = FrogMode.DYING
		else:
			state.frog.position_16 += state.frog.velocity_16
			if map_index == 2:
				var product: Vector3i = state.frog.velocity_16 * 14
				state.frog.velocity_16 = Vector3i(product.x >> 4, product.y >> 4, product.z >> 4)
		update_world(state)
		if not continuing_jump:
			update_matrix(state)
		return
	if state.frog.mode == FrogMode.STATIONARY or state.frog.mode == FrogMode.WAIT_FOR_CAMERA:
		if camera == null or camera.snapshot().turn_wait_complete():
			state.frog.mode = FrogMode.STATIONARY
			state.frog.buffered_keys = 0
		update_matrix(state)
		return
	var landing: bool = state.frog.remaining_ticks == 1 and state.frog.flags & FrogFlags.JUMP_TO_LAND != 0
	move_jumping(state, events)
	var reacted_cell: Vector2i = state.frog.cell
	update_world(state)
	if landing:
		state.frog.cell = reacted_cell
	else:
		update_matrix(state)


## Advances a terrain jump and its landing reaction. Entering freefall copies the jump's
## reference height into old_y, as frozen C's UPDATE_OLD_POS does (fr_old_y = fr_y).
func move_jumping(state: GameplayState, events: Array[TickEvent], react_on_land: bool = true) -> void:
	if state.attachment.current_entity_index >= 0:
		contacts.move_platform_jumping(self, state, events, react_on_land)
		return
	state.frog.remaining_ticks -= 1
	if state.frog.remaining_ticks == 0:
		if state.frog.flags & FrogFlags.JUMP_TO_LAND:
			state.frog.position_16.x = state.frog.target_16.x
			state.frog.position_16.z = state.frog.target_16.z
			land(state, events)
			update_world(state)
			if react_on_land:
				update_matrix(state)
			if react_on_land:
				react(state, grid.squares[state.frog.square_index].flags & 65535, events)
		else:
			state.frog.position_16.x = state.frog.target_16.x
			state.frog.position_16.z = state.frog.target_16.z
			if state.frog.square_index < 0:
				var stack: GridStackDefinition = grid.stack_at(state.frog.cell)
				if stack == null:
					callback_error = "Source final hop stack lookup lies outside authored storage"
					return
				if stack != null:
					for index: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
						if grid.squares[index].flags & GridSquareFlags.USABLE and GridQueries.square_height(grid.squares[index]) >= (state.frog.position_16.y >> 16):
							state.frog.square_index = index
							break
			state.frog.flags &= ~FrogFlags.LANDED_ON_ENTITY_CLEAR_MASK
			state.frog.flags |= FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION
			state.frog.remaining_ticks = 0x7FFFFFF
			state.frog.velocity_16.x = 0
			state.frog.velocity_16.z = 0
			state.frog.old_y = state.frog.target_y
	else:
		state.frog.velocity_16.y += GRAVITY_16
		if state.frog.flags & (FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION) == (FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION) and state.frog.world_position.y - state.frog.old_y >= 0:
			state.requests.animation_requests += 1
			request_animation(FrogAnimationCatalog.FREEFALL if map_index >= 42 and map_index <= 47 else FrogAnimationCatalog.FALLING, state)
			state.frog.flags &= ~FrogFlags.FREEFALL_NO_ANIMATION
			events.append(TickEvent.make(TickEvent.Kind.FALLING))
		state.frog.position_16 += state.frog.velocity_16


## Refreshes whole-unit position and grid coordinates.
func update_world(state: GameplayState) -> void:
	state.frog.world_position = Vector3i(state.frog.position_16.x >> 16, state.frog.position_16.y >> 16, state.frog.position_16.z >> 16)
	state.frog.cell = GridQueries.world_to_cell(grid, state.frog.world_position.x, state.frog.world_position.z)
	state.frog.matrix12[9] = state.frog.world_position.x
	state.frog.matrix12[10] = state.frog.world_position.y
	state.frog.matrix12[11] = state.frog.world_position.z


## Refreshes the stored frog transform.
func update_matrix(state: GameplayState) -> void:
	if state.frog.flags & FrogFlags.ON_ENTITY and state.attachment.current_entity_index >= 0:
		TerrainPlatform.update_matrix(state, contacts.platform_pose(self, state))
	elif state.attachment.current_entity_index >= 0 and state.frog.flags & (FrogFlags.JUMP_FROM_ENTITY | FrogFlags.JUMP_TO_LAND) == FrogFlags.JUMP_FROM_ENTITY:
		var facing: Vector3i = PlatformMath.apply(contacts.platform_pose(self, state).matrix12, TerrainPlatform.DIRECTIONS[state.frog.direction])
		state.frog.matrix12 = TerrainMatrix.update(state.frog.matrix12, state.frog.flags, state.frog.direction, null, facing)
	else:
		state.frog.matrix12 = TerrainMatrix.update(state.frog.matrix12, state.frog.flags, state.frog.direction, grid.squares[state.frog.square_index] if state.frog.square_index >= 0 else null)
	if state.frog.flags & FrogFlags.SCALING_UP:
		state.frog.scale += PlatformMath.divide(5120 - state.frog.scale, 4 - state.frog.scale_timer)
		state.frog.scale_timer += 1
		if state.frog.scale_timer == 4:
			state.frog.flags &= ~FrogFlags.SCALING_UP
			state.frog.flags |= FrogFlags.SCALING_DOWN
			state.frog.scale_timer = 4
		_scale_matrix(state.frog)
	elif state.frog.flags & FrogFlags.SCALING_DOWN:
		state.frog.scale += PlatformMath.divide(4096 - state.frog.scale, state.frog.scale_timer)
		state.frog.scale_timer -= 1
		if state.frog.scale_timer == 0:
			state.frog.flags &= ~FrogFlags.SCALING_DOWN
		_scale_matrix(state.frog)

func _scale_matrix(state: FrogState) -> void:
	for index: int in 9:
		state.matrix12[index] = PlatformMath.s16(PlatformMath.s32(state.matrix12[index] * state.scale) >> 12)


## Applies terrain landing and fall reactions.
func land(state: GameplayState, events: Array[TickEvent]) -> void:
	var flags: int = grid.squares[state.frog.square_index].flags
	if not flags & (GridSquareFlags.DEADLY | GridSquareFlags.WATER | GridSquareFlags.POPDEATH):
		state.frog.position_16 = GridQueries.square_centre(grid, grid.squares[state.frog.square_index]) * 65536
	state.frog.target_y = state.frog.position_16.y >> 16
	var distance: int = state.frog.target_y - state.frog.old_y
	react_fall(state, distance, flags, events)
	state.attachment.current_entity_index = -1
	state.attachment.forbidden_entity_index = -1
	state.frog.velocity_16 = Vector3i.ZERO
	state.frog.old_y = state.frog.target_y
	state.frog.flags &= ~(FrogFlags.ON_ENTITY | FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY | FrogFlags.SUPERJUMP | FrogFlags.JUMP_TO_LAND | FrogFlags.FREEFALL | FrogFlags.FORCEDJUMP | FrogFlags.JUMP_FROM_COLLPRIM | FrogFlags.JUMP_ON_SPOT)
	if entity_collision != null and entity_collision.platforms_enabled and camera != null and camera.snapshot().twist_counter == 0:
		camera.align_y()
	if entity_collision != null and entity_collision.platforms_enabled:
		state.frog.direction = PlatformMath.quadrant(Vector3i(state.frog.matrix12[2], state.frog.matrix12[5], state.frog.matrix12[8]))


## Selects the source landing response for fall distance.
func react_fall(state: GameplayState, distance: int, flags: int, events: Array[TickEvent]) -> void:
	state.frog.mode = FrogMode.STATIONARY
	if flags & GridSquareFlags.SOFT or distance <= 512:
		state.requests.animation_requests += 1
		request_animation(FrogAnimationCatalog.PANT, state)
		events.append(TickEvent.make(TickEvent.Kind.PANT))
	elif distance <= 1024:
		state.frog.mode = FrogMode.STUNNED
		state.frog.remaining_ticks = 45
		if not play_sound(state, 30).is_empty():
			return
		state.requests.sound_requests += 1
		state.requests.animation_requests += 1
		request_animation(FrogAnimationCatalog.CRASH, state)
		if camera != null:
			camera.request_shake(128, 45, 20480, random.next_value("camera_stun_shake_x"), random.next_value("camera_stun_shake_y"))
		events.append(TickEvent.make(TickEvent.Kind.STUN_SOUND))
		events.append(TickEvent.make(TickEvent.Kind.CRASH))
		events.append(TickEvent.make(TickEvent.Kind.CAMERA_STUN_SHAKE))
	else:
		if flags & GridSquareFlags.DEADLY:
			if theme == 3:
				if not play_sound(state, 14).is_empty():
					return
				state.requests.sound_requests += 1
			kill(state, 12 if theme == 3 else 8, theme != 3, events)
		elif flags & GridSquareFlags.POPDEATH:
			kill(state, 23, false, events)
		elif flags & GridSquareFlags.WATER:
			kill(state, 8, true, events)
			events.append(TickEvent.splash(_translation(state)))
			if not play_sound(state, 2).is_empty():
				return
			state.requests.sound_requests += 1
		else:
			kill(state, 2, false, events)


## Applies the selected surface reaction.
func react(state: GameplayState, flags: int, events: Array[TickEvent]) -> void:
	flags &= 65535
	if flags & ~(GridSquareFlags.USABLE | GridSquareFlags.SAFE | GridSquareFlags.DEADLY | GridSquareFlags.WATER | GridSquareFlags.SLIPPY | GridSquareFlags.BOUNCY | GridSquareFlags.CHECKPOINT | GridSquareFlags.FREEFORM_SLIPPY | GridSquareFlags.SOFT | GridSquareFlags.EXTEND_HOP_HEIGHT | GridSquareFlags.SIMPLE_SLIPPY | GridSquareFlags.CLIFF | GridSquareFlags.POPDEATH | GridSquareFlags.BOUNCE_WALL_N | GridSquareFlags.BOUNCE_WALL_E):
		events.append(TickEvent.make(TickEvent.Kind.UNKNOWN_TERRAIN_FLAGS_IGNORED))
	if not flags & GridSquareFlags.USABLE:
		return
	if flags & GridSquareFlags.CLIFF:
		if state.frog.flags & FrogFlags.CONTROL_ACTIVE:
			apply_requests(state, TerrainCliffRoll.setup(state, grid), events)
			state.frog.mode = FrogMode.CLIFF_ROLL
		return
	if flags & GridSquareFlags.SAFE:
		return
	if flags & GridSquareFlags.DEADLY:
		kill(state, 12 if theme == 3 else 8, theme != 3, events)
		if not play_sound(state, 12).is_empty():
			return
		state.requests.sound_requests += 1
	elif flags & GridSquareFlags.POPDEATH:
		kill(state, 23, false, events)
		if not play_sound(state, 17).is_empty():
			return
		state.requests.sound_requests += 1
	elif flags & GridSquareFlags.WATER:
		kill(state, 8, true, events)
		events.append(TickEvent.splash(_translation(state)))
		if not play_sound(state, 2).is_empty():
			return
		state.requests.sound_requests += 1
	elif flags & (GridSquareFlags.SLIPPY | GridSquareFlags.SIMPLE_SLIPPY):
		var mode: int = FrogMode.SLIPPING_LAND_GRID if flags & GridSquareFlags.SLIPPY else FrogMode.SIMPLE_SLIPPING_LAND_GRID
		var callback: TerrainCallbackResult = TerrainGridSlip.setup(state, grid, mode == FrogMode.SIMPLE_SLIPPING_LAND_GRID, theme)
		apply_requests(state, callback, events)
		state.frog.mode = mode
	elif flags & GridSquareFlags.FREEFORM_SLIPPY:
		apply_requests(state, TerrainFreeformSlip.setup(state), events)
		state.frog.mode = FrogMode.SLIPPING_LAND_NONGRID
	elif flags & GridSquareFlags.BOUNCY:
		callback_error = bounce(state, events)


## Enters the source bounce user mode: a forced two-cell, fifteen-tick jump in the facing direction.
func bounce(state: GameplayState, events: Array[TickEvent]) -> String:
	var issue: String = jump(state, (state.frog.direction - controller_directions[0]) & 3, events, false, true, 2, 15)
	state.frog.mode = FrogMode.BOUNCE
	return issue


## Applies a FORM BOUNCY cell: forbids the entity, snaps XZ to its translation, then bounces.
func bounce_from_entity(state: GameplayState, entity_index: int, entity_matrix12: PackedInt32Array, events: Array[TickEvent]) -> String:
	state.attachment.forbidden_entity_index = entity_index
	state.frog.position_16.x = PlatformMath.s32(entity_matrix12[9] << 16)
	state.frog.position_16.z = PlatformMath.s32(entity_matrix12[11] << 16)
	update_world(state)
	return bounce(state, events)


## Requests death animation and updates the candidate death state.
func kill(state: GameplayState, animation: int, down_velocity: bool, events: Array[TickEvent]) -> void:
	if state.frog.mode in [FrogMode.DYING, FrogMode.HIT_CHECKPOINT] or state.frog.flags & FrogFlags.MUST_DIE:
		return
	state.frog.flags &= ~FrogFlags.CONTROL_ACTIVE
	if state.frog.lives > 0:
		state.requests.life_decrement_requested = true
		if flow_enabled:
			state.frog.lives -= 1
	if state.frog.lives <= (0 if flow_enabled else 1):
		state.frog.flags &= ~FrogFlags.ACTIVE
	state.frog.flags |= FrogFlags.MUST_DIE
	state.requests.animation_requests += 1
	request_animation(animation, state)
	if camera != null:
		camera.request_fixed()
	state.frog.death_equate = animation
	if down_velocity:
		state.frog.velocity_16 = Vector3i(0, 65536, 0)
	elif state.frog.mode != FrogMode.JUMPING or not state.frog.flags & FrogFlags.JUMP_TO_LAND:
		state.frog.velocity_16 = Vector3i.ZERO
	if theme == 10 and animation in [FrogAnimationCatalog.DROWN, FrogAnimationCatalog.FLOP]:
		state.requests.death_fire_requested = true
		state.requests.death_scale_colour = Vector3i(24, 0, 0)
		FrogTint.set_scale_colours(state.frog, state.requests.death_scale_colour)
		state.requests.animation_requests += 1
		request_animation(FrogAnimationCatalog.DROWN, state)
		events.append(TickEvent.make(TickEvent.Kind.DEATH_FIRE_PARTICLE_REQUEST))
	events.append(TickEvent.death_animation(animation))
	events.append(TickEvent.make(TickEvent.Kind.CAMERA_FIXED))


## Checks world bounds, terrain height and collision death.
func collide(state: GameplayState, events: Array[TickEvent]) -> bool:
	if state.frog.mode == FrogMode.WAIT_FOR_CAMERA and (camera == null or camera.snapshot().twist_counter == 0):
		return false
	if state.frog.mode in [FrogMode.DYING, FrogMode.HIT_CHECKPOINT, FrogMode.CHECKPOINT_COLLECTED] or state.frog.flags & FrogFlags.MUST_DIE:
		return false
	var p: Vector3i = state.frog.world_position
	if p.x < collision_bounds.position.x or p.x > collision_bounds.end.x or p.z < collision_bounds.position.y or p.z > collision_bounds.end.y:
		kill(state, 2, false, events)
		return false
	if state.frog.flags & FrogFlags.FREEFALL and state.frog.square_index >= 0 and p.y > GridQueries.square_height(grid.squares[state.frog.square_index]):
		land(state, events)
		update_world(state)
		react(state, grid.squares[state.frog.square_index].flags & 65535, events)
		return false
	if p.y > death_height:
		state.frog.world_position.y = death_height
		state.frog.velocity_16 = Vector3i.ZERO
		kill(state, 8, true, events)
		events.append(TickEvent.splash(state.frog.world_position))
		if not play_sound(state, 12 if theme in [1, 8] else 1).is_empty():
			return false
		state.requests.sound_requests += 1
		return false
	return true


func _translation(state: GameplayState) -> Vector3i:
	return Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])


## Allocates source sound immediately and retains any failure for the gameplay transaction.
func play_sound(state: GameplayState, sound_id: int, pitch_offset: int = 0) -> String:
	var issue: String = GameplaySound.play(state, random, sound_id, pitch_offset)
	if not issue.is_empty():
		callback_error = issue
	return issue


## Records and forwards a logical animation request.
func request_animation(animation_id: int, state: GameplayState) -> void:
	state.requests.last_animation_request = animation_id
	if animation_system != null:
		animation_system.request(animation_id)


## Refreshes source provenance and observed terrain facts.
func sync_facts(state: GameplayState) -> void:
	state.diagnostics.source_id = source_id
	state.diagnostics.resource_id = resource_id
	state.diagnostics.map_index = map_index
	state.frog.destination_cell = GridQueries.world_to_cell(grid, state.frog.target_16.x >> 16, state.frog.target_16.z >> 16)
	if entity_collision != null and entity_collision.platforms_enabled and (state.frog.flags & FrogFlags.FREEFALL or (state.attachment.current_entity_index < 0 and state.frog.mode != FrogMode.JUMPING)):
		state.frog.destination_cell = state.frog.cell
	elif state.attachment.current_entity_index >= 0 and not state.frog.flags & FrogFlags.JUMP_TO_LAND:
		var target: Vector3i = PlatformMath.world(contacts.platform_pose(self, state).matrix12, state.frog.target_16)
		state.frog.destination_cell = GridQueries.world_to_cell(grid, target.x, target.z)
	state.frog.square_flags = 0
	state.diagnostics.square_source_offset = -1
	state.diagnostics.polygon_index = -1
	state.diagnostics.polygon_source_offset = -1
	if state.frog.square_index >= 0:
		var square: GridSquareDefinition = grid.squares[state.frog.square_index]
		state.frog.square_flags = square.flags
		state.diagnostics.square_source_offset = square.source_offset
		state.diagnostics.polygon_index = square.polygon_index
		state.diagnostics.polygon_source_offset = square.polygon_source_offset


## Applies callback output to candidate systems.
func apply_requests(state: GameplayState, callback: TerrainCallbackResult, events: Array[TickEvent]) -> void:
	callback_error = callback.error
	for animation_id: int in callback.animation_ids:
		state.requests.animation_requests += 1
		request_animation(animation_id, state)
	if callback.kill_animation >= 0:
		kill(state, callback.kill_animation, false, events)
	if callback.start_slipping_sound:
		events.append(TickEvent.make(TickEvent.Kind.SLIPPING_LOOP_START))
	if callback.kill_looping_sound:
		events.append(TickEvent.make(TickEvent.Kind.SLIPPING_LOOP_STOP))
	if callback.create_slide_particles:
		events.append(TickEvent.make(TickEvent.Kind.SLIDE_PARTICLES_REQUEST))
	if callback.kill_slide_particles:
		events.append(TickEvent.make(TickEvent.Kind.SLIDE_PARTICLES_STOP))
	if callback.setup_mode_request == FrogMode.CLIFF_ROLL:
		apply_requests(state, TerrainCliffRoll.setup(state, grid), events)
		state.frog.mode = FrogMode.CLIFF_ROLL


## Applies source callback flags in their original order.
func apply_callback(state: GameplayState, callback: TerrainCallbackResult, events: Array[TickEvent]) -> void:
	apply_requests(state, callback, events)
	if callback.land_requested:
		land(state, events)
	if callback.callback_flags & TerrainCallbackResult.UPDATE_POS:
		update_world(state)
	if callback.callback_flags & TerrainCallbackResult.UPDATE_MATRIX:
		update_matrix(state)
	if callback.callback_flags & TerrainCallbackResult.REACT_WITH_FLAGS:
		react(state, callback.react_flags & 65535, events)
	if callback.callback_flags & TerrainCallbackResult.UPDATE_OLD_POS:
		state.frog.old_position_16 = state.frog.position_16



## Detached result of validating and preparing the frog's initial state.
class StartResult:
	extends RefCounted
	var error: String = ""
	var state: GameplayState
	var directions: PackedInt32Array = PackedInt32Array()

## Prepares frog reset state without changing committed systems.
func prepare_start(initial: RunStart, default_cell: Vector2i, default_direction: int) -> StartResult:
	var prepared := StartResult.new()
	if grid == null:
		prepared.error = "Terrain run has no validated grid"
		return prepared
	var cell: Vector2i = default_cell
	var direction: int = default_direction
	var powers: int = 0
	var directions := PackedInt32Array([0, 1, 2, 3])
	if initial != null:
		powers = initial.powerup_flags
		if initial.spawn_cell != Vector2i(-1, -1):
			cell = initial.spawn_cell
		if initial.spawn_direction != -1:
			direction = initial.spawn_direction
		if not initial.controller_directions.is_empty():
			directions = initial.controller_directions.duplicate()
	if directions.size() != 4:
		prepared.error = "Controller directions require four cardinal values"
		return prepared
	for i: int in 4:
		if directions[i] != ((directions[0] + i) & 3):
			prepared.error = "Controller directions must form a cardinal camera rotation"
			return prepared
	var stack: GridStackDefinition = grid.stack_at(cell)
	if powers & ~7 or direction < 0 or direction > 3 or stack == null or stack.square_count == 0:
		prepared.error = "Terrain run start requires a bounded terrain cell, direction 0..3 and supported powerups"
		return prepared
	var index: int = stack.first_square_index + stack.square_count - 1
	var state := GameplayState.new()
	state.frog.cell = cell
	state.frog.direction = direction
	state.frog.square_index = index
	state.frog.powerup_flags = powers
	if initial != null:
		if initial.quick_jump_timer < 0 or initial.quick_jump_timer > 65535 or initial.auto_hop_timer < 0 or initial.auto_hop_timer > 65535 or initial.super_tongue_timer < 0 or initial.super_tongue_timer > 65535:
			prepared.error = "Modifier timers must fit source unsigned16 values"
			return prepared
		state.frog.quick_jump_timer = initial.quick_jump_timer
		state.frog.auto_hop_timer = initial.auto_hop_timer
		state.frog.super_tongue_timer = initial.super_tongue_timer
	state.frog.position_16 = GridQueries.square_centre(grid, grid.squares[index]) * 65536
	state.frog.world_position = Vector3i(state.frog.position_16.x >> 16, state.frog.position_16.y >> 16, state.frog.position_16.z >> 16)
	state.frog.lives = initial.lives if initial != null else 3
	state.frog.old_y = state.frog.position_16.y >> 16
	state.frog.target_y = state.frog.old_y
	state.frog.old_position_16 = state.frog.position_16
	state.frog.matrix12[9] = state.frog.world_position.x
	state.frog.matrix12[10] = state.frog.world_position.y
	state.frog.matrix12[11] = state.frog.world_position.z
	state.frog.matrix12 = TerrainMatrix.update(state.frog.matrix12, state.frog.flags, state.frog.direction, grid.squares[index])
	state.frog.initial_cell = cell
	FrogTint.reset(state.frog, frog_ambient)
	state.frog.start_mode = initial.start_mode if initial != null else 0
	if state.frog.start_mode < 0 or state.frog.start_mode > 2:
		prepared.error = "Start mode must select component, fast reset or single-start bounce"
		return prepared
	state.frog.start_target_16 = state.frog.position_16.y
	if state.frog.start_mode == RunStart.Mode.SINGLE_START:
		state.frog.position_16.y -= 6400 << 12
		state.frog.mode = FrogMode.LEVEL_START_BOUNCE
		update_world(state)
		state.frog.old_position_16 = state.frog.position_16
		state.frog.old_y = state.frog.world_position.y
		state.frog.target_y = state.frog.old_y
	elif state.frog.start_mode == RunStart.Mode.FAST_RESET:
		state.frog.mode = FrogMode.WAIT_FOR_CAMERA
	prepared.state = state
	prepared.directions = directions
	return prepared

## Applies the source script ejection operands as grid distance and jump duration.
func eject(state: GameplayState, grid_delta: int, duration: int, events: Array[TickEvent]) -> String:
	if duration == 0:
		if state.frog.mode == FrogMode.DYING:
			return ""
		contacts.detach_platform(self, state, events)
		if not callback_error.is_empty():
			return callback_error
		state.frog.mode = FrogMode.JUMPING
		state.frog.remaining_ticks = 65535
		state.frog.velocity_16 = Vector3i.ZERO
		state.frog.flags &= ~FrogFlags.LANDED_ON_LAND_CLEAR_MASK
		state.requests.animation_requests += 1
		request_animation(FrogAnimationCatalog.FREEFALL, state)
		return ""
	if duration < 0 or grid_delta < 0:
		return "Unsafe negative ejection jump operands"
	var direction: int = (state.frog.direction - (state.attachment.entity_angle if state.frog.flags & FrogFlags.ON_ENTITY else controller_directions[0])) & 3
	return jump(state, direction, events, false, true, grid_delta, duration)
