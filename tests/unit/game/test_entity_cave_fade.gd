extends GutTest
## Hand-derived frozen cave fade ramp, colour-scale policy and run ordering.

func _entity(live_flags: int = 0, entity_flags: int = 0) -> EntitySnapshot:
	var result := EntitySnapshot.new()
	result.live = true
	result.live_flags = live_flags
	result.entity_flags = entity_flags
	return result

func _definition(form_flags: int = 0) -> EntityDefinition:
	var result := EntityDefinition.new()
	result.form_flags = form_flags
	return result

func test_ramp_saturates_inside_minimum_and_beyond_maximum() -> void:
	assert_eq(EntityCaveFade.colour(Vector3i(5, 900, 7), Vector3i(15, -900, 7), 200, 400), 128)
	assert_eq(EntityCaveFade.colour(Vector3i(0, 0, 0), Vector3i(0, 0, 20), 400, 800), 128)
	assert_eq(EntityCaveFade.colour(Vector3i(0, 0, 0), Vector3i(30, 0, 0), 200, 400), 0)
	assert_eq(EntityCaveFade.colour(Vector3i(0, 0, 0), Vector3i(20, 0, 0), 200, 400), 0)

func test_ramp_interpolates_with_source_fixed_point() -> void:
	assert_eq(EntityCaveFade.colour(Vector3i.ZERO, Vector3i(1024, 0, 725), 0x100000, 0x200000), 64)
	assert_eq(EntityCaveFade.colour(Vector3i(-1024, 0, -725), Vector3i.ZERO, 0xF0000, 0x1F0000), 56)

func test_squared_distance_compares_unsigned() -> void:
	assert_eq(EntityCaveFade.colour(Vector3i(-25000, 0, 0), Vector3i(25000, 0, 0), 0x100000, 0x200000), 0)
	assert_eq(EntityCaveFade.colour(Vector3i(-25000, 0, 0), Vector3i(25000, 0, 0), 0xFFFFFFF0, 0xFFFFFFFF), 128)

func test_sprite_scale_quadruples_and_caps() -> void:
	var sprite: EntityDefinition = _definition(EntityCaveFade.FORM_NO_MODEL)
	for pair: Vector2i in [Vector2i(31, 124), Vector2i(32, 128), Vector2i(40, 128), Vector2i(0, 0)]:
		var entity: EntitySnapshot = _entity()
		EntityCaveFade.apply(entity, sprite, pair.x)
		assert_eq(entity.colour_scale, Vector3i(pair.y, pair.y, pair.y), str(pair))
		assert_true(entity.colour_scaled)

func test_sprite_opt_outs_and_hidden_entities_keep_colours() -> void:
	var cases: Array = [
		[_definition(EntityCaveFade.FORM_NO_MODEL | EntityCaveFade.FORM_NO_COLOUR_FADE), _entity()],
		[_definition(EntityCaveFade.FORM_NO_MODEL), _entity(EntityLiveFlags.NO_COLOUR_FADE)],
		[_definition(), _entity(0, EntityDefinition.NO_DISPLAY)],
		[_definition(EntityCaveFade.FORM_NO_MODEL), _entity(0, EntityDefinition.NO_DISPLAY)],
	]
	for row: Array in cases:
		var definition: EntityDefinition = row[0]
		var entity: EntitySnapshot = row[1]
		entity.colour_scale = Vector3i(1, 2, 3)
		EntityCaveFade.apply(entity, definition, 64)
		assert_eq(entity.colour_scale, Vector3i(1, 2, 3))
		assert_false(entity.colour_scaled)

func test_models_set_or_respect_existing_scale() -> void:
	var entity: EntitySnapshot = _entity(EntityLiveFlags.NO_COLOUR_FADE)
	entity.colour_scale = Vector3i(200, 100, 64)
	EntityCaveFade.apply(entity, _definition(), 64)
	assert_eq(entity.colour_scale, Vector3i(64, 64, 64))
	assert_true(entity.colour_scaled)
	var respecting: EntitySnapshot = _entity(EntityLiveFlags.RESPECT_SCALE_COLOURS)
	respecting.colour_scale = Vector3i(200, 100, 64)
	EntityCaveFade.apply(respecting, _definition(), 64)
	assert_eq(respecting.colour_scale, Vector3i(100, 50, 32))
	assert_true(respecting.colour_scaled)
	var animated: EntitySnapshot = _entity(EntityLiveFlags.ANIMATED)
	EntityCaveFade.apply(animated, _definition(EntityCaveFade.FORM_NO_MODEL | EntityCaveFade.FORM_NO_COLOUR_FADE), 31)
	assert_eq(animated.colour_scale, Vector3i(31, 31, 31))
	var black: EntitySnapshot = _entity()
	EntityCaveFade.apply(black, _definition(), 0)
	assert_eq(black.colour_scale, Vector3i.ZERO)
	assert_true(black.colour_scaled)

