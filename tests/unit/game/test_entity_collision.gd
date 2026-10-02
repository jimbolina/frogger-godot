extends GutTest
## Bounded FORM reaction, C map-group order, and terrain/entity transaction checks.

func _static(index: int, x: int = 0, z: int = 0, flags: int = 0) -> EntityDefinition:
	var entity := EntityDefinition.new()
	entity.entity_name = "STATIC"
	entity.entity_index = index
	entity.unique_id = 7
	entity.form_grid_id = 2
	entity.form_id = 3
	entity.form_name = "TEST"
	entity.flags = flags
	entity.matrix12[9] = x
	entity.matrix12[11] = z
	return entity

func _contact(entity: EntityDefinition, flags: int = 4097) -> FormContactDefinition:
	var contact := FormContactDefinition.new()
	contact.entity_index = entity.entity_index
	contact.unique_id = entity.unique_id
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.form_name = entity.form_name
	contact.entity_flags = entity.flags
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-128, -128)
	contact.height = -10
	contact.max_y = 10
	contact.radius_squared = 1000000
	contact.grid_flags = PackedInt32Array([flags])
	return contact

func _collision(entities: Array[EntityDefinition]) -> EntityCollisionDefinition:
	var result := EntityCollisionDefinition.new()
	result.entities = entities
	for entity: EntityDefinition in entities:
		result.contacts.append(_contact(entity))
	result.group_dimensions = Vector2i(3, 3)
	result.group_size = Vector2i(256, 256)
	return result

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(2, 2)
	level.grid.base = Vector2i(-256, -256)
	level.spawn_cell = Vector2i.ZERO
	level.collision_enabled = true
	for i: int in 4:
		var stack := GridStackDefinition.new()
		stack.first_square_index = i
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 3
		var x: int = -256 + (i % 2) * 256
		@warning_ignore("integer_division")
		var z: int = -256 + (i / 2) * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		level.grid.squares.append(square)
	return level

func test_reaction_precedence_and_detached_results() -> void:
	var entity: EntityDefinition = _static(8)
	var definition: FormContactDefinition = _contact(entity)
	var pose := EntitySnapshot.new()
	pose.entity_index = 8
	pose.unique_id = 7
	var geometric: FormContactResult = FormContactQuery.query(definition, pose, Vector3i.ZERO)
	for flags: int in [0, 4, 5, 4097, 4101, 4099, 4161, 3, 65, 17, 33, 1]:
		geometric.cell_flags = flags
		var reaction: FormReactionResult = FormReaction.evaluate(definition, geometric)
		if flags in [4097, 4101]:
			assert_eq(reaction.status, FormReactionResult.POP)
		elif flags in [3, 65, 5, 33, 4099, 4161]:
			assert_eq(reaction.status, FormReactionResult.UNSUPPORTED)
		elif flags in [17, 1]:
			assert_eq(reaction.status, FormReactionResult.HIT)
		else:
			assert_eq(reaction.status, FormReactionResult.NONE)
	definition.death_type = 5
	geometric.cell_flags = 5
	assert_eq(FormReaction.evaluate(definition, geometric).status, FormReactionResult.POP)
	definition.reaction_unsupported_reason = "script callback"
	assert_eq(FormReaction.evaluate(definition, geometric).status, FormReactionResult.UNSUPPORTED)
	geometric.status = FormContactResult.MISS
	assert_eq(FormReaction.evaluate(definition, geometric).status, FormReactionResult.NONE)
	var copied: FormContactDefinition = definition.copy()
	assert_eq(copied.death_type, 5)
	assert_eq(copied.reaction_unsupported_reason, "script callback")
	var reaction_copy: FormReactionResult = FormReaction.evaluate(definition, geometric).copy()
	reaction_copy.contact.cell_flags = 999
	assert_eq(geometric.cell_flags, 5)

