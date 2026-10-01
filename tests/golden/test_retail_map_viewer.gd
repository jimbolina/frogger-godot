extends RetailTest
## Real map loading and viewer controls through executable-selected resources.

var _viewer: MapViewer

func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)
	_viewer.open_data(GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")))

func test_representative_maps_load_and_reuse_resources() -> void:
	for code: String in ["SUB1", "ORG1", "CAV1", "SKY1"]:
		assert_true(_viewer.load_level_by_code(code), code)
		assert_gt(_viewer.current_mesh.triangle_count, 0, code)
		assert_eq(_viewer.current_mesh.missing_texture_ids.size(), 0, code)
		var mesh: MapMesh = _viewer.current_mesh
		var instance: MapMesh.Instance = _viewer.map_instance
		_viewer.seek_tick(17)
		_viewer.set_filtering(true)
		_viewer.set_camera_preset("map-slice")
		_viewer.step_animation()
		assert_same(_viewer.current_mesh, mesh, code)
		assert_same(_viewer.map_instance, instance, code)
		assert_eq(_viewer.tick, 18, code)
		assert_lte(instance.visible_group_indices().size(), 128, code)
	assert_true(_viewer.load_level_by_code("SUB1", true))
	assert_true(_viewer.scene_data.low_poly)
	assert_false(_viewer.load_level_by_code("UNKNOWN"))

func test_all_78_detail_switches_release_previous_scene_resources() -> void:
	var switched: int = 0
	for level: int in 60:
		var row: MapBookEntry = _viewer.data.map_book_entry(level)
		if row == null or row.is_dummy() or row.map_id(false) <= 0:
			continue
		for low_poly: bool in [false, true]:
			var previous_mesh: WeakRef
			var previous_instance: WeakRef
			var previous_scene: WeakRef
			if _viewer.current_mesh != null:
				previous_mesh = weakref(_viewer.current_mesh)
				previous_instance = weakref(_viewer.map_instance)
				previous_scene = weakref(_viewer.scene_data)
			assert_true(_viewer.load_level_by_code(FroggerIds.LEVEL_CODES[level], low_poly))
			await get_tree().process_frame
			await get_tree().process_frame
			if previous_mesh != null:
				var old_node: Object = previous_instance.get_ref()
				var old_mesh: Object = previous_mesh.get_ref()
				var old_scene: Object = previous_scene.get_ref()
				assert_null(old_node, "previous node released")
				assert_null(old_mesh, "previous mesh and materials released")
				assert_null(old_scene, "previous decoded map and banks released")
			assert_eq(_viewer._world.get_child_count(), 3, "only camera, environment and active map remain")
			switched += 1
	assert_eq(switched, 78)


func test_static_lighting_probe_builds_and_animated_probe_is_rejected() -> void:
	assert_true(_viewer.load_level_by_code("CAV1"))
	_viewer._show_probe("GEN_CHECKPOINT_1.XMR")
	assert_not_null(_viewer.probe_mesh)
	assert_gt(_viewer.probe_mesh.triangle_count, 0)
	assert_eq(_viewer._probe.get_child_count(), _viewer.probe_mesh.part_meshes.size())
	assert_true(_viewer.load_level_by_code("CAV1"))
	_viewer._show_probe("GEN_FROG.XAR")
	assert_null(_viewer.probe_mesh)
	assert_null(_viewer._probe)
	assert_string_contains("\n".join(_viewer.scene_data.diagnostics), "choose a static .XMR")