func _contact(definition: EntityDefinition) -> FormContactDefinition:
	var contact := FormContactDefinition.new()
	contact.entity_index = definition.entity_index
	contact.unique_id = definition.unique_id
	contact.form_id = definition.form_id
	contact.form_grid_id = definition.form_grid_id
	contact.form_name = definition.form_name
	contact.entity_flags = definition.flags
	contact.dimensions = Vector2i.ONE
	contact.grid_flags = PackedInt32Array([1])
	return contact

func _cave_level(offset: Vector3i, frog_position: Vector3i) -> LevelDefinition:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.spawn_cell = Vector2i(1, 1)
	level.collision_enabled = true
	level.cave_light = true
	level.camera.source_offset = Vector3i(0, -512, -512)
	var rock := EntityDefinition.new()
	rock.entity_index = 1
	rock.unique_id = 11
	rock.entity_name = "STATIC"
	rock.behavior = EntityBehaviorCatalog.resolve(rock.entity_name)
	rock.behavior.immortal = true
	rock.flags = EntityDefinition.NO_COLLISION
	rock.matrix12[9] = frog_position.x + offset.x
	rock.matrix12[10] = frog_position.y
	rock.matrix12[11] = frog_position.z + offset.z
	var light := EntityDefinition.new()
	light.entity_index = 2
	light.unique_id = 12
	light.entity_name = "CAV_FROGGER_LIGHT"
	light.behavior = EntityBehaviorCatalog.resolve(light.entity_name)
	light.behavior.execution = EntityBehavior.Execution.CONTACT
	light.flags = EntityDefinition.NO_COLLISION
	light.form_flags = 1
	light.cave = EntityCaveDefinition.new()
	light.cave.light_max_squared = 0x200000
	light.cave.light_min_squared = 0x100000
	light.cave.light_die = 0x10000
	level.entity_collision = EntityCollisionDefinition.new()
	for definition: EntityDefinition in [rock, light]:
		level.entity_collision.entities.append(definition)
		level.entity_collision.contacts.append(_contact(definition))
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
	return level

func _spawn_position() -> Vector3i:
	var probe: GameplayRun = GameplayRun.create(TerrainScenario.builtin("normal").level)
	var matrix: PackedInt32Array = probe.snapshot().frog.matrix12
	return Vector3i(matrix[9], matrix[10], matrix[11])

func test_reset_seeds_environment_from_immortal_light_creation() -> void:
	var run: GameplayRun = GameplayRun.create(_cave_level(Vector3i(1024, 0, 725), _spawn_position()))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var state: GameplayState = run.snapshot()
	assert_eq(state.entity_environment.light_max_squared, 0x200000)
	assert_eq(state.entity_environment.light_min_squared, 0x100000)
	assert_false(state.entities.entities[0].colour_scaled, "Creation never fades")
	state.entity_environment.light_max_squared = 7
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().entity_environment.light_max_squared, 0x200000)

func test_visit_fade_uses_radii_after_earlier_light_update_and_rolls_back() -> void:
	var frog: Vector3i = _spawn_position()
	var level: LevelDefinition = _cave_level(Vector3i(1024, 0, 725), frog)
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var before: GameplayState = run.snapshot()
	run._entities._lifecycle.polygon_counts.fill(2500)
	var failed: TickResult = run.step(TickCommand.new())
	assert_ne(failed.error, "")
	assert_false(run.snapshot().entities.entities[0].colour_scaled)
	assert_eq(run.snapshot().entity_environment.light_max_squared, before.entity_environment.light_max_squared)
	run._entities._lifecycle.polygon_counts.fill(1)
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	var final: GameplayState = result.final_snapshot
	assert_eq(final.entity_environment.light_max_squared, 0x1F0000)
	assert_eq(final.entity_environment.light_min_squared, 0xF0000)
	var rock: EntitySnapshot = final.entities.entities[0]
	assert_true(rock.colour_scaled)
	assert_eq(rock.colour_scale, Vector3i(56, 56, 56))
	var observed: bool = false
	for update: EntityUpdateObservation in final.entities.updates:
		if update.entity.entity_index == 1:
			observed = true
			assert_eq(update.entity.colour_scale, Vector3i(56, 56, 56))
	assert_true(observed)

func test_non_cave_levels_never_fade() -> void:
	var level: LevelDefinition = _cave_level(Vector3i(1024, 0, 725), _spawn_position())
	level.cave_light = false
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if result.error.is_empty():
		assert_false(result.final_snapshot.entities.entities[0].colour_scaled)
		assert_eq(result.final_snapshot.entities.entities[0].colour_scale, Vector3i.ZERO)
