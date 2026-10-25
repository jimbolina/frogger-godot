extends GutTest
## Visibility tail ordering and complete frog/entity/camera transaction boundaries.

func _level(flags: int = 4097) -> LevelDefinition:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.spawn_cell = Vector2i(1, 1)
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	level.camera.source_offset = Vector3i(0, -512, -512)
	level.camera.target_offset = Vector3i.ZERO
	var entity := EntityDefinition.new()
	entity.entity_index = 9
	entity.unique_id = 77
	entity.entity_name = "STATIC"
	entity.form_name = "TEST"
	entity.matrix12[9] = -128
	entity.matrix12[11] = -128
	var contact := FormContactDefinition.new()
	contact.entity_index = 9
	contact.unique_id = 77
	contact.form_name = "TEST"
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.dimensions = Vector2i(2, 1)
	contact.offsets = Vector2i(-128, -128)
	contact.height = 0
	contact.max_y = 64
	contact.radius_squared = 1000000
	contact.grid_flags = PackedInt32Array([flags, flags])
	level.entity_collision = EntityCollisionDefinition.new()
	level.entity_collision.entities.append(entity)
	level.entity_collision.contacts.append(contact)
	level.entity_collision.platforms_enabled = bool(flags & 2)
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

func _tick(run: TerrainRun, pressed: int = 0) -> TickResult:
	var command := TickCommand.new()
	command.tick_index = run.snapshot().tick_index
	command.pressed_mask = pressed
	return run.step(command)

func _assert_failed(result: TickResult) -> void:
	assert_false(result.error.is_empty())
	assert_null(result.control_snapshot)
	assert_null(result.move_snapshot)
	assert_null(result.collision_snapshot)
	assert_null(result.camera_snapshot)
	assert_null(result.scripts_snapshot)
	assert_null(result.final_snapshot)
	assert_true(result.events.is_empty())
	assert_true(result.entity_contacts.is_empty())
	assert_true(result.rng_consumers.is_empty())

func _active_zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.bounds = PackedInt32Array([0, 0, 3, 3])
	for unused: int in 4:
		zone.camera_offsets.append(Vector3i(0, -768, -768))
		zone.camera_offsets.append(Vector3i.ZERO)
	return zone

func test_zone_transition_visibility_failure_rolls_back_every_component_and_retries() -> void:
	var level: LevelDefinition = _level()
	level.camera_zones.append(_active_zone())
	var run: TerrainRun = TerrainRun.create(level)
	var clean: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	assert_eq(_tick(clean).error, "")
	var before: String = ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true))
	run._entities._lifecycle.polygon_counts.fill(2500)
	var failure: TickResult = _tick(run)
	_assert_failed(failure)
	assert_string_contains(failure.error, "2500")
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), before)
	run._entities._lifecycle.polygon_counts.fill(1)
	assert_eq(_tick(run).error, "")
	assert_eq(_tick(clean).error, "")
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), ZoneLifecycleChecks.canonical(TerrainTrace.facts(clean.snapshot(), true)))
	assert_eq(run.snapshot().death_entity_index, 9)
	assert_eq(run.snapshot().camera.zone_index, 0)

func test_active_zone_safe_attachment_and_departure_keep_live_generation() -> void:
	var level: LevelDefinition = _level(3 | 256)
	level.camera_zones.append(_active_zone())
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, 9)
	assert_eq(run.snapshot().camera.zone_index, 0)
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	for unused: int in 5:
		assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, 9)
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	for unused: int in 6:
		assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().entities.entities[0].generation, 1)

func test_moving_safe_platform_composes_zone_camera_with_visibility() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_file("res://tests/golden/fixtures/lifecycle_safe_moving.json")
	assert_eq(scenario.error, "")
	assert_eq(scenario.apply_arguments(PackedStringArray(["--entity-lifecycle=visibility"])), "")
	scenario.level.camera_zones.append(_active_zone())
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var attached: bool = false
	var departed: bool = false
	for tick: int in scenario.tick_limit:
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
		var state: RunSnapshot = result.final_snapshot
		if state.current_entity_index >= 0:
			attached = true
			assert_eq(state.camera.zone_index, 0)
			assert_true(state.entities.live_order.has(state.current_entity_index))
		elif attached:
			departed = true
	assert_true(attached)
	assert_true(departed)

