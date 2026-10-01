extends GutTest
## The model viewer, driven with made-up models. Needs no game files.

const VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"

var _viewer: ModelViewer


func before_each() -> void:
	var scene: PackedScene = load(VIEWER_SCENE)
	_viewer = scene.instantiate() as ModelViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)


func test_shows_a_model_from_bytes() -> void:
	var parts: Array[SyntheticMof.Part] = [SyntheticMof.square(MofPolygonType.F4), SyntheticMof.square(MofPolygonType.G4)]
	assert_eq(_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static(parts)), 4)
	assert_eq(_viewer.part_node_count(), 2)
	assert_eq(_viewer.visible_part_count(), 2)
	assert_string_contains(_viewer.facts_text(), "2 parts")
	assert_string_contains(_viewer.facts_text(), "F4 1, G4 1")


func test_a_placeholder_shows_nothing() -> void:
	assert_eq(_viewer.load_model_bytes("NULL", SyntheticMof.build_dummy()), 0)
	assert_eq(_viewer.part_node_count(), 0)


func test_bad_bytes_are_refused() -> void:
	assert_eq(_viewer.load_model_bytes("BAD.XMR", "not a model at all".to_ascii_buffer()), -1)
	assert_eq(_viewer.part_node_count(), 0)


func test_an_animated_file_shows_its_first_model() -> void:
	var inside: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)])
	assert_eq(_viewer.load_model_bytes("TEST.XAR", SyntheticMof.build_animated([inside, inside])), 2)
	assert_eq(_viewer.current_model.static_models.size(), 2)


func test_without_game_data_nothing_is_listed() -> void:
	assert_eq(_viewer.wad_names().size(), 0)
	assert_eq(_viewer.load_wad_model("THEME_GEN_HI.WAD", 0), -1)
	assert_eq(_viewer.load_model_by_name("GEN_FROG.XAR"), -1)


func test_animation_controls_pause_seek_step_restart_and_preserve_mesh() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.F4)
	part.poses.append(part.poses[0].duplicate())
	part.flipbook_actions = 1
	_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([part]))
	assert_true(_viewer.select_action(0))
	_viewer.set_playing(true)
	assert_true(_viewer.playing)
	var mesh: ModelMesh = _viewer.current_mesh
	_viewer.step_animation()
	assert_false(_viewer.playing)
	assert_eq(_viewer.player.frame, 1)
	assert_true(_viewer.seek_tick(0))
	assert_eq(_viewer.player.frame, 0)
	_viewer.restart_animation()
	assert_eq(_viewer.player.tick, 0)
	assert_same(_viewer.current_mesh, mesh)
	assert_false(_viewer.animated_instance.smoothing_enabled)


func test_render_options_preserve_texture_phase_and_player_settings() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	part.animated_polygons = PackedInt32Array([0])
	part.animation_images = PackedInt32Array([7, 8])
	part.animation_durations = PackedInt32Array([2, 3])
	assert_eq(_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([part])), 2)
	_viewer.set_playing(false)
	var original_player: ModelAnimationPlayer = _viewer.player
	for _tick: int in 3:
		original_player.advance_tick()
	original_player.texture_animation_enabled = false
	original_player.update_period = 3
	original_player.end_mode = ModelAnimationPlayer.EndMode.HIDE
	var tick: int = original_player.tick
	_viewer._rebuild()
	assert_same(_viewer.player, original_player)
	assert_eq(_viewer.player.tick, tick)
	assert_eq(_viewer.player.update_period, 3)
	assert_eq(_viewer.player.end_mode, ModelAnimationPlayer.EndMode.HIDE)
	assert_false(_viewer.player.texture_animation_enabled)
	original_player.texture_animation_enabled = true
	var entry: int = original_player.sample_pose().texture_entries[0][0]
	assert_eq(entry, 1, "frozen phase resumes after the render resources change")


