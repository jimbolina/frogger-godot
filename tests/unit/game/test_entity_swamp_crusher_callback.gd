extends GutTest
## Hand-derived frozen Swamp SwpCrusherCallback debounce, velocity-directed bounce, user-mode count and deadly FORM squish.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 10, -20, 30]
const INDEX: int = 6

func _grid(usable: bool = true) -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(3, 3)
	grid.base = Vector2i(-384, -384)
	for index: int in 9:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = (GridSquareFlags.USABLE | GridSquareFlags.SAFE) if usable else 0
		var x: int = -384 + (index % 3) * 256
		@warning_ignore("integer_division")
		var z: int = -384 + (index / 3) * 256
		square.vertices.assign([Vector3i(x, -64, z + 256), Vector3i(x + 256, -64, z + 256), Vector3i(x, -64, z), Vector3i(x + 256, -64, z)])
		grid.squares.append(square)
	return grid

func _contact(flags: PackedInt32Array = PackedInt32Array([GridSquareFlags.USABLE, GridSquareFlags.USABLE | GridSquareFlags.DEADLY])) -> FormContactDefinition:
	var contact := FormContactDefinition.new()
	contact.entity_index = INDEX
	contact.dimensions = Vector2i(2, 1)
	contact.offsets = Vector2i(-256, -128)
	contact.height = -10
	contact.max_y = 10
	contact.grid_flags = flags
	return contact

func _frog(grid: GridDefinition, contact: FormContactDefinition) -> Frog:
	var frog := Frog.new()
	frog.grid = grid
	frog.theme = FormCallback.SWAMP_THEME
	frog.entity_collision = EntityCollisionDefinition.new()
	if contact != null:
		frog.entity_collision.contacts.append(contact)
	return frog

func _definition() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = INDEX
	return definition

func _crusher(matrix: PackedInt32Array = IDENTITY, count: int = 0) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = INDEX
	entity.matrix12 = matrix.duplicate()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.count = count
	return entity

func _state(mode: int, velocity: Vector3i = Vector3i.ZERO, delta: Vector3i = Vector3i.ZERO) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = mode
	state.frog.direction = 0
	state.frog.cell = Vector2i(1, 1)
	state.frog.square_index = 4
	state.frog.position_16 = Vector3i(10, -20, 30) * 65536
	state.frog.matrix12[9] = 10 + delta.x
	state.frog.matrix12[10] = -20 + delta.y
	state.frog.matrix12[11] = 30 + delta.z
	state.frog.velocity_16 = velocity
	state.frog.target_y = -50
	return state

func _apply(frog: Frog, entity: EntitySnapshot, state: GameplayState) -> String:
	var events: Array[TickEvent] = []
	return EntitySwampCrusherCallback.apply(_definition(), entity, frog, state, events)

func _killed(state: GameplayState) -> bool:
	return bool(state.frog.flags & FrogFlags.MUST_DIE) and state.frog.death_equate == FrogAnimationCatalog.SQUISHED

func test_non_zero_count_ignores_the_hit() -> void:
	var entity: EntitySnapshot = _crusher(IDENTITY, 3)
	var state: GameplayState = _state(FrogMode.JUMPING, Vector3i(65536, 0, 0))
	var before: String = JSON.stringify(TerrainTrace.facts(state, true))
	assert_eq(_apply(_frog(_grid(), _contact()), entity, state), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(state, true)), before)
	assert_eq(entity.custom_state.count, 3)
	assert_false(_killed(state))

func test_still_frog_falls_through_to_the_facing_reversal_from_its_stored_cell() -> void:
	var entity: EntitySnapshot = _crusher()
	var state: GameplayState = _state(FrogMode.JUMPING)
	var twin: GameplayState = _state(FrogMode.JUMPING)
	assert_eq(FormCallback.crusher_bounce_back(_grid(), twin, INDEX), "")
	assert_eq(_apply(_frog(_grid(), _contact(PackedInt32Array([0, 0]))), entity, state), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(state, true)), JSON.stringify(TerrainTrace.facts(twin, true)))
	assert_eq(state.frog.cell, Vector2i(1, 0))
	assert_eq(state.frog.direction, 2)
	assert_eq(state.attachment.forbidden_entity_index, INDEX)
	assert_eq(entity.custom_state.count, 5)

func test_moving_frog_bounces_against_its_dominant_velocity_axis_from_its_world_cell() -> void:
	var cases: Array = [
		[Vector3i(5 * 65536, 0, 65536), Vector2i(0, 1), 3],
		[Vector3i(-65536, 0, 0), Vector2i(2, 1), 1],
		[Vector3i(7, 0, -3), Vector2i(0, 1), 3],
		[Vector3i(65536, 0, 65536), Vector2i(1, 0), 2],
		[Vector3i(0, 0, 1), Vector2i(1, 0), 2],
		[Vector3i(-2, 0, -3), Vector2i(1, 2), 0],
	]
	for item: Array in cases:
		var velocity: Vector3i = item[0]
		var cell: Vector2i = item[1]
		var direction: int = item[2]
		var entity: EntitySnapshot = _crusher()
		var state: GameplayState = _state(FrogMode.JUMPING, velocity)
		state.frog.cell = Vector2i(2, 2)
		state.frog.direction = 1
		assert_eq(_apply(_frog(_grid(), _contact(PackedInt32Array([0, 0]))), entity, state), "")
		assert_eq(state.frog.cell, cell, str(velocity))
		assert_eq(state.frog.direction, direction, str(velocity))
		assert_eq(state.frog.mode, FrogMode.JUMPING)
		assert_eq(state.attachment.forbidden_entity_index, INDEX)
		assert_eq(entity.custom_state.count, 5)

