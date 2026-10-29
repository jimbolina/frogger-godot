extends GutTest
## Sandbox arena terrain zones, spawn, camera zone and dedicated-scene opening.

var _sandbox: SandboxLevel

func before_each() -> void:
	_sandbox = SandboxLevel.build()

func _centre(zone_name: StringName) -> Vector2i:
	var zone: SandboxLevel.Zone = _sandbox.zone_named(zone_name)
	return zone.cells.position + zone.cells.size / 2

func test_every_labelled_zone_has_its_terrain_flags() -> void:
	var expected: Dictionary[StringName, int] = {
		&"plain": GridSquareFlags.USABLE | GridSquareFlags.SAFE,
		&"water": GridSquareFlags.USABLE | GridSquareFlags.WATER,
		&"ice": GridSquareFlags.USABLE | GridSquareFlags.SLIPPY,
		&"freeform_ice": GridSquareFlags.USABLE | GridSquareFlags.FREEFORM_SLIPPY,
		&"bouncy": GridSquareFlags.USABLE | GridSquareFlags.BOUNCY,
		&"deadly": GridSquareFlags.USABLE | GridSquareFlags.DEADLY,
		&"soft": GridSquareFlags.USABLE | GridSquareFlags.SAFE | GridSquareFlags.SOFT,
		&"checkpoint": GridSquareFlags.USABLE | GridSquareFlags.SAFE | GridSquareFlags.CHECKPOINT,
		&"cliff_steps": GridSquareFlags.USABLE | GridSquareFlags.SAFE,
		&"cliff": GridSquareFlags.USABLE | GridSquareFlags.CLIFF,
		&"camera": GridSquareFlags.USABLE | GridSquareFlags.SAFE,
	}
	assert_eq(_sandbox.zones.size(), expected.size())
	for zone: SandboxLevel.Zone in _sandbox.zones:
		assert_true(expected.has(zone.name), str(zone.name))
		var flags: int = expected.get(zone.name, -1)
		assert_eq(zone.flags, flags, str(zone.name))
		if zone.name == &"plain":
			continue
		for z: int in range(zone.cells.position.y, zone.cells.end.y):
			for x: int in range(zone.cells.position.x, zone.cells.end.x):
				assert_eq(_sandbox.flags_at(Vector2i(x, z)), zone.flags, "%s (%d,%d)" % [zone.name, x, z])
	assert_eq(_sandbox.flags_at(Vector2i(0, 0)), GridSquareFlags.USABLE | GridSquareFlags.SAFE)
	assert_eq(_sandbox.flags_at(Vector2i(-1, 0)), -1)
	assert_eq(_sandbox.flags_at(SandboxLevel.DIMENSIONS), -1)

func test_hazard_zones_keep_a_plain_border_inside_the_grid() -> void:
	for zone: SandboxLevel.Zone in _sandbox.zones:
		if zone.name == &"plain":
			continue
		assert_true(Rect2i(Vector2i(2, 2), SandboxLevel.DIMENSIONS - Vector2i(4, 4)).encloses(zone.cells), str(zone.name))

func test_grid_matches_source_storage_rules() -> void:
	var grid: GridDefinition = _sandbox.level.grid
	assert_eq(grid.dimensions, SandboxLevel.DIMENSIONS)
	assert_eq(grid.stacks.size(), SandboxLevel.DIMENSIONS.x * SandboxLevel.DIMENSIONS.y)
	assert_eq(grid.squares.size(), grid.stacks.size())
	var info: GridSurfaceInfo = GridQueries.info_at(grid, grid.base.x + 128, grid.base.y + 128)
	assert_not_null(info)
	if info != null:
		assert_eq(info.height, 0)
	assert_eq(GridQueries.world_to_cell(grid, grid.base.x + 300, grid.base.y + 600), Vector2i(1, 2))

func test_spawn_is_usable_safe_plain_ground_with_safe_neighbours() -> void:
	var level: LevelDefinition = _sandbox.level
	assert_eq(level.spawn_cell, SandboxLevel.SPAWN_CELL)
	assert_eq(level.spawn_direction, SandboxLevel.SPAWN_DIRECTION)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var flags: int = _sandbox.flags_at(level.spawn_cell + offset)
		assert_eq(flags & (GridSquareFlags.USABLE | GridSquareFlags.SAFE), GridSquareFlags.USABLE | GridSquareFlags.SAFE, str(offset))
		assert_eq(flags & (GridSquareFlags.DEADLY | GridSquareFlags.WATER | GridSquareFlags.POPDEATH | GridSquareFlags.CLIFF), 0, str(offset))
		assert_eq(_sandbox.zone_at(level.spawn_cell + offset).name, &"plain")
	assert_eq(_sandbox.edge_heights(level.spawn_cell), Vector2i.ZERO)

