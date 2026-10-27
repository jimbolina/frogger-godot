extends GutTest
## Independent records must survive the presentation's stepping and render schedules unchanged.

var _viewer: TerrainViewer

func before_each() -> void:
	_viewer = TerrainViewer.new()
	_viewer.auto_open = false
	_viewer.record_trace = true
	add_child_autofree(_viewer)
	_viewer.set_process(false)

func _expected(index: int) -> PackedStringArray:
	var rows := PackedStringArray([TerrainTrace.HEADER])
	for line: String in FileAccess.get_file_as_string("res://tests/golden/synthetic/terrain_components.csv").strip_edges().split("\n"):
		if line.begins_with(str(index) + ","):
			rows.append(line.strip_edges())
	return rows

func test_rendered_step_driver_matches_all_component_facts() -> void:
	for identifier: String in ["normal", "blocked", "buffer"]:
		var scenario: TerrainScenario = TerrainScenario.builtin(identifier)
		assert_eq(_viewer.open_scenario(scenario), "")
		for tick: int in scenario.tick_limit:
			assert_eq(_viewer.step_scenario().error, "")
			_viewer.smoothing = true
			_viewer.draw_state(0.35)
			_viewer.draw_state(0.85)
		assert_eq(_viewer.trace.rows, _expected(scenario.scenario_index))

func test_render_schedules_pause_and_reset_do_not_change_executed_ticks() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("buffer")
	for delta: float in [1.0 / 240.0, 1.0 / 200.0, 1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 0.2]:
		assert_eq(_viewer.open_scenario(scenario), "")
		_viewer.smoothing = true
		_viewer.playing = true
		for frame: int in 1000:
			if _viewer.run.snapshot().tick_index == scenario.tick_limit:
				break
			_viewer._process(delta)
		assert_eq(_viewer.run.snapshot().tick_index, scenario.tick_limit)
		assert_eq(_viewer.trace.rows, _expected(2))
		_viewer.playing = false
		_viewer._process(10.0)
		assert_eq(_viewer.run.snapshot().tick_index, scenario.tick_limit)
		assert_eq(_viewer.reset_scenario(), "")
		assert_eq(_viewer.run.snapshot().tick_index, 0)
		assert_eq(_viewer.trace.rows.size(), 1)

func test_scenario_commands_are_detached_and_invalid_tick_leaves_trace_unchanged() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_viewer.open_scenario(scenario), "")
	var command: TickCommand = scenario.command_at(0)
	command.pressed_mask = 0
	assert_eq(scenario.command_at(0).pressed_mask, TickCommand.NORTH)
	command.tick_index = 2
	assert_false(_viewer.step_command(command).error.is_empty())
	assert_eq(_viewer.run.snapshot().tick_index, 0)
	assert_eq(_viewer.trace.rows.size(), 1)

func test_live_pressed_edges_are_derived_at_the_tick_boundary() -> void:
	assert_eq(_viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_UP
	key.pressed = true
	_viewer._unhandled_key_input(key)
	assert_eq(_viewer.step_live().error, "")
	assert_eq(_viewer.step_live().error, "")
	assert_eq(_viewer.run.snapshot().frog.buffered_keys, 0, "Held input is not another pressed edge")
	key.physical_keycode = KEY_RIGHT
	_viewer._unhandled_key_input(key)
	key.pressed = false
	_viewer._unhandled_key_input(key)
	assert_eq(_viewer.step_live().error, "")
	assert_eq(_viewer.run.snapshot().frog.buffered_keys, 0, "A released transient key is absent at the source sampling boundary")
	key.pressed = true
	_viewer._unhandled_key_input(key)
	assert_eq(_viewer.step_live().error, "")
	assert_eq(_viewer.run.snapshot().frog.buffered_keys, 1)

func test_direct_map_controls_idle_and_hop_beyond_the_replay_limit() -> void:
	_viewer.configure_input(PackedStringArray(["--level=ORG1"]))
	assert_false(_viewer.replay_commands)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_viewer.open_scenario(scenario), "")
	var start: Vector3i = _viewer.run.snapshot().frog.position_16
	_press(KEY_SPACE)
	for tick: int in 24:
		_viewer._process(1.0 / 30.0)
	assert_eq(_viewer.run.snapshot().tick_index, 24)
	assert_eq(_viewer.run.snapshot().frog.position_16, start, "No fixture hop leaks into live input")
	assert_true(_viewer.playing)
	assert_string_contains(_viewer._label.text, "LIVE | running")
	_press(KEY_UP)
	_viewer._process(1.0 / 30.0)
	_press(KEY_UP, false)
	for tick: int in 9:
		_viewer._process(1.0 / 30.0)
	assert_ne(_viewer.run.snapshot().frog.position_16, start)
	_press(KEY_DOWN)
	_viewer._process(1.0 / 30.0)
	_press(KEY_DOWN, false)
	for tick: int in 9:
		_viewer._process(1.0 / 30.0)
	assert_eq(_viewer.run.snapshot().frog.position_16, start, "A later live hop still responds")
	_press(KEY_R)
	assert_false(_viewer.replay_commands, "Reset retains live control selection")
	assert_false(_viewer.playing)
	assert_string_contains(_viewer._label.text, "LIVE | paused")