func test_tail_creation_defers_pop_until_following_tick() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_false(run.snapshot().entities.entities[0].live)
	var first: TickResult = _tick(run)
	assert_eq(first.error, "")
	if not first.error.is_empty():
		return
	assert_false(first.collision_snapshot.entities.entities[0].live)
	assert_false(first.scripts_snapshot.entities.entities[0].live)
	assert_true(first.final_snapshot.entities.entities[0].live)
	assert_eq(first.final_snapshot.entities.entities[0].generation, 1)
	assert_true(first.entity_contacts.is_empty())
	assert_eq(first.final_snapshot.death_entity_index, -1)
	var second: TickResult = _tick(run)
	assert_eq(second.error, "")
	if second.error.is_empty():
		assert_eq(second.final_snapshot.death_entity_index, 9)
		assert_true(second.events.has("entity_pop_explosion_request"))

func test_visibility_requires_camera_and_preserves_all_attached_default() -> void:
	var level: LevelDefinition = _level()
	level.camera = null
	assert_string_contains(TerrainRun.create(level).error, "camera")
	level.entity_collision.lifecycle = null
	var legacy: TerrainRun = TerrainRun.create(level)
	assert_eq(legacy.error, "")
	if legacy.error.is_empty():
		assert_eq(_tick(legacy).final_snapshot.death_entity_index, 9)

func test_safe_mount_local_hop_and_departure_keep_live_identity() -> void:
	var run: TerrainRun = TerrainRun.create(_level(3 | 256))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, 9)
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	for unused: int in 5:
		assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, 9)
	assert_eq(run.snapshot().entity_cell, Vector2i(1, 0))
	var departure: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(departure.error, "")
	if not departure.error.is_empty():
		return
	assert_eq(departure.final_snapshot.forbidden_entity_index, 9)
	for unused: int in 6:
		assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, -1)

func test_missing_or_dormant_current_attachment_fails_before_mutation() -> void:
	for identity: int in [9, 99]:
		var run: TerrainRun = TerrainRun.create(_level(3 | 256))
		assert_eq(run.error, "")
		if not run.error.is_empty():
			return
		run._state.current_entity_index = identity
		_assert_failed(_tick(run))
		assert_eq(run.snapshot().tick_index, 0)
		assert_false(run.snapshot().entities.entities[0].live)

func test_forbidden_identity_without_current_link_does_not_pin() -> void:
	var run: TerrainRun = TerrainRun.create(_level(3 | 256))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	# Represent a prior offscreen update with only the departure exclusion left.
	run._entities._state.entities[0].destroy_pending = true
	run._state.forbidden_entity_index = 9
	assert_eq(run.snapshot().current_entity_index, -1)
	var next: TickResult = _tick(run)
	assert_eq(next.error, "")
	if next.error.is_empty():
		assert_eq(next.final_snapshot.entities.lifecycle_events, ["destroy:9:1", "create:9:2"])
		assert_false(next.collision_snapshot.entities.entities[0].live)
		assert_eq(next.final_snapshot.current_entity_index, -1)

func test_late_budget_failure_rolls_back_pop_camera_rng_and_retries() -> void:
	var level: LevelDefinition = _level()
	level.frog_action_lengths.clear()
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(3)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var before: RunSnapshot = run.snapshot()
	# Fault injection is confined to the owned candidate definition, never player data.
	run._entities._lifecycle.polygon_counts.fill(2500)
	var failed: TickResult = _tick(run)
	_assert_failed(failed)
	assert_string_contains(failed.error, "2500")
	var after: RunSnapshot = run.snapshot()
	assert_eq(after.tick_index, before.tick_index)
	assert_eq(after.death_entity_index, -1)
	assert_eq(after.camera.source_world, before.camera.source_world)
	assert_eq(after.camera.mode, before.camera.mode)
	assert_eq(after.animation.cel, before.animation.cel)
	assert_eq(after.rng_state, before.rng_state)
	assert_eq(after.rng_draw_count, before.rng_draw_count)
	assert_eq(after.entities.live_order, before.entities.live_order)
	assert_eq(after.entities.selected_groups, before.entities.selected_groups)
	assert_eq(after.entities.entities[0].generation, 1)
	assert_false(after.entities.entities[0].destroy_pending)
	run._entities._lifecycle.polygon_counts.fill(1)
	var retry: TickResult = _tick(run)
	assert_eq(retry.error, "")
	if retry.error.is_empty():
		assert_eq(retry.final_snapshot.death_entity_index, 9)
		assert_eq(retry.events.count("entity_pop_explosion_request"), 1)