func test_capture_folder_must_stay_outside_the_repository() -> void:
	assert_false(ModelViewer._external_capture_folder(ProjectSettings.globalize_path("res://screenshots")))
	assert_false(ModelViewer._external_capture_folder(ProjectSettings.globalize_path("res://screenshots/../capture")))
	assert_false(ModelViewer._external_capture_folder("screenshots"))
	assert_true(ModelViewer._external_capture_folder(OS.get_environment("TEMP")))


func test_replacement_with_null_or_invalid_data_clears_model_selections_and_caches() -> void:
	for invalid: GameData in [null, GameData.new()]:
		_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)]))
		_viewer._banks[1] = VloFile.new()
		_viewer._current_wad = 12
		_viewer._actions.add_item("Old action")
		if invalid != null:
			invalid.error = "Invalid tables"
		_viewer.open_data(invalid)
		assert_null(_viewer.current_model)
		assert_null(_viewer.current_mesh)
		assert_null(_viewer.player)
		assert_null(_viewer.animated_instance)
		assert_null(_viewer._library)
		assert_null(_viewer._preferred)
		assert_eq(_viewer._banks.size(), 0)
		assert_eq(_viewer._current_wad, -1)
		assert_eq(_viewer._actions.item_count, 0)
		assert_eq(_viewer.part_node_count(), 0)
		assert_eq(_viewer.wad_names().size(), 0)
		assert_eq(_viewer.facts_text(), "")


func test_detached_viewer_releases_model_resources_and_caches() -> void:
	_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)]))
	_viewer._banks[1] = VloFile.new()
	var old_mesh: WeakRef = weakref(_viewer.current_mesh)
	var old_bank: WeakRef = weakref(_viewer._banks[1])
	remove_child(_viewer)
	await get_tree().process_frame
	var released_mesh: ModelMesh = old_mesh.get_ref()
	var released_bank: VloFile = old_bank.get_ref()
	assert_null(released_mesh)
	assert_null(released_bank)
	assert_null(_viewer.current_model)
	assert_null(_viewer.current_mesh)
	assert_null(_viewer.player)
	assert_null(_viewer.animated_instance)
	assert_null(_viewer._library)
	assert_null(_viewer._preferred)
	assert_eq(_viewer._banks.size(), 0)
	assert_eq(_viewer.part_node_count(), 0)


func test_action_changes_and_held_geometry_keep_texture_clocks_independent() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	part.poses.append(part.poses[0].duplicate())
	part.flipbook_actions = 2
	part.animated_polygons = PackedInt32Array([0])
	part.animation_images = PackedInt32Array([7, 8])
	part.animation_durations = PackedInt32Array([2, 3])
	assert_eq(_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([part])), 2)
	_viewer.set_playing(false)
	_viewer.player.advance_tick()
	_viewer.player.advance_tick()
	assert_true(_viewer.select_action(1))
	assert_eq(_viewer.player.tick, 3, "action changes do not restart the independent tick counter")
	var entry: int = _viewer.player.sample_pose().texture_entries[0][0]
	assert_eq(entry, 1, "action changes continue the texture phase instead of resetting it")
	_viewer.player.end_mode = ModelAnimationPlayer.EndMode.HOLD
	_viewer.set_playing(true)
	for _tick: int in 3:
		_viewer._physics_process(1.0 / 30.0)
	assert_true(_viewer.playing, "holding geometry keeps the independent texture clock running")
	assert_true(_viewer.player.completed)
	assert_eq(_viewer.player.frame, 1)
	assert_eq(_viewer.player.tick, 6)


func test_animation_shortcuts_work_while_a_list_has_focus() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.F4)
	part.poses.append(part.poses[0].duplicate())
	part.flipbook_actions = 1
	_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static([part]))
	_viewer._wad_list.grab_focus()
	_send_key(KEY_SPACE)
	assert_false(_viewer.playing)
	_send_key(KEY_PERIOD)
	assert_eq(_viewer.player.tick, 1)
	_send_key(KEY_R)
	assert_eq(_viewer.player.tick, 0)
	_send_key(KEY_I)
	assert_true(_viewer.animated_instance.smoothing_enabled)


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	_viewer.get_viewport().push_input(event)