func test_explicit_fixtures_keep_replay_and_report_its_end() -> void:
	for arguments: PackedStringArray in [PackedStringArray(),
		PackedStringArray(["--level=ORG1", "--run-scenario"]),
		PackedStringArray(["--level=ORG1", "--scenario=normal"]),
		PackedStringArray(["--level=ORG1", "--scenario-file=fixture.json"])]:
		_viewer.configure_input(arguments)
		assert_true(_viewer.replay_commands)
	assert_eq(_viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	_press(KEY_SPACE)
	for tick: int in 17:
		_viewer._process(1.0 / 30.0)
	assert_eq(_viewer.run.snapshot().tick_index, 16)
	assert_false(_viewer.playing)
	assert_string_contains(_viewer._label.text, "replay finished: Tab selects live input")
	_press(KEY_TAB)
	_press(KEY_SPACE)
	_viewer._process(1.0 / 30.0)
	assert_eq(_viewer.run.snapshot().tick_index, 17)
	assert_string_contains(_viewer._label.text, "LIVE | running")

func _press(code: Key, pressed: bool = true) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = pressed
	_viewer._unhandled_key_input(key)

func test_authored_json_inputs_and_command_line_overrides_are_detached() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var values: Dictionary = {"level": {"theme": 4, "theme_name": "JUN", "collision_enabled": true,
		"collision_bounds": [-500, -500, 1000, 1000], "camera": {"source_offset": [0, -700, -400]}},
		"start": {"seed": 7, "powerup_flags": 2, "quick_jump_timer": 19, "controller_directions": [1, 2, 3, 0]}}
	assert_eq(TerrainScenarioJson.apply(scenario, values), "")
	assert_eq(scenario.level.camera.source_offset, Vector3i(0, -700, -400))
	assert_eq(scenario.level.theme_name, &"JUN")
	assert_eq(scenario.initial.controller_directions, PackedInt32Array([1, 2, 3, 0]))
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--seed=11", "--tick-limit=24"])), "")
	assert_eq(scenario.initial.seed, 11)
	assert_eq(scenario.tick_limit, 24)
	assert_false(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--tick-limit=-1"])).is_empty())
	assert_false(TerrainScenarioJson.apply(scenario, {"start": {"seed": 1.5}}).is_empty())
	assert_false(TerrainScenarioJson.apply(scenario, {"grid": {"dimensions": [4], "base": [0, 0]}}).is_empty())

func test_detaching_data_clears_retail_scene_and_run_but_keeps_synthetic_inputs() -> void:
	var synthetic: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_viewer.open_scenario(synthetic), "")
	assert_eq(_viewer.open_data(null), "")
	assert_not_null(_viewer.run)
	assert_same(_viewer.scenario, synthetic)
	synthetic.map_scene = MapSceneData.new()
	synthetic.level_code = "ORG3"
	assert_eq(_viewer.open_data(null), "")
	assert_null(_viewer.run)
	assert_null(synthetic.map_scene)
	assert_eq(_viewer._ground.get_child_count(), 0)

func test_reset_releases_old_generated_mesh_resources() -> void:
	assert_eq(_viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	var face: MeshInstance3D = _viewer._ground.get_child(0) as MeshInstance3D
	var old_mesh: WeakRef = weakref(face.mesh)
	face = null
	for repeat: int in 6:
		assert_eq(_viewer.reset_scenario(), "")
		assert_eq(_viewer._ground.get_child_count(), 16)
	await get_tree().process_frame
	var released: Object = old_mesh.get_ref()
	assert_null(released, "Replaced generated meshes are released after queued nodes free")

func test_resize_updates_terrain_and_every_prepared_frog_texture_material() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	add_child_autofree(viewport)
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	viewport.add_child(viewer)
	viewer.set_process(false)
	assert_eq(viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	var face: MeshInstance3D = viewer._ground.get_child(0) as MeshInstance3D
	var terrain: ShaderMaterial = face.material_override as ShaderMaterial
	var original: ShaderMaterial = terrain.duplicate() as ShaderMaterial
	var frame: ShaderMaterial = terrain.duplicate() as ShaderMaterial
	var track := ModelMesh.TextureTrack.new()
	track.original = original
	track.frames = [frame]
	viewer.frog_assets = TerrainFrogAssets.new()
	viewer.frog_assets.mesh = ModelMesh.new()
	viewer.frog_assets.mesh.texture_tracks = [[track]]
	viewer._projection_size = Vector2i.ZERO
	viewer.draw_state(1.0)
	var initial_scale: Vector2 = terrain.get_shader_parameter("projection_scale")
	assert_eq(initial_scale, Vector2(1, 0.9375))
	viewport.size = Vector2i(800, 480)
	viewer.draw_state(1.0)
	for material: ShaderMaterial in [terrain, original, frame]:
		var scale: Vector2 = material.get_shader_parameter("projection_scale")
		assert_eq(scale, Vector2(1, 0.75))
	assert_almost_eq(viewer._camera.fov, GameplayProjection.vertical_fov_degrees(Vector2i(800, 480)), 0.00001)

func test_scenario_tongue_input_is_detached_and_unknown_mask_is_rejected() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_object({"builtin": "normal", "tick_limit": 2,
		"commands": [{"tick": 0, "pressed": TickCommand.TONGUE, "held": TickCommand.TONGUE}]})
	assert_eq(scenario.error, "")
	var command: TickCommand = scenario.command_at(0)
	assert_eq(command.pressed_mask, TickCommand.TONGUE)
	command.pressed_mask = 0
	command.held_mask = 0
	assert_eq(scenario.command_at(0).pressed_mask, TickCommand.TONGUE)
	assert_eq(scenario.command_at(0).held_mask, TickCommand.TONGUE)
	var rejected: TerrainScenario = TerrainScenario.from_object({"builtin": "normal", "tick_limit": 2,
		"commands": [{"tick": 0, "pressed": 256, "held": 0}]})
	assert_string_contains(rejected.error, "0..255")

func test_json_start_completion_roundtrip_uint32_inputs_and_atomic_refusal() -> void:
	var authored: Dictionary = {"tick_limit": 4, "start": {"seed": 4294967295, "start_mode": 2},
		"level": {"spawn_cell": [0, 0]},
		"grid": {"dimensions": [1, 1], "base": [-128, -128], "stacks": [[0, 1]],
			"squares": [{"flags": 2147483651, "vertices": [[-128, 0, 128], [128, 0, 128], [-128, 0, -128], [128, 0, -128]]}]},
		"commands": [{"tick": 0, "pressed": 0, "held": 0, "start_timer_context": 37, "start_sequence_complete": true}]}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(authored))
	var scenario: TerrainScenario = TerrainScenario.from_object(decoded)
	assert_eq(scenario.error, "")
	assert_eq(scenario.initial.seed, 4294967295)
	assert_eq(scenario.level.grid.squares[0].flags, 2147483651)
	var detached: TickCommand = scenario.command_at(0)
	detached.start_timer_context = 0
	detached.start_sequence_complete = false
	assert_eq(scenario.command_at(0).start_timer_context, 37)
	assert_true(scenario.command_at(0).start_sequence_complete)
	assert_eq(_viewer.open_scenario(scenario), "")
	var result: TickResult = _viewer.step_scenario()
	assert_eq(result.error, "")
	assert_eq(result.control_snapshot.frog.start_timer, 37)
	assert_eq(result.control_snapshot.frog.mode, 3, "Explicit HUD completion selects source WAIT")
	assert_eq(_viewer.run.snapshot().tick_index, 1)
	var row: Dictionary = JSON.parse_string(_viewer.trace.full_rows[1])
	var command: Dictionary = row.command
	var timer: float = command.start_timer_context
	assert_eq(timer, 37.0)
	var completed: bool = command.start_sequence_complete
	assert_true(completed)
	assert_eq(command.size(), 5, "Trace includes all five typed command fields")
	var ordinary: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_viewer.open_scenario(ordinary), "")
	var invalid: TickCommand = ordinary.command_at(0)
	invalid.start_sequence_complete = true
	var before: String = JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot()))
	assert_false(_viewer.step_command(invalid).error.is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot())), before)
	assert_eq(_viewer.trace.full_rows.size(), 1)
	assert_false(TerrainScenarioJson.apply(ordinary, {"start": {"seed": 4294967296}}).is_empty())
	assert_false(TerrainScenarioJson.apply(ordinary, {"start": {"seed": -1}}).is_empty())
	assert_false(TerrainScenarioJson.apply(ordinary, {"level": {"spawn_cell": [2147483648, 0]}}).is_empty())