func test_moving_frog_bounce_matches_the_shared_square_rule() -> void:
	var entity: EntitySnapshot = _crusher()
	var state: GameplayState = _state(FrogMode.JUMPING, Vector3i(0, 0, -65536))
	var twin: GameplayState = _state(FrogMode.JUMPING, Vector3i(0, 0, -65536))
	assert_eq(FormCallback.crusher_bounce_to(_grid(), twin, INDEX, Vector2i(1, 2), Vector3i(0, 1, 0)), "")
	assert_eq(_apply(_frog(_grid(), _contact(PackedInt32Array([0, 0]))), entity, state), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(state, true)), JSON.stringify(TerrainTrace.facts(twin, true)))

func test_user_mode_retarget_leaves_count_four_and_a_blocked_target_leaves_five() -> void:
	var entity: EntitySnapshot = _crusher()
	var state: GameplayState = _state(FrogMode.BOUNCE, Vector3i(65536, 0, 0))
	assert_eq(_apply(_frog(_grid(), _contact(PackedInt32Array([0, 0]))), entity, state), "")
	assert_eq(entity.custom_state.count, 4)
	assert_eq(state.frog.cell, Vector2i(0, 1))
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.remaining_ticks, 6)
	entity = _crusher()
	state = _state(FrogMode.BOUNCE, Vector3i(65536, 0, 0))
	assert_eq(_apply(_frog(_grid(false), _contact(PackedInt32Array([0, 0]))), entity, state), "")
	assert_eq(entity.custom_state.count, 5)
	assert_eq(state.frog.cell, Vector2i(1, 1))

func test_deadly_square_kills_strictly_inside_xz_and_inclusively_inside_y() -> void:
	var cases: Array = [
		[Vector3i(100, 0, 0), true],
		[Vector3i(-100, 0, 0), false],
		[Vector3i(255, 0, 0), true],
		[Vector3i(256, 0, 0), false],
		[Vector3i(100, 0, 127), true],
		[Vector3i(100, 0, -127), true],
		[Vector3i(100, 0, 128), false],
		[Vector3i(100, 0, -128), false],
		[Vector3i(100, -10, 0), true],
		[Vector3i(100, -11, 0), false],
		[Vector3i(100, 10, 0), true],
		[Vector3i(100, 11, 0), false],
		[Vector3i(65536 + 100, 0, 0), true],
	]
	for item: Array in cases:
		var delta: Vector3i = item[0]
		var expected: bool = item[1]
		var entity: EntitySnapshot = _crusher()
		var state: GameplayState = _state(FrogMode.JUMPING, Vector3i.ZERO, delta)
		assert_eq(_apply(_frog(_grid(false), _contact()), entity, state), "")
		assert_eq(_killed(state), expected, str(delta))

func test_deadly_lookup_uses_the_crusher_local_frame() -> void:
	var rotated: PackedInt32Array = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 10, -20, 30]
	var state: GameplayState = _state(FrogMode.JUMPING, Vector3i.ZERO, Vector3i(0, 0, -100))
	assert_eq(_apply(_frog(_grid(false), _contact()), _crusher(rotated), state), "")
	assert_true(_killed(state))
	state = _state(FrogMode.JUMPING, Vector3i.ZERO, Vector3i(0, 0, 100))
	assert_eq(_apply(_frog(_grid(false), _contact()), _crusher(rotated), state), "")
	assert_false(_killed(state))

func test_squish_follows_a_user_mode_bounce_and_needs_form_data() -> void:
	var entity: EntitySnapshot = _crusher()
	var state: GameplayState = _state(FrogMode.BOUNCE, Vector3i(5 * 65536, 0, 0), Vector3i(100, 0, 0))
	assert_eq(_apply(_frog(_grid(), _contact()), entity, state), "")
	assert_eq(entity.custom_state.count, 4)
	assert_eq(state.frog.cell, Vector2i(0, 1))
	assert_true(_killed(state))
	var contact: FormContactDefinition = _contact()
	contact.has_form_data = false
	state = _state(FrogMode.JUMPING, Vector3i.ZERO, Vector3i(100, 0, 0))
	assert_eq(_apply(_frog(_grid(false), contact), _crusher(), state), "")
	assert_false(_killed(state))

func test_missing_collision_form_or_grid_is_an_error_before_any_change() -> void:
	var entity: EntitySnapshot = _crusher()
	var frog: Frog = _frog(_grid(), _contact())
	frog.entity_collision = null
	assert_ne(_apply(frog, entity, _state(FrogMode.JUMPING)), "")
	var other: FormContactDefinition = _contact()
	other.entity_index = 99
	var no_form: GameplayState = _state(FrogMode.JUMPING)
	assert_eq(_apply(_frog(_grid(), other), entity, no_form), "", "A missing FORM still bounces, as the source bounce needs no form data")
	assert_eq(entity.custom_state.count, 5)
	assert_false(_killed(no_form))
	entity = _crusher()
	var state: GameplayState = _state(FrogMode.JUMPING, Vector3i(65536, 0, 0))
	assert_ne(_apply(_frog(null, _contact()), entity, state), "")
	assert_eq(entity.custom_state.count, 0)
	assert_eq(state.frog.cell, Vector2i(1, 1))
