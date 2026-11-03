extends GutTest
## Forest candidate ownership and atomic rejection of incomplete dependencies.

func test_swarm_and_environment_copies_own_every_mutable_field() -> void:
	var original := EntitySnapshot.new()
	original.custom_state = EntityCustomState.new()
	original.custom_state.swarm = EntitySwarmState.new()
	original.custom_state.swarm.positions[0] = Vector3i(10, 20, 30)
	original.custom_state.swarm.matrix12[9] = 100
	original.custom_state.swarm.angles[0] = 512
	var copied: EntitySnapshot = original.copy()
	copied.custom_state.swarm.positions[0] = Vector3i(-1, -2, -3)
	copied.custom_state.swarm.matrix12[9] = -100
	copied.custom_state.swarm.angles[0] = 1024
	copied.custom_state.swarm.visible = true
	assert_eq(original.custom_state.swarm.positions[0], Vector3i(10, 20, 30))
	assert_eq(original.custom_state.swarm.matrix12[9], 100)
	assert_eq(original.custom_state.swarm.angles[0], 512)
	assert_false(original.custom_state.swarm.visible)
	var environment := EntityEnvironmentState.new()
	environment.active_swarms = 2
	var next: EntityEnvironmentState = environment.copy()
	next.active_swarms = 3
	assert_eq(environment.active_swarms, 2)

func test_failed_branch_terrain_lookup_discards_decrement_and_outputs() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_BREAKING_BRANCH")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.mode = 1
	entity.custom_state.timer = 0
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var random: SourceRandom = SourceRandom.create(17)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, random, Vector3i.ZERO, false, false)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_null(result.environment)
	assert_null(result.random)
	assert_eq(entity.custom_state.mode, 1)
	assert_eq(entity.custom_state.timer, 0)
	assert_true(entity.requests.is_empty())
	assert_eq(random.draw_count, 0)

func test_invalid_squirrel_animation_preserves_previous_state() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_SQUIRREL")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.path = PathSnapshot.new()
	entity.path.flags = PathStart.JUST_BOUNCED_END
	entity.animation = EntityAnimationState.create(PackedInt32Array([4]))
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_eq(result.path_active_request, -1)
	assert_eq(entity.custom_state.mode, 0)
	assert_eq(entity.animation.action, 0)
	assert_eq(entity.path.flags, PathStart.JUST_BOUNCED_END)

func test_failed_hive_height_lookup_discards_motion_and_shared_count() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_HIVE")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.forest = EntityForestDefinition.new()
	definition.forest.swarm_speed = 1000
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.mode = 1
	entity.custom_state.swarm = EntitySwarmState.new()
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	environment.active_swarms = 1
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = 1000
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false, null, null, frog)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_null(result.environment)
	assert_eq(entity.custom_state.swarm.speed, 0)
	assert_eq(entity.custom_state.swarm.matrix12[9], 0)
	assert_eq(environment.active_swarms, 1)

func test_trace_facts_include_swarm_positions_and_shared_swarm_count() -> void:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.swarm = EntitySwarmState.new()
	entity.custom_state.swarm.positions[1] = Vector3i(12, -64, 32)
	entity.custom_state.swarm.speed = 257
	var facts: Dictionary = TerrainTrace.facts(entity)
	var position: Array = facts.background.swarm.positions[1]
	assert_eq(position, [12, -64, 32])
	var speed: int = facts.background.swarm.speed
	assert_eq(speed, 257)
	var environment := EntityEnvironmentState.new()
	environment.active_swarms = -1
	var count: int = TerrainTrace.facts(environment).active_swarms
	assert_eq(count, -1)

func test_hive_stopped_target_returns_before_pitch_rng() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_HIVE")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.forest = EntityForestDefinition.new()
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.mode = 1
	entity.custom_state.swarm = EntitySwarmState.new()
	entity.custom_state.moving_voice_active = true
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	environment.active_swarms = 1
	var frog := GameplayState.new()
	frog.frog.mode = FrogMode.DYING
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false, null, null, frog)
	assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, 3)
	assert_eq(result.random.draw_count, 0)
	assert_true(result.entity.requests.is_empty())
	assert_eq(entity.custom_state.mode, 1)
	assert_eq(result.environment.active_swarms, 1)

