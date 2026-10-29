extends GutTest
## Data-free sandbox spawning: availability, path presets, rebuild validity and run starts.

const DATA_FREE: PackedStringArray = ["FOR_SWAYING_BRANCH", "STATIC", "DYNAMIC", "MOVING_TONGUEABLE", "MOVING"]

var _sandbox: SandboxLevel
var _spawner: SandboxSpawner

func before_each() -> void:
	_sandbox = SandboxLevel.build()
	_spawner = SandboxSpawner.new(_sandbox)

func _assert_valid() -> void:
	var collision: EntityCollisionDefinition = _spawner.entity_collision()
	assert_eq(collision.validate(), "")
	assert_eq(collision.entities.size(), _spawner.placements.size())
	assert_eq(collision.contacts.size(), _spawner.placements.size())
	assert_eq(collision.environment.checkpoint_positions.size(), 5)
	for index: int in collision.entities.size():
		assert_eq(collision.entities[index].entity_index, index)
		assert_eq(collision.contacts[index].entity_index, index)
		assert_eq(collision.entities[index].unique_id, _spawner.placements[index].unique_id)
	assert_eq(EntityRun.create(collision.entities).error, "")

func test_catalog_names_and_data_free_availability() -> void:
	assert_eq(SandboxSpawner.kind_names().size(), EntityBehaviorCatalog.KINDS.size())
	assert_eq(_spawner.available_names(), DATA_FREE)
	for entity_name: String in SandboxSpawner.kind_names():
		var availability: SandboxSpawner.Availability = _spawner.availability(entity_name)
		assert_eq(availability.entity_name, entity_name)
		assert_eq(availability.available, DATA_FREE.has(entity_name), entity_name)
		assert_eq(availability.reason.is_empty(), availability.available, entity_name)

func test_unavailable_kinds_report_reasons_without_spawning() -> void:
	for entity_name: String in ["SUB_TURTLE", "VOL_FALLING_PLATFORM", "VOL_COLOUR_SWITCH", "CHECKPOINT"]:
		var result: SandboxSpawner.Result = _spawner.add(entity_name, Vector2i(10, 10))
		assert_string_contains(result.error, "player data", entity_name)
		assert_null(result.placement, entity_name)
	assert_string_contains(_spawner.add("ORG_BABY_FROG", Vector2i(10, 10)).error, "parent log")
	assert_string_contains(_spawner.add("GEN_TOP_LEFT", Vector2i(10, 10)).error, "not spawnable")
	assert_string_contains(_spawner.add("NOT_A_KIND", Vector2i(10, 10)).error, "Unknown")
	assert_string_contains(_spawner.add("STATIC", Vector2i(-1, 0)).error, "outside")
	assert_string_contains(_spawner.add("STATIC", Vector2i(3, 3), SandboxSpawner.Preset.LINE).error, "fixed matrix")
	assert_eq(_spawner.placements.size(), 0)
	_assert_valid()

func test_static_entity_sits_on_the_cell_centre_with_a_matching_contact() -> void:
	var result: SandboxSpawner.Result = _spawner.add("STATIC", Vector2i(5, 4))
	assert_eq(result.error, "")
	var entity: EntityDefinition = result.placement.entity
	assert_eq([entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]], [-4096 + 5 * 256 + 128, 0, -4096 + 4 * 256 + 128])
	assert_null(entity.path_definition)
	assert_eq(result.placement.contact.grid_flags, PackedInt32Array([GridSquareFlags.USABLE | GridSquareFlags.SAFE]))
	assert_eq(result.placement.level_code, "")
	assert_eq(result.placement.theme, -1)
	_assert_valid()

func test_path_presets_build_lines_loops_and_speeds() -> void:
	var still: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(4, 4))
	var line: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(4, 6), SandboxSpawner.Preset.LINE)
	var loop: SandboxSpawner.Result = _spawner.add("MOVING_TONGUEABLE", Vector2i(4, 8), SandboxSpawner.Preset.LOOP)
	var fast: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(4, 10), SandboxSpawner.Preset.SPEED)
	var custom: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(4, 12), SandboxSpawner.Preset.LINE, 40)
	for result: SandboxSpawner.Result in [still, line, loop, fast, custom]:
		assert_eq(result.error, "")
	assert_eq(still.placement.entity.path_start.speed, 0)
	assert_eq(line.placement.entity.path_start.speed, SandboxSpawner.DEFAULT_SPEED)
	assert_eq(fast.placement.entity.path_start.speed, SandboxSpawner.DEFAULT_SPEED * SandboxSpawner.SPEED_MULTIPLIER)
	assert_eq(custom.placement.entity.path_start.speed, 40)
	var segments: Array[PathSegmentDefinition] = line.placement.entity.path_definition.segments
	assert_eq(segments.size(), 1)
	assert_eq(segments[0].length, SandboxSpawner.LINE_CELLS * 256)
	assert_eq(segments[0].start, _spawner.cell_centre(Vector2i(4, 6)))
	var loop_segments: Array[PathSegmentDefinition] = loop.placement.entity.path_definition.segments
	assert_eq(loop_segments.size(), 4)
	assert_eq(loop_segments[3].end, loop_segments[0].start)
	for segment: PathSegmentDefinition in loop_segments:
		assert_eq(segment.length, SandboxSpawner.LOOP_CELLS * 256)
	assert_true(bool(loop.placement.entity.path_start.flags & PathStart.REPEAT))
	_assert_valid()

