extends GutTest
## Independent frozen Forest transitions and source-width boundary facts.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/forest.json"))

func _result() -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = EntitySnapshot.new()
	result.entity.matrix12 = IDENTITY.duplicate()
	result.entity.custom_state = EntityCustomState.new()
	result.entity.animation = EntityAnimationState.create(PackedInt32Array([4, 4]))
	result.entity.path = PathSnapshot.new()
	result.environment = EntityEnvironmentState.new()
	result.environment.checkpoint_positions.resize(5)
	result.random = SourceRandom.create(1)
	return result

func _definition(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve(name)
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.action_lengths = PackedInt32Array([4, 4])
	definition.forest = EntityForestDefinition.new()
	return definition

func _assert_row(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key: String in actual:
		if actual[key] is bool:
			var got: bool = actual[key]
			var want: bool = expected[key]
			assert_eq(got, want, label + " " + key)
		else:
			var got: int = actual[key]
			var want: int = expected[key]
			assert_eq(got, want, label + " " + key)

func test_squirrel_bounce_and_animation_end_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().squirrels:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		result.entity.custom_state.mode = initial.mode
		result.entity.animation.action = initial.mode
		result.entity.animation.cel = initial.cel
		result.entity.path.flags = PathStart.JUST_BOUNCED_END if initial.bounce else 0
		var definition: EntityDefinition = _definition("FOR_SQUIRREL")
		definition.authored_delay = 65535
		assert_eq(EntitySquirrel.update(definition, result), "")
		_assert_row({"mode": result.entity.custom_state.mode, "action": result.entity.animation.action, "active": result.path_active_request}, expected, str(initial))

func test_visibility_steps_and_boundaries_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().visibility:
		var initial: Dictionary = fixture.input
		var matrix: PackedInt32Array = IDENTITY.duplicate()
		matrix[9] = initial.start
		var frog := GameplayState.new()
		frog.frog.flags = FrogFlags.ACTIVE if initial.frog_active else 0
		frog.frog.matrix12[9] = initial.frog_x
		var entity := EntitySnapshot.new()
		entity.matrix12[9] = initial.entity_x
		entity.entity_flags = 8 if initial.disabled else 0
		entity.live = initial.live
		entity.flags_authoritative = true
		var definition: EntityDefinition = _definition("STATIC")
		definition.form_id = initial.form
		var contact := FormContactDefinition.new()
		contact.radius_squared = initial.radius2
		contact.dimensions = Vector2i(1, 1)
		var offset: int = initial.offset
		contact.offsets = Vector2i(offset, 0)
		contact.has_form_data = initial.has_form
		var collision := EntityCollisionDefinition.new()
		collision.group_dimensions = Vector2i(2, 1)
		collision.group_size = Vector2i(1024, 1024)
		var neighbors: Array[EntitySnapshot] = [entity]
		var definitions: Array[EntityDefinition] = [definition]
		var contacts: Array[FormContactDefinition] = [contact]
		var direction: int = initial.direction
		var expected: int = fixture.expected
		var actual: int = ForestVisibilityQuery.first_hit(matrix, Vector3i(direction, 0, 0), frog, neighbors, definitions, contacts, collision)
		assert_eq(actual, expected, str(initial))

func test_hedgehog_clocks_and_repeat_precedence_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().hedgehogs:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		result.entity.custom_state.mode = initial.mode
		result.entity.custom_state.timer = initial.timer
		result.entity.animation.action = initial.action
		result.entity.animation.cel = initial.cel
		result.entity.path.flags = PathStart.JUST_REPEATED_END if initial.repeat else 0
		var definition: EntityDefinition = _definition("FOR_HEDGEHOG")
		definition.forest.run_time = 2
		definition.forest.roll_time = 3
		definition.forest.run_speed = 256
		definition.forest.roll_speed = 768
		assert_eq(EntityHedgehog.update(definition, result), "")
		_assert_row({"mode": result.entity.custom_state.mode, "timer": result.entity.custom_state.timer, "action": result.entity.animation.action, "speed": result.path_speed_request}, expected, str(initial))

func _grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(1, 1)
	var stack := GridStackDefinition.new()
	stack.square_count = 2
	grid.stacks.append(stack)
	for height: int in [0, -100]:
		var square := GridSquareDefinition.new()
		square.vertices.assign([Vector3i(0, height, 0), Vector3i(256, height, 0), Vector3i(0, height, 256), Vector3i(256, height, 256)])
		grid.squares.append(square)
	return grid

func test_branch_countdown_first_layer_and_fall_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().branches:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		result.entity.entity_index = 0
		result.entity.custom_state.mode = initial.mode
		result.entity.custom_state.timer = initial.timer
		result.entity.custom_state.target.y = initial.floor
		result.entity.custom_state.velocity_16.y = initial.speed
		result.entity.matrix12[10] = initial.y
		result.entity.entity_flags = EntityDefinition.NO_COLLISION if initial.disabled else 0
		result.entity.pop_allocated = initial.effect
		var frog := GameplayState.new()
		frog.attachment.current_entity_index = 0 if initial.attached else -1
		var hit: bool = initial.hit
		assert_eq(EntityBreakingBranch.update(_definition("FOR_BREAKING_BRANCH"), result, frog, hit, _grid()), "")
		var sounds: int = 0
		var pop: bool = false
		for event: TickEvent in result.entity.requests:
			if event.kind == TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST:
				pop = true
			else:
				assert_eq(event.sound_id, 66)
				sounds += 1
		_assert_row({"mode": result.entity.custom_state.mode, "timer": result.entity.custom_state.timer, "y": result.entity.matrix12[10], "speed": result.entity.custom_state.velocity_16.y, "sounds": sounds, "disabled": bool(result.entity.entity_flags & EntityDefinition.NO_COLLISION), "detach": result.frog_fall_requested, "pop": pop}, expected, str(initial))

func test_hive_release_chase_mill_return_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().hives:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		result.entity.custom_state.mode = initial.mode
		var swarm := EntitySwarmState.new()
		swarm.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, initial.x, 0, 0])
		swarm.speed = initial.speed
		swarm.delay = initial.delay
		swarm.visible = initial.visible
		result.entity.custom_state.swarm = swarm
		result.environment.active_swarms = initial.active
		var definition: EntityDefinition = _definition("FOR_HIVE")
		definition.forest.release_distance = initial.release
		definition.forest.swarm_speed = initial.maximum
		var frog := GameplayState.new()
		frog.frog.matrix12[9] = initial.frog_x
		frog.frog.flags = FrogFlags.ACTIVE | (FrogFlags.CONTROL_ACTIVE if initial.eligible else 0)
		frog.frog.mode = FrogMode.DYING if initial.stopped else FrogMode.STATIONARY
		var collision: EntityCollisionDefinition = null
		var neighbors: Array[EntitySnapshot] = []
		var definitions: Array[EntityDefinition] = []
		var contacts: Array[FormContactDefinition] = []
		if initial.first_hit != 0:
			collision = EntityCollisionDefinition.new()
			collision.group_dimensions = Vector2i(4, 1)
			collision.group_size = Vector2i(1024, 1024)
		if initial.first_hit == 2:
			neighbors.append(EntitySnapshot.new())
			var stump: EntityDefinition = _definition("STATIC")
			stump.form_id = 9
			definitions.append(stump)
			var contact := FormContactDefinition.new()
			contact.dimensions = Vector2i(1, 1)
			contact.radius_squared = 1000000
			contacts.append(contact)
		var grid: GridDefinition = _grid()
		grid.stacks[0].square_count = 1
		assert_eq(EntityHive.update(definition, result, frog, neighbors, definitions, contacts, grid, collision, 0), "")
		_assert_row({"mode": result.entity.custom_state.mode, "speed": swarm.speed, "delay": swarm.delay, "x": swarm.matrix12[9], "visible": swarm.visible, "active": result.environment.active_swarms, "death": result.death_animation >= 0}, expected, str(initial))

func test_land_projection_triangles_and_tangent_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().projection:
		var initial: Dictionary = fixture.input
		var heights: Array = initial.heights
		var grid: GridDefinition = _grid()
		for index: int in 4:
			grid.squares[0].vertices[index].y = heights[index]
		var position: Array = initial.position
		var tangent: Array = initial.tangent
		var path := PathSnapshot.new()
		path.position = Vector3i.ZERO
		path.tangent = Vector3i.ZERO
		for axis: int in 3:
			path.position[axis] = position[axis]
			path.tangent[axis] = tangent[axis]
		var flags: int = EntityDefinition.PROJECT_ON_LAND
		if initial.world_align:
			flags |= EntityDefinition.ALIGN_TO_WORLD
		var expected_values: Array = fixture.expected
		var expected: PackedInt32Array = PackedInt32Array(expected_values)
		assert_eq(EntityTransform.moving_on_land(path, flags, grid), expected, str(initial))