func test_last_life_sting_removes_frog_from_following_visibility_query() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_HIVE")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.forest = EntityForestDefinition.new()
	definition.forest.swarm_speed = 1000
	var stump := EntityDefinition.new()
	stump.behavior = EntityBehaviorCatalog.resolve("STATIC")
	stump.form_id = 9
	var contact := FormContactDefinition.new()
	contact.dimensions = Vector2i(1, 1)
	contact.radius_squared = 1000000
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i(1, 1)
	collision.group_size = Vector2i(1024, 1024)
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i.ZERO
	for case: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		var lives: int = case.x
		var infinite: bool = case.y == 1
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		entity.custom_state.mode = 1
		entity.custom_state.swarm = EntitySwarmState.new()
		var environment := EntityEnvironmentState.new()
		environment.checkpoint_positions.resize(5)
		environment.active_swarms = 1
		var frog := GameplayState.new()
		frog.frog.flags = FrogFlags.ACTIVE | FrogFlags.CONTROL_ACTIVE
		frog.frog.lives = lives
		frog.cheats.infinite_lives = infinite
		frog.frog.matrix12[9] = 100
		var neighbors: Array[EntitySnapshot] = [EntitySnapshot.new()]
		var definitions: Array[EntityDefinition] = [stump]
		var contacts: Array[FormContactDefinition] = [contact]
		var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false, null, null, frog, neighbors, definitions, 0, grid, collision, contacts)
		assert_eq(result.error, "")
		assert_eq(result.death_animation, FrogAnimationCatalog.FLOP)
		var removed: bool = Frog.kill_deactivates(lives, infinite)
		assert_eq(removed, lives == (0 if infinite else 1))
		assert_eq(result.entity.custom_state.mode, 2 if removed else 3, "lives %d infinite %s" % [lives, infinite])
		assert_true(bool(frog.frog.flags & FrogFlags.ACTIVE))

func test_missing_hedgehog_projection_grid_rolls_back_action_and_timer() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_HEDGEHOG")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.forest = EntityForestDefinition.new()
	definition.flags = EntityDefinition.PROJECT_ON_LAND
	var entity := EntitySnapshot.new()
	entity.entity_flags = definition.flags
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.timer = 0
	entity.path = PathSnapshot.new()
	entity.path.tangent = Vector3i(0, 0, 4096)
	entity.animation = EntityAnimationState.create(PackedInt32Array([4, 4]))
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_eq(entity.custom_state.mode, 0)
	assert_eq(entity.custom_state.timer, 0)
	assert_eq(entity.animation.action, 0)
	assert_eq(entity.path.position, Vector3i.ZERO)

func test_projected_hedgehog_factory_keeps_path_height_until_live_update() -> void:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve("FOR_HEDGEHOG")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.forest = EntityForestDefinition.new()
	definition.forest.run_time = 10
	definition.forest.roll_time = 20
	definition.forest.run_speed = 256
	definition.forest.roll_speed = 512
	definition.flags = EntityDefinition.PROJECT_ON_LAND
	definition.action_lengths = PackedInt32Array([4, 4])
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.start = Vector3i(0, 777, 0)
	segment.end = Vector3i(0, 777, 256)
	segment.length = 256
	definition.path_definition = PathDefinition.new()
	definition.path_definition.segments.append(segment)
	definition.path_start = PathStart.new()
	definition.path_start.flags = PathStart.ACTIVE
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(run.snapshot().entities[0].matrix12[10], 777)
	assert_eq(run.snapshot().entities[0].custom_state.timer, 10)

