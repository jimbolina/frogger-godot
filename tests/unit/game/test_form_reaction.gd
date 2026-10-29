extends GutTest
## FORM BOUNCY reaction precedence, the shared bounce and its whole-tick application.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
const BOUNCY: int = GridSquareFlags.USABLE | GridSquareFlags.BOUNCY

func _grid(rows: int = 4) -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(2, rows)
	grid.base = Vector2i(-256, -256)
	for index: int in 2 * rows:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = GridSquareFlags.USABLE | GridSquareFlags.SAFE
		var x: int = -256 + (index % 2) * 256
		@warning_ignore("integer_division")
		var z: int = -256 + (index / 2) * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		grid.squares.append(square)
	return grid

func _frog(grid: GridDefinition) -> Frog:
	var frog := Frog.new()
	frog.grid = grid
	frog.random = SourceRandom.create(1)
	return frog

func _state(grid: GridDefinition, position: Vector3i, direction: int) -> GameplayState:
	var state := GameplayState.new()
	state.frog.position_16 = position * 65536
	state.frog.direction = direction
	state.frog.mode = FrogMode.JUMPING
	state.frog.target_y = position.y
	state.frog.world_position = position
	state.frog.matrix12[9] = position.x
	state.frog.matrix12[10] = position.y
	state.frog.matrix12[11] = position.z
	state.frog.cell = GridQueries.world_to_cell(grid, position.x, position.z)
	state.frog.square_index = grid.stack_at(state.frog.cell).first_square_index
	return state

func _definition() -> FormContactDefinition:
	var definition := FormContactDefinition.new()
	definition.entity_index = 5
	definition.unique_id = 9
	return definition

func _contact(flags: int) -> FormContactResult:
	var contact := FormContactResult.new()
	contact.status = FormContactResult.CONTACT
	contact.entity_index = 5
	contact.unique_id = 9
	contact.cell_flags = flags
	return contact

func test_bouncy_cell_reports_a_supported_hit_after_source_precedence() -> void:
	var reaction: FormReactionResult = FormReaction.evaluate(_definition(), _contact(BOUNCY))
	assert_eq(reaction.status, FormReactionResult.BOUNCE)
	assert_true(reaction.hit)
	assert_eq(reaction.reason, "")
	assert_eq(reaction.kill_animation, -1)
	var expected: Dictionary[int, String] = {
		BOUNCY | GridSquareFlags.SAFE: FormReactionResult.SAFE,
		BOUNCY | GridSquareFlags.CHECKPOINT: FormReactionResult.CHECKPOINT,
		BOUNCY | GridSquareFlags.POPDEATH: FormReactionResult.POP,
		BOUNCY | GridSquareFlags.DEADLY: FormReactionResult.SQUISH,
		BOUNCY | GridSquareFlags.SLIPPY: FormReactionResult.HIT,
		GridSquareFlags.BOUNCY: FormReactionResult.NONE,
	}
	for flags: int in expected:
		assert_eq(FormReaction.evaluate(_definition(), _contact(flags), true).status, expected[flags], str(flags))
	assert_eq(reaction.copy().status, FormReactionResult.BOUNCE)

func test_bounce_is_a_forced_two_cell_fifteen_tick_jump_facing_forward() -> void:
	var grid: GridDefinition = _grid()
	var frog: Frog = _frog(grid)
	var state: GameplayState = _state(grid, Vector3i(-128, 0, -128), 0)
	var events: Array[TickEvent] = []
	assert_eq(frog.bounce(state, events), "")
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.cell, Vector2i(0, 2))
	assert_eq(state.frog.square_index, 4)
	assert_eq(state.frog.remaining_ticks, 15)
	assert_eq(state.frog.target_16.x, -128 * 65536)
	assert_eq(state.frog.target_16.z, 384 * 65536)
	assert_eq(state.frog.velocity_16.z, PlatformMath.divide(512 * 65536, 15))
	assert_eq(state.frog.velocity_16.y, -((Frog.GRAVITY_16 * 16) >> 1))
	assert_true(state.frog.flags & FrogFlags.JUMP_TO_LAND != 0)
	assert_true(TickEvent.trace_lines(events).has("hop"))

func test_bounce_uses_the_camera_relative_direction() -> void:
	var grid: GridDefinition = _grid()
	var frog: Frog = _frog(grid)
	frog.controller_directions = PackedInt32Array([1, 2, 3, 0])
	var state: GameplayState = _state(grid, Vector3i(-128, 0, -128), 0)
	var events: Array[TickEvent] = []
	assert_eq(frog.bounce(state, events), "")
	assert_eq(state.frog.direction, 0)
	assert_eq(state.frog.cell, Vector2i(0, 2))