func test_reset_and_detached_nested_lifecycle_snapshots() -> void:
	var level: LevelDefinition = _level(3 | 256)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	assert_eq(_tick(run).error, "")
	var before: RunSnapshot = run.snapshot()
	var detached: RunSnapshot = before.copy()
	detached.entities.entities[0].live = false
	detached.entities.entities[0].generation = 100
	detached.entities.live_order.clear()
	detached.entities.selected_groups.clear()
	detached.entities.lifecycle_events.append("fake")
	level.entity_collision.lifecycle.polygon_counts.fill(2500)
	assert_true(run.snapshot().entities.entities[0].live)
	assert_eq(run.snapshot().entities.entities[0].generation, 1)

	assert_eq(run.snapshot().entities.live_order, before.entities.live_order)
	var invalid := RunStart.new()
	invalid.spawn_cell = Vector2i(99, 99)
	assert_false(run.reset(invalid).is_empty())
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().current_entity_index, 9)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().forbidden_entity_index, -1)
	assert_false(run.snapshot().entities.entities[0].live)
	assert_eq(run.snapshot().entities.entities[0].generation, 0)
	assert_true(run.snapshot().entities.live_order.is_empty())
	assert_true(run.snapshot().entities.selected_groups.is_empty())
	assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().entities.entities[0].generation, 1)

func test_visibility_failure_after_stun_random_draws_retries_identically() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.entities[0].flags = EntityDefinition.NO_COLLISION
	level.entity_collision.contacts[0].entity_flags = EntityDefinition.NO_COLLISION
	level.theme_name = &"JUN"
	level.theme = 4
	for index: int in level.grid.squares[9].vertices.size():
		level.grid.squares[9].vertices[index].y = 513
	var reference: TerrainRun = TerrainRun.create(level)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(reference.error, "")
	assert_eq(run.error, "")
	if not run.error.is_empty() or not reference.error.is_empty():
		return
	var observed_draws: bool = false
	for tick: int in 30:
		var pressed: int = TickCommand.NORTH if tick == 0 else 0
		var expected: TickResult = _tick(reference, pressed)
		assert_eq(expected.error, "")
		if not expected.error.is_empty():
			return
		if not expected.rng_consumers.is_empty():
			observed_draws = true
			var before: RunSnapshot = run.snapshot()
			run._entities._lifecycle.polygon_counts.fill(2500)
			_assert_failed(_tick(run, pressed))
			var after: RunSnapshot = run.snapshot()
			assert_eq(after.tick_index, before.tick_index)
			assert_eq(after.position_16, before.position_16)
			assert_eq(after.mode, before.mode)
			assert_eq(after.camera.shake_timer, before.camera.shake_timer)
			assert_eq(after.camera.source_world, before.camera.source_world)
			assert_eq(after.animation.cel, before.animation.cel)
			assert_eq(after.rng_state, before.rng_state)
			assert_eq(after.rng_draw_count, before.rng_draw_count)
			run._entities._lifecycle.polygon_counts.fill(1)
		var actual: TickResult = _tick(run, pressed)
		assert_eq(actual.error, "")
		if not actual.error.is_empty():
			return
		assert_eq(actual.rng_consumers, expected.rng_consumers)
		assert_eq(actual.final_snapshot.rng_state, expected.final_snapshot.rng_state)
		assert_eq(actual.final_snapshot.camera.source_world, expected.final_snapshot.camera.source_world)
		assert_eq(actual.final_snapshot.position_16, expected.final_snapshot.position_16)
		assert_eq(actual.final_snapshot.animation.cel, expected.final_snapshot.animation.cel)
		assert_eq(actual.final_snapshot.entities.lifecycle_events, expected.final_snapshot.entities.lifecycle_events)
	assert_true(observed_draws, "The injected late failure must discard real RNG consumption")
