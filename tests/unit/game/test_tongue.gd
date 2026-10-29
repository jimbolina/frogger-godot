extends GutTest
## Source tongue timing, detached state and terrain obstruction boundaries.

func _grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(6, 6)
	for index: int in 36:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.vertices.assign([Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO])
		grid.squares.append(square)
	return grid

func test_clock_grabs_at_eight_and_collects_once_at_twenty() -> void:
	var tongue := TongueState.new()
	assert_true(tongue.start(7))
	for tick: int in range(1, 20):
		assert_eq(tongue.advance(), -1)
		assert_false(tongue.start(9))
		if tick == 8:
			assert_eq(tongue.mode, TongueState.Mode.GRAB)
			assert_eq(tongue.counter, 4)
		if tick == 12:
			assert_eq(tongue.mode, TongueState.Mode.IN)
			assert_eq(tongue.section, 8)
	assert_eq(tongue.advance(), 7)
	assert_eq(tongue.mode, TongueState.Mode.IDLE)
	assert_eq(tongue.advance(), -1)
	assert_eq(tongue.target_index, -1)

func test_eye_cleaning_takes_twenty_four_ticks_and_copy_is_detached() -> void:
	var tongue := TongueState.new()
	tongue.start(-1)
	var copied: TongueState = tongue.copy()
	copied.reset()
	assert_eq(tongue.mode, TongueState.Mode.OUT)
	for tick: int in 23:
		assert_eq(tongue.advance(), -1)
		assert_ne(tongue.mode, TongueState.Mode.IDLE)
	assert_eq(tongue.advance(), -1)
	assert_eq(tongue.mode, TongueState.Mode.IDLE)

func test_short_sight_ray_checks_only_start_and_first_three_vertices() -> void:
	var grid: GridDefinition = _grid()
	grid.squares[1].vertices[0].y = -300
	var sight: TongueTarget = TongueTarget.line_of_sight(grid, Vector3i(128, 0, 128), Vector3i(384, 0, 128))
	assert_eq(sight.error, "")
	assert_eq(sight.entity_index, 1)
	grid.squares[0].vertices[3].y = -300
	assert_eq(TongueTarget.line_of_sight(grid, Vector3i(128, 0, 128), Vector3i(384, 0, 128)).entity_index, 1)
	grid.squares[0].vertices[2].y = -201
	assert_eq(TongueTarget.line_of_sight(grid, Vector3i(128, 0, 128), Vector3i(384, 0, 128)).entity_index, 0)

func test_long_sight_ray_checks_intermediate_cell_and_rejects_unsafe_storage() -> void:
	var grid: GridDefinition = _grid()
	assert_eq(TongueTarget.line_of_sight(grid, Vector3i(128, 0, 128), Vector3i(896, 0, 128)).entity_index, 1)
	grid.squares[1].vertices[0].y = -201
	assert_eq(TongueTarget.line_of_sight(grid, Vector3i(128, 0, 128), Vector3i(896, 0, 128)).entity_index, 0)
	assert_string_contains(TongueTarget.line_of_sight(grid, Vector3i(-128, 0, 128), Vector3i(896, 0, 128)).error, "outside authored storage")

func test_curve_quantizes_endpoints_and_uses_source_origin() -> void:
	var matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	assert_eq(TongueCurve.tip(matrix, 0, Vector3i(107, -3, 509), true), Vector3i(0, -32, 48))
	assert_eq(TongueCurve.tip(matrix, 8, Vector3i(107, -3, 509), true), Vector3i(104, -8, 504))
	assert_eq(TongueCurve.tip(matrix, 8, Vector3i.ZERO, false), Vector3i(8, -80, 48))

func test_butterfly_callback_uses_supplied_reward_and_authored_identity() -> void:
	var frog := Frog.new()
	frog.entity_collision = EntityCollisionDefinition.new()
	var definition := EntityDefinition.new()
	definition.entity_index = 42
	definition.butterfly_type = 0
	definition.butterfly_reward = RewardDefinition.new()
	definition.butterfly_reward.flags = RewardDefinition.SCORE
	definition.butterfly_reward.value = 375
	frog.entity_collision.entities.append(definition)
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	assert_string_contains(FormCallback.apply(FormCallback.Kind.BUTTERFLY_SCORE, frog, state, 0, events), "decoded pickup reward")
	assert_eq(state.flow.score, 0)
	assert_eq(FormCallback.apply(FormCallback.Kind.BUTTERFLY_SCORE, frog, state, 42, events), "")
	assert_eq(state.flow.score, 375)
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, TickEvent.Kind.REWARD)
	assert_eq(events[0].entity_index, 42)
	definition.butterfly_reward = null
	assert_string_contains(FormCallback.apply(FormCallback.Kind.BUTTERFLY_SCORE, frog, state, 42, events), "decoded pickup reward")
	assert_eq(state.flow.score, 375)

func _jumping() -> Array:
	var frog := Frog.new()
	frog.grid = _grid()
	var state := GameplayState.new()
	state.frog.mode = FrogMode.JUMPING
	state.frog.remaining_ticks = 4
	state.frog.no_input_timer = 9
	return [frog, state]

func test_mid_jump_tongue_slurps_and_still_buffers_same_tick_direction() -> void:
	var pair: Array = _jumping()
	var frog: Frog = pair[0]
	var state: GameplayState = pair[1]
	var events: Array[TickEvent] = []
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.TONGUE | TickCommand.WEST
	assert_eq(frog.control(state, command, events), "")
	assert_eq(state.tongue.mode, TongueState.Mode.OUT)
	assert_eq(state.tongue.target_index, -1)
	assert_eq(state.frog.no_input_timer, 0)
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, TickEvent.Kind.SOUND)
	assert_eq(events[0].sound_id, 20)
	assert_eq(state.requests.sound_requests, 1)
	assert_eq(state.frog.mode, FrogMode.JUMPING)
	assert_eq(state.frog.buffered_keys, 1)
	assert_eq(state.frog.buffered_direction, 3)
	command.pressed_mask = TickCommand.TONGUE
	assert_eq(frog.control(state, command, events), "")
	assert_eq(events.size(), 1, "An active effect is not restarted mid-jump")
	assert_eq(state.requests.sound_requests, 1)

func test_mid_jump_tongue_and_super_hop_buffer_together() -> void:
	var pair: Array = _jumping()
	var frog: Frog = pair[0]
	var state: GameplayState = pair[1]
	var events: Array[TickEvent] = []
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.TONGUE | TickCommand.SUPER_HOP
	assert_eq(frog.control(state, command, events), "")
	assert_eq(state.tongue.mode, TongueState.Mode.OUT)
	assert_eq(state.frog.buffered_keys, 1)
	assert_eq(state.frog.buffered_direction, 8)

func test_recorded_demo_byte_mid_jump_starts_nothing() -> void:
	var pair: Array = _jumping()
	var frog: Frog = pair[0]
	var state: GameplayState = pair[1]
	var events: Array[TickEvent] = []
	var command := TickCommand.new()
	command.recorded_input_byte = 16
	command.pressed_mask = TickCommand.TONGUE | TickCommand.NORTH
	assert_eq(frog.control(state, command, events), "")
	assert_eq(state.tongue.mode, TongueState.Mode.IDLE)
	assert_eq(state.frog.no_input_timer, 9)
	assert_true(events.is_empty())
	assert_eq(state.frog.buffered_keys, 0)