func _hive_transaction_level() -> LevelDefinition:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.spawn_cell = Vector2i(1, 1)
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	level.camera.source_offset = Vector3i(0, -512, -512)
	level.camera.target_offset = Vector3i.ZERO
	var hive := EntityDefinition.new()
	hive.entity_index = 9
	hive.unique_id = 77
	hive.entity_name = "FOR_HIVE"
	hive.behavior = EntityBehaviorCatalog.resolve(hive.entity_name)
	hive.behavior.execution = EntityBehavior.Execution.CONTACT
	hive.flags = EntityDefinition.NO_COLLISION
	hive.forest = EntityForestDefinition.new()
	hive.forest.release_distance = 2048
	hive.forest.swarm_speed = 10922
	var contact := FormContactDefinition.new()
	contact.entity_index = hive.entity_index
	contact.unique_id = hive.unique_id
	contact.form_grid_id = hive.form_grid_id
	contact.form_id = hive.form_id
	contact.entity_flags = hive.flags
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-128, -128)
	contact.height = 0
	contact.max_y = 64
	contact.radius_squared = 1000000
	contact.grid_flags = PackedInt32Array([1])
	level.entity_collision = EntityCollisionDefinition.new()
	level.entity_collision.entities.append(hive)
	level.entity_collision.contacts.append(contact)
	level.entity_collision.environment = EntityEnvironmentState.new()
	level.entity_collision.environment.checkpoint_positions.resize(5)
	level.entity_collision.group_base = Vector3i(-8192, 0, -8192)
	level.entity_collision.group_dimensions = Vector2i(32, 32)
	level.entity_collision.group_size = Vector2i(512, 512)
	var lifetime := EntityLifecycleDefinition.new()
	lifetime.group_base = level.entity_collision.group_base
	lifetime.group_dimensions = level.entity_collision.group_dimensions
	lifetime.group_size = level.entity_collision.group_size
	lifetime.polygon_counts.resize(1024)
	lifetime.polygon_counts.fill(1)
	level.entity_collision.lifecycle = lifetime
	var buzz := LogicalSoundDefinition.new()
	buzz.sound_id = 64
	buzz.flags = LogicalSoundDefinition.LOOPED
	buzz.frame_count = 10000
	level.sounds.append(buzz)
	return level

func test_late_visibility_failure_rolls_back_swarm_environment_rng_and_sound() -> void:
	var level: LevelDefinition = _hive_transaction_level()
	var clean: GameplayRun = GameplayRun.create(level)
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(clean.error, "")
	assert_eq(run.error, "")
	if not clean.error.is_empty() or not run.error.is_empty():
		return
	var command := TickCommand.new()
	var expected: TickResult = clean.step(command)
	assert_eq(expected.error, "")
	if not expected.error.is_empty():
		return
	assert_eq(expected.final_snapshot.entities.entities[0].custom_state.mode, EntityHive.Mode.CHASING)
	assert_eq(expected.final_snapshot.entity_environment.active_swarms, 1)
	assert_has(expected.rng_consumers, "entity:9:hive_pitch")
	var pitch_seen: bool = false
	for event: TickEvent in expected.events:
		pitch_seen = pitch_seen or event.kind == TickEvent.Kind.PITCH_BEND
	assert_true(pitch_seen)
	var before: String = ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true))
	run._entities._lifecycle.polygon_counts.fill(2500)
	var failed: TickResult = run.step(command)
	assert_string_contains(failed.error, "2500")
	assert_null(failed.final_snapshot)
	assert_true(failed.events.is_empty())
	assert_true(failed.rng_consumers.is_empty())
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), before)
	run._entities._lifecycle.polygon_counts.fill(1)
	var retried: TickResult = run.step(command)
	assert_eq(retried.error, "")
	assert_eq(retried.rng_consumers, expected.rng_consumers)
	assert_eq(TickEvent.trace_lines(retried.events), TickEvent.trace_lines(expected.events))
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), ZoneLifecycleChecks.canonical(TerrainTrace.facts(clean.snapshot(), true)))