func test_group_order_negative_division_clamping_and_flags() -> void:
	var moving_a: EntityDefinition = _static(2, 0, 0)
	moving_a.entity_name = "MOVING"
	var moving_b: EntityDefinition = _static(4, 0, 0)
	moving_b.entity_name = "MOVING"
	var static_a: EntityDefinition = _static(5, 0, 0)
	var hidden_static: EntityDefinition = _static(9, 0, 0, EntityDefinition.HIDDEN)
	var static_next_group: EntityDefinition = _static(11, 256, 0)
	var moving_hidden: EntityDefinition = _static(12, 0, 0, EntityDefinition.HIDDEN)
	moving_hidden.entity_name = "MOVING"
	var static_far: EntityDefinition = _static(15, 9999, 9999, EntityDefinition.NO_DISPLAY)
	var definition: EntityCollisionDefinition = _collision([moving_a, moving_b, static_a, hidden_static, static_next_group, moving_hidden, static_far])
	assert_eq(definition.validate(), "")
	var snapshot := EntityRunSnapshot.new()
	for entity: EntityDefinition in definition.entities:
		var pose := EntitySnapshot.new()
		pose.entity_index = entity.entity_index
		pose.unique_id = entity.unique_id
		pose.matrix12 = entity.matrix12.duplicate()
		snapshot.entities.append(pose)
	assert_eq(EntityContactOrder.indices(definition, snapshot, Vector3i(-1, 0, -1)), PackedInt32Array([4, 2, 9, 5, 11]))
	assert_eq(EntityContactOrder.indices(definition, snapshot, Vector3i(768, 0, 768)), PackedInt32Array([15]))
	assert_eq(EntityContactOrder.indices(definition, snapshot, Vector3i(-256, 0, -256)), PackedInt32Array([4, 2, 9, 5]))
	definition.group_base.x = -32768
	definition.entities[0].matrix12[9] = 2147483647
	snapshot.entities[0].matrix12[9] = 2147483647
	assert_eq(EntityContactOrder.indices(definition, snapshot, Vector3i(2147483647, 0, 0)).size(), 0)
	definition.group_base.x = 0
	definition.entities[0].matrix12[9] = 0
	snapshot.entities[0].matrix12[9] = 0
	var detached: EntityCollisionDefinition = definition.copy()
	detached.entities[0].matrix12[9] = 900
	detached.contacts[0].grid_flags[0] = 0
	assert_eq(definition.entities[0].matrix12[9], 0)
	assert_eq(definition.contacts[0].grid_flags[0], 4097)
	definition.contacts[1].entity_index = 99
	assert_false(definition.validate().is_empty())

func test_pop_continues_scanning_and_resets_transient_hits() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(2, -128, -128), _static(7, -128, -128)])
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var command := TickCommand.new()
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.entity_hit_indices, PackedInt32Array([7, 2]))
	assert_eq(result.final_snapshot.death_entity_index, 7)
	assert_eq(result.final_snapshot.death_equate, 23)
	assert_eq(result.final_snapshot.velocity_16, Vector3i.ZERO)
	assert_true(result.final_snapshot.life_decrement_requested)
	assert_eq(result.events.count("entity_pop_explosion_request"), 1)
	assert_eq(result.final_snapshot.entities.tick_index, result.final_snapshot.tick_index)
	var detached: RunSnapshot = run.snapshot()
	detached.entities.entities[0].matrix12[9] = 123
	detached.entity_hit_indices.append(99)
	assert_eq(run.snapshot().entities.entities[0].matrix12[9], -128)
	assert_eq(run.snapshot().entity_hit_indices.size(), 2)
	command.tick_index = 1
	result = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.entity_hit_indices.size(), 0)
	assert_eq(result.final_snapshot.death_count, 69)
	assert_eq(result.events.count("entity_pop_explosion_request"), 0)
	assert_eq(result.final_snapshot.death_entity_index, 7)

func test_moving_post_step_pose_and_late_failure_retry() -> void:
	var path := PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 20
	segment.start = Vector3i(-138, 0, -128)
	segment.end = Vector3i(-118, 0, -128)
	path.segments.append(segment)
	var moving: EntityDefinition = _static(4)
	moving.entity_name = "MOVING"
	moving.flags = EntityDefinition.ALIGN_TO_WORLD
	moving.path_definition = path
	moving.path_start = PathStart.new()
	moving.path_start.speed = 10
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([moving])
	level.entity_collision.contacts[0].entity_flags = moving.flags
	level.entity_collision.contacts[0].radius_squared = 25
	var lengths := PackedInt32Array()
	for _index: int in FrogAnimationCatalog.ACTION_NAMES.size():
		lengths.append(1)
	level.frog_action_lengths = lengths
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities.entities[0].matrix12[9], -138)
	# The forced animation error happens after path motion and POP are queued.
	run._animation.error = "forced late failure"
	var command := TickCommand.new()
	var failed: TickResult = run.step(command)
	assert_eq(failed.error, "forced late failure")
	assert_null(failed.control_snapshot)
	assert_null(failed.move_snapshot)
	assert_null(failed.collision_snapshot)
	assert_null(failed.camera_snapshot)
	assert_null(failed.final_snapshot)
	assert_eq(failed.entity_contacts.size(), 0)
	assert_eq(failed.events.size(), 0)
	assert_eq(failed.rng_consumers.size(), 0)
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().entities.entities[0].matrix12[9], -138)
	run._animation.error = ""
	var succeeded: TickResult = run.step(command)
	assert_eq(succeeded.error, "")
	assert_eq(succeeded.final_snapshot.entities.entities[0].matrix12[9], -128)
	assert_eq(succeeded.final_snapshot.death_entity_index, 4)
	assert_eq(succeeded.entity_contacts.size(), 1)

