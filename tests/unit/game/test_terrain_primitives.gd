extends GutTest
## Primitive precedence, source flags and full terrain transaction ownership.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]

func _level(indices: PackedInt32Array = PackedInt32Array([2])) -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(2, 2)
	level.grid.base = Vector2i(-256, -256)
	level.spawn_cell = Vector2i.ZERO
	level.collision_enabled = true
	for index: int in 4:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 3
		var x: int = -256 + (index % 2) * 256
		@warning_ignore("integer_division")
		var z: int = -256 + (index / 2) * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		level.grid.squares.append(square)
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
	for index: int in indices:
		var entity := EntityDefinition.new()
		entity.entity_name = "STATIC"
		entity.behavior = EntityBehaviorCatalog.resolve(entity.entity_name)
		entity.entity_index = index
		entity.unique_id = index + 7
		entity.form_grid_id = 2
		entity.form_id = 3
		entity.form_name = "TEST"
		entity.matrix12[9] = -128
		entity.matrix12[11] = -128
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
		contact.grid_flags = PackedInt32Array([4097])
		var primitive := EntityPrimitiveDefinition.new()
		primitive.half_size = Vector3i(50, 50, 50)
		contact.primitives.append(primitive)
		collision.contacts.append(contact)
	level.entity_collision = collision
	return level

func test_primitive_hit_precedes_pop_form_and_retains_first_source_winner() -> void:
	var run: TerrainRun = TerrainRun.create(_level(PackedInt32Array([2, 7])))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.primitive_contacts.size(), 2)
	assert_eq(result.primitive_contacts[0].entity_index, 7)
	assert_eq(result.primitive_contacts[1].entity_index, 2)
	assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.CONTACT)
	assert_true(result.entity_contacts.is_empty())
	assert_eq(result.final_snapshot.attachment.entity_hit_indices, PackedInt32Array([7, 2]))
	assert_eq(result.final_snapshot.diagnostics.death_entity_index, 7)
	assert_eq(result.final_snapshot.frog.death_equate, FrogAnimationCatalog.SQUISHED)
	assert_eq(result.collision_snapshot.frog.matrix12.slice(3, 6), PackedInt32Array([0, 0, 0]))
	assert_eq(TickEvent.trace_lines(result.events).count("entity_squish"), 1)
	assert_false(TickEvent.trace_lines(result.events).has("entity_pop_explosion_request"))

func test_primitive_miss_and_disabled_shape_fall_back_to_pop_form() -> void:
	for disabled: bool in [false, true]:
		var level: LevelDefinition = _level()
		if disabled:
			level.entity_collision.contacts[0].primitives[0].flags |= 256
		else:
			level.entity_collision.contacts[0].primitives[0].offset.x = 100
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		if not run.error.is_empty():
			return
		var result: TickResult = run.step(TickCommand.new())
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
		assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.DISABLED if disabled else EntityPrimitiveQuery.MISS)
		assert_eq(result.entity_contacts[0].status, FormReactionResult.POP)
		assert_eq(result.final_snapshot.frog.death_equate, FrogAnimationCatalog.POP)
		assert_eq(TickEvent.trace_lines(result.events).count("entity_pop_explosion_request"), 1)

func test_primitive_miss_deadly_form_squishes_without_primitive_flatten() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].primitives[0].offset.x = 100
	level.entity_collision.contacts[0].grid_flags[0] = 5
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.entity_contacts[0].status, FormReactionResult.SQUISH)
	assert_eq(result.final_snapshot.frog.death_equate, FrogAnimationCatalog.SQUISHED)
	assert_eq(result.collision_snapshot.frog.matrix12[4], 4096)

func test_entity_no_collision_disables_both_contact_paths() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.entities[0].flags = EntityDefinition.NO_COLLISION
	level.entity_collision.contacts[0].entity_flags = EntityDefinition.NO_COLLISION
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.DISABLED)
	assert_eq(result.entity_contacts[0].contact.status, FormContactResult.DISABLED)
	assert_eq(result.final_snapshot.diagnostics.death_entity_index, -1)
	assert_true(result.final_snapshot.attachment.entity_hit_indices.is_empty())

func test_late_failure_rolls_back_hits_and_stored_pose_then_retries() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	run._animation.error = "forced primitive late failure"
	var failed: TickResult = run.step(TickCommand.new())
	assert_eq(failed.error, "forced primitive late failure")
	assert_null(failed.control_snapshot)
	assert_null(failed.move_snapshot)
	assert_null(failed.collision_snapshot)
	assert_null(failed.camera_snapshot)
	assert_null(failed.scripts_snapshot)
	assert_null(failed.final_snapshot)
	assert_true(failed.entity_contacts.is_empty())
	assert_true(failed.primitive_contacts.is_empty())
	assert_true(failed.events.is_empty())
	assert_true(failed.rng_consumers.is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)
	run._animation.error = ""
	var succeeded: TickResult = run.step(TickCommand.new())
	assert_eq(succeeded.error, "")
	assert_eq(succeeded.final_snapshot.diagnostics.death_entity_index, 2)
	assert_eq(succeeded.primitive_contacts.size(), 1)

func test_setup_and_snapshots_detach_primitive_and_cached_probe_facts() -> void:
	var level: LevelDefinition = _level()
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	level.entity_collision.contacts[0].primitives[0].offset.x = 500
	level.entity_collision.frog_collision.probes[0].vertex.x = 500
	level.entity_collision.frog_collision.actions[0].frames[0][9] = 500
	var snapshot: RunSnapshot = run.snapshot()
	var original_point: Vector3i = snapshot.frog.frog_collision_pose.probes.points[0]
	snapshot.frog.frog_collision_pose.probes.points[0].x = 999
	snapshot.frog.frog_collision_pose.action = 999
	assert_eq(run.snapshot().frog.frog_collision_pose.probes.points[0], original_point)
	assert_eq(run.snapshot().frog.frog_collision_pose.action, 0)
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.CONTACT)

func test_primitive_hit_drives_traffic_splat_on_the_following_update() -> void:
	var level: LevelDefinition = _level()
	var script := EntityScriptDefinition.new()
	script.root_id = 1
	script.programs[1] = PackedInt32Array([34, 0, 0, 0, 0, 38])
	script.names[1] = "SCRIPT_ORG_CAR_BLUE"
	script.callbacks[0] = "SCRIPT_CB_FROG_TRAFFIC_SPLAT"
	level.entity_collision.entities[0].script_definition = script
	level.entity_collision.entities[0].action_lengths = PackedInt32Array([1])
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var first: TickResult = run.step(TickCommand.new())
	assert_eq(first.error, "")
	assert_false(TickEvent.trace_lines(first.events).has("entity:2:sound:13:0:0:0"))
	var command := TickCommand.new()
	command.tick_index = 1
	var second: TickResult = run.step(command)
	assert_eq(second.error, "")
	assert_eq(TickEvent.trace_lines(second.events).count("entity:2:sound:13:0:0:0"), 1)
	assert_eq(second.control_snapshot.entities.updates[0].previous_flags & 64, 64)
	assert_true(second.final_snapshot.attachment.entity_hit_indices.is_empty())