func test_cliff_steps_climb_within_a_hop_and_cliff_rolls_north() -> void:
	var steps: SandboxLevel.Zone = _sandbox.zone_named(&"cliff_steps")
	var previous: int = 0
	for z: int in range(steps.cells.position.y, steps.cells.end.y):
		var height: int = GridQueries.square_height(_square(Vector2i(steps.cells.position.x, z)))
		assert_lt(height, previous)
		assert_lte(previous - height, 200)
		previous = height
	var cliff: SandboxLevel.Zone = _sandbox.zone_named(&"cliff")
	for z: int in range(cliff.cells.position.y, cliff.cells.end.y):
		var normal: Vector3i = GridQueries.average_normal(_square(Vector2i(cliff.cells.position.x, z)))
		assert_gt(normal.z, 256, "row %d rolls toward +z" % z)
		assert_lt(absi(normal.x), absi(normal.z))
	assert_eq(_sandbox.edge_heights(Vector2i(cliff.cells.position.x, cliff.cells.end.y - 1)).x, 0)
	assert_eq(_sandbox.edge_heights(Vector2i(cliff.cells.position.x, cliff.cells.position.y)).y, previous)

func test_camera_zone_rewards_timer_and_empty_entities_are_valid() -> void:
	var level: LevelDefinition = _sandbox.level
	assert_eq(level.camera_zones.size(), 1)
	var zone: ZoneDefinition = level.camera_zones[0]
	assert_eq(zone.validate_camera(), "")
	assert_eq(ZoneQueries.first_camera_match(level.camera_zones, _centre(&"camera")), SandboxLevel.CAMERA_ZONE_INDEX)
	assert_eq(ZoneQueries.first_camera_match(level.camera_zones, level.spawn_cell), -1)
	var camera_cells: Rect2i = _sandbox.zone_named(&"camera").cells
	assert_eq(ZoneQueries.first_camera_match(level.camera_zones, camera_cells.end - Vector2i.ONE), SandboxLevel.CAMERA_ZONE_INDEX)
	assert_eq(ZoneQueries.first_camera_match(level.camera_zones, camera_cells.end), -1)
	assert_eq(level.rewards.size(), 24)
	assert_eq(level.level_time, SandboxLevel.LEVEL_TIME)
	assert_true(level.flow_enabled)
	assert_true(level.collision_enabled)
	assert_eq(level.frog_action_lengths.size(), FrogAnimationCatalog.ACTION_NAMES.size())
	assert_not_null(level.entity_collision)
	assert_eq(level.entity_collision.entities.size(), 0)
	assert_eq(level.entity_collision.contacts.size(), 0)
	assert_eq(level.entity_collision.validate(), "")

func test_builds_are_independent() -> void:
	var other: SandboxLevel = SandboxLevel.build()
	other.level.grid.squares[0].flags = 0
	assert_eq(_sandbox.flags_at(Vector2i.ZERO), GridSquareFlags.USABLE | GridSquareFlags.SAFE)

func test_run_starts_and_idles_on_the_spawn_cell() -> void:
	var run: GameplayRun = GameplayRun.create(_sandbox.level, SandboxLevel.run_start())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for tick: int in 30:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", str(tick))
		if not result.error.is_empty():
			return
	assert_eq(run.snapshot().frog.cell, SandboxLevel.SPAWN_CELL)
	assert_ne(run.snapshot().frog.mode, FrogMode.DYING)

func test_hopping_into_the_water_zone_drowns() -> void:
	var water: SandboxLevel.Zone = _sandbox.zone_named(&"water")
	var start := RunStart.new()
	start.spawn_cell = Vector2i(water.cells.position.x, water.cells.position.y - 1)
	start.spawn_direction = 0
	var run: GameplayRun = GameplayRun.create(_sandbox.level, start)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var drowned: bool = false
	for tick: int in 30:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
		command.held_mask = command.pressed_mask
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", str(tick))
		if not result.error.is_empty():
			return
		drowned = drowned or result.final_snapshot.frog.death_equate == FrogAnimationCatalog.DROWN
	assert_true(drowned)

func test_dedicated_screen_opens_and_steps_the_sandbox() -> void:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	assert_eq(screen.open_run(_sandbox.level, SandboxLevel.run_start()), "")
	assert_true(screen.playing)
	assert_eq(screen.last_error, "")
	for tick: int in 10:
		var command := TickCommand.new()
		command.tick_index = tick
		var result: TickResult = screen.step_command(command)
		assert_eq(result.error, "", str(tick))
		screen.draw_state(0.5)
	assert_eq(screen.run.snapshot().tick_index, 10)
	assert_eq(screen.run.snapshot().frog.cell, SandboxLevel.SPAWN_CELL)

func _square(cell: Vector2i) -> GridSquareDefinition:
	var grid: GridDefinition = _sandbox.level.grid
	return grid.squares[grid.stack_at(cell).first_square_index]