func test_terrain_early_exit_prevents_entity_contact() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(3, -128, -128)])
	level.collision_bounds = Rect2i(0, 0, 100, 100)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(result.entity_contacts.size(), 0)
	assert_eq(result.final_snapshot.death_entity_index, -1)
	assert_eq(result.final_snapshot.entity_hit_indices.size(), 0)
	assert_eq(result.final_snapshot.death_equate, 2)

func test_late_camera_rejection_rolls_back_pop_and_entity_motion() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(3, -128, -128)])
	level.camera = GameplayCameraDefinition.new()
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	run._state.remaining_ticks = -1
	var failed: TickResult = run.step(TickCommand.new())
	assert_string_contains(failed.error, "Camera timers")
	assert_null(failed.control_snapshot)
	assert_null(failed.move_snapshot)
	assert_null(failed.collision_snapshot)
	assert_null(failed.camera_snapshot)
	assert_null(failed.final_snapshot)
	assert_eq(failed.entity_contacts.size(), 0)
	assert_eq(failed.events.size(), 0)
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().death_entity_index, -1)
	run._state.remaining_ticks = 0
	var succeeded: TickResult = run.step(TickCommand.new())
	assert_eq(succeeded.error, "")
	assert_eq(succeeded.final_snapshot.death_entity_index, 3)

func test_source_collision_early_returns_and_wait_twist() -> void:
	for case_name: String in ["freefall", "deathheight", "pending", "wait", "twist"]:
		var level: LevelDefinition = _level()
		level.entity_collision = _collision([_static(3, -128, -128)])
		if case_name == "deathheight":
			level.theme_death_height = -1
		if case_name in ["wait", "twist"]:
			level.camera = GameplayCameraDefinition.new()
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		if case_name == "freefall":
			run._state.flags |= 128
			run._state.world_position.y = 1
			run._state.position_16.y = 65536
		elif case_name == "pending":
			run._state.flags |= 8
		elif case_name in ["wait", "twist"]:
			run._state.mode = 3
			run._camera._state.move_timer = 4
			run._camera._state.twist_counter = 1 if case_name == "twist" else 0
		var result: TickResult = run.step(TickCommand.new())
		assert_eq(result.error, "", case_name)
		if case_name == "twist":
			assert_eq(result.final_snapshot.entity_hit_indices, PackedInt32Array([3]))
		else:
			assert_eq(result.entity_contacts.size(), 0, case_name)
			assert_eq(result.final_snapshot.entity_hit_indices.size(), 0, case_name)

func test_disabled_contact_and_invalid_contact_rollback() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(3, -128, -128, EntityDefinition.NO_COLLISION)])
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(result.entity_contacts[0].contact.status, FormContactResult.DISABLED)
	assert_eq(result.final_snapshot.entity_hit_indices.size(), 0)
	level = _level()
	level.entity_collision = _collision([_static(3, -128, -128)])
	run = TerrainRun.create(level)
	run._entity_collision.contacts[0].dimensions = Vector2i.ZERO
	var before: RunSnapshot = run.snapshot()
	result = run.step(TickCommand.new())
	assert_string_contains(result.error, "dimensions")
	assert_null(result.control_snapshot)
	assert_null(result.move_snapshot)
	assert_null(result.collision_snapshot)
	assert_eq(result.entity_contacts.size(), 0)
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().rng_state, before.rng_state)
	assert_eq(run.snapshot().entities.tick_index, before.entities.tick_index)
	run._entity_collision.contacts[0].dimensions = Vector2i.ONE
	assert_eq(run.step(TickCommand.new()).error, "")