func test_terrain_bouncy_reaction_uses_the_shared_bounce() -> void:
	var grid: GridDefinition = _grid()
	var frog: Frog = _frog(grid)
	var state: GameplayState = _state(grid, Vector3i(-128, 0, -128), 0)
	var events: Array[TickEvent] = []
	frog.react(state, BOUNCY, events)
	assert_eq(frog.callback_error, "")
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.cell, Vector2i(0, 2))
	assert_eq(state.frog.remaining_ticks, 15)

func test_form_bounce_forbids_the_entity_snaps_to_its_translation_then_bounces() -> void:
	var grid: GridDefinition = _grid()
	var frog: Frog = _frog(grid)
	var state: GameplayState = _state(grid, Vector3i(-200, -16, -20), 0)
	state.frog.position_16 += Vector3i(1234, 0, 4321)
	var matrix: PackedInt32Array = IDENTITY.duplicate()
	matrix[9] = -120
	matrix[10] = -999
	matrix[11] = 10
	var events: Array[TickEvent] = []
	assert_eq(frog.bounce_from_entity(state, 5, matrix, events), "")
	assert_eq(state.attachment.forbidden_entity_index, 5)
	assert_eq(state.frog.position_16, Vector3i(-120 * 65536, -16 * 65536, 10 * 65536))
	assert_eq(state.frog.world_position, Vector3i(-120, -16, 10))
	assert_eq(state.frog.direction, 0)
	assert_eq(state.frog.cell, Vector2i(0, 3), "the jump starts from the snapped cell (0, 1)")
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.velocity_16.x, PlatformMath.divide((-128 - -120) * 65536, 15))
	assert_eq(state.frog.velocity_16.z, PlatformMath.divide((640 - 10) * 65536, 15))

func test_form_reaction_application_records_the_hit_and_bounces() -> void:
	var grid: GridDefinition = _grid()
	var frog: Frog = _frog(grid)
	var state: GameplayState = _state(grid, Vector3i(-128, 0, -128), 0)
	var definition: FormContactDefinition = _definition()
	var reaction: FormReactionResult = FormReaction.evaluate(definition, _contact(BOUNCY))
	var pose := EntitySnapshot.new()
	pose.entity_index = 5
	pose.matrix12 = IDENTITY.duplicate()
	pose.matrix12[9] = -128
	pose.matrix12[11] = -128
	var result := TickResult.new()
	assert_eq(FrogContacts.new().apply_form_reaction(frog, state, definition, pose, reaction, result), "")
	assert_eq(state.attachment.entity_hit_indices, PackedInt32Array([5]))
	assert_eq(state.attachment.forbidden_entity_index, 5)
	assert_eq(state.attachment.death_entity_index, -1)
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.cell, Vector2i(0, 2))

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = _grid()
	level.spawn_cell = Vector2i.ZERO
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i(3, 3)
	collision.group_size = Vector2i(256, 256)
	collision.frog_collision = FrogCollisionDefinition.new()
	collision.frog_collision.part_count = 1
	collision.frog_collision.probes.append(FrogCollisionDefinition.Probe.new())
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(1)
		var action := FrogCollisionDefinition.Action.new()
		action.frames.append(IDENTITY.duplicate())
		action.actual_cels.append(0)
		collision.frog_collision.actions.append(action)
	var entity := EntityDefinition.new()
	entity.entity_name = "STATIC"
	entity.behavior = EntityBehaviorCatalog.resolve(entity.entity_name)
	entity.entity_index = 2
	entity.unique_id = 9
	entity.form_grid_id = 2
	entity.form_id = 3
	entity.form_name = "TEST_MUSHROOM"
	entity.matrix12[9] = -120
	entity.matrix12[11] = -110
	collision.entities.append(entity)
	var contact := FormContactDefinition.new()
	contact.entity_index = entity.entity_index
	contact.unique_id = entity.unique_id
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.form_name = entity.form_name
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-128, -128)
	contact.height = -10
	contact.max_y = 10
	contact.radius_squared = 1000000
	contact.grid_flags = PackedInt32Array([BOUNCY])
	collision.contacts.append(contact)
	level.entity_collision = collision
	return level

func test_form_bounce_runs_inside_the_collision_transaction() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.entity_contacts.size(), 1)
	assert_eq(result.entity_contacts[0].status, FormReactionResult.BOUNCE)
	var snapshot: GameplayState = result.collision_snapshot
	assert_eq(snapshot.attachment.entity_hit_indices, PackedInt32Array([2]))
	assert_eq(snapshot.attachment.forbidden_entity_index, 2)
	assert_eq(snapshot.frog.mode, FrogMode.BOUNCE)
	assert_eq(snapshot.frog.position_16.x, -120 * 65536)
	assert_eq(snapshot.frog.position_16.z, -110 * 65536)
	assert_eq(snapshot.frog.cell, Vector2i(0, 2))
	assert_eq(snapshot.frog.remaining_ticks, 15)
	var next := TickCommand.new()
	next.tick_index = 1
	var following: TickResult = run.step(next)
	assert_eq(following.error, "")
	assert_eq(following.entity_contacts.size(), 0, "the forbidden mushroom is not contacted again")