func test_paths_near_the_edge_turn_back_inside_the_grid() -> void:
	var line: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(30, 29), SandboxSpawner.Preset.LINE)
	var loop: SandboxSpawner.Result = _spawner.add("MOVING", Vector2i(30, 29), SandboxSpawner.Preset.LOOP)
	assert_eq(line.error, "")
	assert_eq(loop.error, "")
	for result: SandboxSpawner.Result in [line, loop]:
		for segment: PathSegmentDefinition in result.placement.entity.path_definition.segments:
			for point: Vector3i in [segment.start, segment.end]:
				assert_ne(GridQueries.info_at(_sandbox.level.grid, point.x, point.z), null, str(point))

func test_remove_remove_at_remove_last_and_clear_keep_the_table_valid() -> void:
	for x: int in 4:
		assert_eq(_spawner.add("STATIC", Vector2i(3 + x, 20)).error, "")
	assert_eq(_spawner.add("MOVING", Vector2i(3, 20), SandboxSpawner.Preset.LINE).error, "")
	var ids: PackedInt32Array = []
	for placement: SandboxSpawner.Placement in _spawner.placements:
		ids.append(placement.unique_id)
	assert_eq(ids, PackedInt32Array([1, 2, 3, 4, 5]))
	_assert_valid()
	assert_true(_spawner.remove(2))
	assert_false(_spawner.remove(2))
	_assert_valid()
	assert_eq(_spawner.remove_at(Vector2i(3, 20)), 2)
	assert_eq(_spawner.remove_at(Vector2i(3, 20)), 0)
	_assert_valid()
	assert_true(_spawner.remove_last())
	_assert_valid()
	assert_eq(_spawner.placements.size(), 1)
	assert_eq(_spawner.placements[0].unique_id, 3)
	assert_eq(_spawner.add("DYNAMIC", Vector2i(9, 9)).placement.unique_id, 6)
	_spawner.clear()
	assert_false(_spawner.remove_last())
	_assert_valid()

func test_level_definition_is_fresh_and_leaves_the_arena_unchanged() -> void:
	assert_eq(_spawner.add("STATIC", Vector2i(8, 8)).error, "")
	var level: LevelDefinition = _spawner.level_definition()
	assert_ne(level, _sandbox.level)
	assert_eq(level.entity_collision.entities.size(), 1)
	assert_eq(_sandbox.level.entity_collision.entities.size(), 0)
	assert_eq(level.grid, _sandbox.level.grid)
	assert_eq(level.spawn_cell, _sandbox.level.spawn_cell)
	assert_eq(level.level_time, _sandbox.level.level_time)
	assert_eq(level.rewards.size(), _sandbox.level.rewards.size())
	assert_eq(level.frog_action_lengths, _sandbox.level.frog_action_lengths)
	assert_eq(level.camera_zones.size(), 1)
	level.camera_zones.clear()
	assert_eq(_sandbox.level.camera_zones.size(), 1)
	assert_false(level.cave_light)

func test_run_start_keeps_the_frog_cell_and_direction() -> void:
	var start: RunStart = SandboxSpawner.run_start(Vector2i(7, 3), 2)
	assert_eq(start.start_mode, RunStart.Mode.COMPONENT)
	assert_eq(start.spawn_cell, Vector2i(7, 3))
	assert_eq(start.spawn_direction, 2)
	var run: GameplayRun = GameplayRun.create(_spawner.level_definition(), start)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var kept: RunStart = SandboxSpawner.run_start_from(run.snapshot())
	assert_eq(kept.spawn_cell, Vector2i(7, 3))
	assert_eq(kept.spawn_direction, run.snapshot().frog.direction)
	assert_eq(_spawner.add("STATIC", Vector2i(12, 3)).error, "")
	var restarted: GameplayRun = GameplayRun.create(_spawner.level_definition(), kept)
	assert_eq(restarted.error, "")
	if restarted.error.is_empty():
		assert_eq(restarted.snapshot().frog.cell, Vector2i(7, 3))

func test_spawned_platform_carries_the_frog_over_water() -> void:
	var water: Rect2i = _sandbox.zone_named(&"water").cells
	var cell := Vector2i(water.position.x + 1, water.position.y)
	assert_eq(_spawner.add("MOVING", cell).error, "")
	var run: GameplayRun = GameplayRun.create(_spawner.level_definition(), SandboxSpawner.run_start(cell - Vector2i(0, 1), 0))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var mounted: bool = false
	for tick: int in 30:
		var result: TickResult = _tick(run, TickCommand.NORTH if tick == 0 else 0)
		assert_eq(result.error, "", str(tick))
		if not result.error.is_empty():
			return
		assert_ne(result.final_snapshot.frog.death_equate, FrogAnimationCatalog.DROWN, str(tick))
		mounted = mounted or result.final_snapshot.attachment.current_entity_index == 0
	assert_true(mounted)

func _tick(run: GameplayRun, pressed: int = 0) -> TickResult:
	var command := TickCommand.new()
	command.tick_index = run.snapshot().tick_index
	command.pressed_mask = pressed
	command.held_mask = pressed
	return run.step(command)