func test_pause_step_reset_and_optional_smoothing_have_no_native_interpolation() -> void:
	assert_eq(_viewer.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)
	assert_eq(_viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	var initial: Vector3 = _viewer._frog.position
	var before: String = JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot()))
	_viewer._process(0.25)
	assert_eq(_viewer._frog.position, initial)
	assert_eq(JSON.stringify(TerrainTrace.facts(_viewer.run.snapshot())), before)
	assert_eq(_viewer.step_scenario().error, "")
	assert_eq(_viewer._frog.position, GameSpace.fixed_position(_viewer._current.frog.position_16) + Vector3(0, 0.12, 0))
	assert_eq(_viewer._frog.get_global_transform_interpolated().origin, _viewer._frog.global_position)
	_viewer.playing = true
	_viewer.smoothing = true
	assert_eq(_viewer.step_scenario().error, "")
	_viewer.draw_state(0.5)
	var midpoint: Vector3 = GameSpace.fixed_position(_viewer._previous.frog.position_16).lerp(GameSpace.fixed_position(_viewer._current.frog.position_16), 0.5) + Vector3(0, 0.12, 0)
	assert_eq(_viewer._frog.position, midpoint)
	assert_ne(_viewer._previous.frog.position_16, _viewer._current.frog.position_16)
	assert_eq(_viewer._frog.get_global_transform_interpolated().origin, _viewer._frog.global_position)
	assert_eq(_viewer.reset_scenario(), "")
	assert_eq(_viewer._frog.position, initial)
	assert_eq(_viewer._frog.get_global_transform_interpolated().origin, _viewer._frog.global_position)

func test_interactive_smoothing_default_capture_override_and_rejection_reset() -> void:
	_viewer.configure_input(PackedStringArray())
	assert_true(_viewer.smoothing)
	_viewer.configure_input(PackedStringArray(["--run-scenario"]))
	assert_false(_viewer.smoothing)
	_viewer.configure_input(PackedStringArray(["--run-scenario", "--smoothing=true"]))
	assert_true(_viewer.smoothing)
	assert_eq(_viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	_viewer.playing = true
	assert_eq(_viewer.step_scenario().error, "")
	_viewer.draw_state(0.5)
	var rejected := TickCommand.new()
	rejected.tick_index = -1
	assert_ne(_viewer.step_command(rejected).error, "")
	assert_false(_viewer.playing)
	_viewer.draw_state(0.0)
	assert_eq(_viewer._frog.position, GameSpace.fixed_position(_viewer._current.frog.position_16) + Vector3(0, 0.12, 0))