func test_reset_preserves_aggregate_then_death_completes() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(3, -128, -128)])
	level.camera = GameplayCameraDefinition.new()
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	assert_eq(run.step(TickCommand.new()).error, "")
	var before: RunSnapshot = run.snapshot()
	var invalid := RunStart.new()
	invalid.spawn_cell = Vector2i(99, 99)
	assert_false(run.reset(invalid).is_empty())
	var after: RunSnapshot = run.snapshot()
	assert_eq(after.tick_index, before.tick_index)
	assert_eq(after.entities.tick_index, before.entities.tick_index)
	assert_eq(after.death_entity_index, before.death_entity_index)
	assert_eq(after.rng_state, before.rng_state)
	assert_eq(after.camera.mode, before.camera.mode)
	assert_eq(after.camera.source_world, before.camera.source_world)
	assert_eq(after.camera.move_timer, before.camera.move_timer)
	for tick: int in range(1, 71):
		var command := TickCommand.new()
		command.tick_index = tick
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		assert_eq(result.final_snapshot.entities.tick_index, result.final_snapshot.tick_index)
	assert_eq(run.snapshot().death_count, 0)
	assert_true(run.snapshot().completed)
	assert_eq(run.snapshot().death_entity_index, 3)
	var beyond := TickCommand.new()
	beyond.tick_index = 71
	assert_string_contains(run.step(beyond).error, "completed")

func test_moving_path_enters_scanned_group_before_contact() -> void:
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 130
	segment.start = Vector3i(-193, 0, -128)
	segment.end = Vector3i(-63, 0, -128)
	var path := PathDefinition.new()
	path.segments.append(segment)
	var mover: EntityDefinition = _static(6)
	mover.entity_name = "MOVING"
	mover.flags = EntityDefinition.ALIGN_TO_WORLD
	mover.path_definition = path
	mover.path_start = PathStart.new()
	mover.path_start.speed = 65
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([mover])
	level.entity_collision.group_base = Vector3i(-256, 0, -256)
	level.entity_collision.group_dimensions = Vector2i(4, 4)
	level.entity_collision.group_size = Vector2i(64, 64)
	level.entity_collision.contacts[0].entity_flags = mover.flags
	level.entity_collision.contacts[0].radius_squared = 25
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities.entities[0].matrix12[9], -193)
	assert_eq(EntityContactOrder.indices(level.entity_collision, run.snapshot().entities, Vector3i(-128, 0, -128)).size(), 0)
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.entities.entities[0].matrix12[9], -128)
	assert_eq(result.final_snapshot.entity_hit_indices, PackedInt32Array([6]))
	assert_eq(result.final_snapshot.death_entity_index, 6)

func test_pop_requests_death_even_when_animation_is_locked() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision = _collision([_static(3, -128, -128)])
	var lengths := PackedInt32Array()
	for _index: int in FrogAnimationCatalog.ACTION_NAMES.size():
		lengths.append(3)
	level.frog_action_lengths = lengths
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	run._animation.state.flags |= 32
	run._state.animation = run._animation.state.copy()
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.death_equate, 23)
	assert_eq(result.final_snapshot.last_animation_request, 23)
	assert_eq(result.final_snapshot.animation_requests, 1)
	assert_eq(result.final_snapshot.animation.script_type, FrogAnimationCatalog.PANT)
	assert_true(result.events.has("entity_pop_explosion_request"))

func test_pop_life_request_and_active_flag_boundaries() -> void:
	for lives: int in [0, 1, 2]:
		var level: LevelDefinition = _level()
		level.entity_collision = _collision([_static(3, -128, -128)])
		var start := RunStart.new()
		start.lives = lives
		var run: TerrainRun = TerrainRun.create(level, start)
		assert_eq(run.error, "")
		var result: TickResult = run.step(TickCommand.new())
		assert_eq(result.error, "", "lives %d" % lives)
		assert_eq(result.final_snapshot.death_equate, 23)
		assert_eq(result.final_snapshot.fixture_lives, lives)
		assert_eq(result.final_snapshot.life_decrement_requested, lives > 0)
		assert_eq(bool(result.final_snapshot.flags & 1), lives > 1)
		assert_eq(result.events.count("entity_pop_explosion_request"), 1)
