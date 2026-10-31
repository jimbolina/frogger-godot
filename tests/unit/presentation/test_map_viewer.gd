extends GutTest
## Map camera and inspector controls with synthetic map records.

var _viewer: MapViewer

func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)

func _scene() -> MapSceneData:
	var source := MapSceneData.new()
	source.level = 48
	source.map = MapFile.new()
	source.remap = TextureRemap.new()
	source.map.vertices = [Vector3i(-256, 0, 0), Vector3i(256, 0, 0), Vector3i(0, 0, 256)]
	source.map.general.camera_source_offset = Vector3i(0, -1024, -1024)
	source.map.general.camera_target_offset = Vector3i(0, -128, 0)
	source.midpoint = Vector3i(0, 0, 128)
	var polygon := MapPolygon.new()
	polygon.vertex_indices = PackedInt32Array([0, 1, 2])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.visible = true
	source.map.polygons.append(polygon)
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	source.map.groups.append(group)
	source.map.group_dimensions = Vector2i.ONE
	source.map.group_size = Vector2i(768, 768)
	return source

func test_camera_offsets_and_reference_projection() -> void:
	var source: MapSceneData = _scene()
	var camera: MapCameraData = MapCameraData.for_scene(source)
	assert_eq(camera.source, Vector3i(0, -1024, -896))
	assert_eq(camera.target, Vector3i(0, -128, 128))
	assert_almost_eq(camera.vertical_fov(), rad_to_deg(2.0 * atan(240.0 / 256.0)), 0.0001)
	camera = MapCameraData.for_scene(source, "map-slice")
	assert_eq(camera.source, Vector3i(0, -10000, -9872))
	assert_eq(camera.target, source.midpoint)
	assert_eq(camera.projection_distance, 1000)
	assert_eq(camera.projection_scale, 2)
	assert_eq(camera.vertical_ratio, 0.9375)
	assert_eq(camera.projection_distance * camera.projection_scale * camera.vertical_ratio, 1875.0)
	assert_almost_eq(camera.vertical_fov(), rad_to_deg(2.0 * atan(240.0 / 2000.0)), 0.0001)

func test_controls_keep_mesh_and_fixed_render_target() -> void:
	assert_true(_viewer.show_scene(_scene()))
	assert_eq(_viewer.render_size(), Vector2i(640, 480))
	var mesh: MapMesh = _viewer.current_mesh
	var instance: MapMesh.Instance = _viewer.map_instance
	_viewer.seek_tick(9)
	_viewer.step_animation()
	assert_eq(_viewer.tick, 10)
	assert_false(_viewer.playing)
	_viewer.set_filtering(true)
	_viewer.set_inspection_visibility(true)
	assert_true(_viewer.set_camera_preset("map-slice"))
	_viewer.reset_camera()
	assert_eq(_viewer.tick, 10)
	assert_same(_viewer.current_mesh, mesh)
	assert_same(_viewer.map_instance, instance)
	assert_true(instance.reference_mode)
	assert_string_contains(_viewer.facts_text(), "SUB1")

func test_failure_and_capture_destination_boundaries() -> void:
	assert_false(_viewer.load_level_by_code("SUB1"))
	var source := MapSceneData.new()
	source.error = "Broken map dependency"
	assert_false(_viewer.show_scene(source))
	assert_string_contains(_viewer.facts_text(), "Broken map dependency")
	assert_false(_viewer.set_camera_preset("unknown"))
	assert_false(MapViewer._external_capture_folder("captures"))
	assert_false(MapViewer._external_capture_folder(ProjectSettings.globalize_path("res://captures/../captures")))
	assert_true(MapViewer._external_capture_folder(OS.get_environment("TEMP")))


func test_invalid_catalog_reports_failure_before_table_access() -> void:
	var invalid := AssetCatalog.new()
	invalid.error = "Invalid executable tables"
	_viewer.open_data(invalid)
	assert_string_contains(_viewer.facts_text(), "Invalid executable tables")
	assert_false(_viewer.load_level_by_code("SUB1"))


func test_replacement_with_null_or_invalid_data_releases_scene_and_probe_state() -> void:
	for invalid: AssetCatalog in [null, AssetCatalog.new()]:
		var source: MapSceneData = _scene()
		source.diagnostics.append("Old source warning")
		assert_true(_viewer.show_scene(source))
		assert_string_contains(_viewer._status.tooltip_text, "Old source warning")
		_viewer.seek_tick(17)
		_viewer.set_playing(true)
		_viewer.probe_mesh = ModelMesh.new()
		_viewer._probe = Node3D.new()
		_viewer._world.add_child(_viewer._probe)
		var old_map: WeakRef = weakref(_viewer.current_mesh)
		if invalid != null:
			invalid.error = "Invalid tables"
		_viewer.open_data(invalid)
		await get_tree().process_frame
		var released_mesh: MapMesh = old_map.get_ref()
		assert_null(released_mesh)
		assert_null(_viewer.scene_data)
		assert_null(_viewer.current_mesh)
		assert_null(_viewer.map_instance)
		assert_null(_viewer.probe_mesh)
		assert_null(_viewer._probe)
		assert_eq(_viewer._world.get_child_count(), 2, "Only the inspection camera and environment remain")
		assert_eq(_viewer._levels.item_count, 0)
		assert_eq(_viewer._status.tooltip_text, "", "Old source diagnostics must not survive replacement")
		assert_eq(_viewer.tick, 0)
		assert_false(_viewer.playing)


func test_detached_viewer_releases_map_resources() -> void:
	assert_true(_viewer.show_scene(_scene()))
	var old_mesh: WeakRef = weakref(_viewer.current_mesh)
	var old_scene: WeakRef = weakref(_viewer.scene_data)
	remove_child(_viewer)
	await get_tree().process_frame
	var released_mesh: MapMesh = old_mesh.get_ref()
	var released_scene: MapSceneData = old_scene.get_ref()
	assert_null(released_mesh)
	assert_null(released_scene)
	assert_null(_viewer.map_instance)
	assert_null(_viewer.current_mesh)
	assert_null(_viewer.scene_data)
	assert_false(_viewer.playing)

func test_custom_raw_camera_and_projection_validate_and_reset() -> void:
	assert_true(_viewer.show_scene(_scene()))
	assert_true(_viewer.set_camera_pose(Vector3i(512, -2048, -4096), Vector3i(512, 0, 0), 512))
	assert_eq(_viewer.projection_distance(), 512)
	assert_eq(GameSpace.to_game(_viewer._camera.position), Vector3i(512, -2048, -4096))
	assert_false(_viewer.set_camera_pose(Vector3i.ZERO, Vector3i.ZERO, 256))
	assert_false(_viewer.set_camera_pose(Vector3i(0, -10, -10), Vector3i.ZERO, 0))
	assert_false(_viewer.set_camera_pose(Vector3i(1000001, 0, 0), Vector3i.ZERO, 256))
	assert_true(_viewer.set_camera_pose(Vector3i(0, -256, 0), Vector3i.ZERO, 256))
	_viewer.set_camera_preset("map-slice")
	assert_eq(_viewer.projection_distance(), 1000)
	assert_eq(_viewer.effective_projection_distance(), 2000)
	assert_eq(MapViewer._parse_vector("1,-2,3"), [1, -2, 3])
	assert_eq(MapViewer._parse_vector("1,two,3").size(), 0)
	assert_eq(MapViewer._parse_vector("1,2").size(), 0)

func test_manual_reference_camera_motion_uses_custom_projection_and_reset_restores() -> void:
	assert_true(_viewer.show_scene(_scene()))
	_viewer.set_camera_preset("map-slice")
	assert_true(_viewer.map_instance.reference_projection)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.relative = Vector2(20, 5)
	_viewer._unhandled_input(motion)
	assert_false(_viewer.map_instance.reference_projection, "fixed C pitch must not override orbit camera")
	assert_true(_viewer._custom_camera)
	assert_eq(_viewer.effective_projection_distance(), 2000)
	assert_eq(_viewer.map_instance.projection_scale, Vector2.ONE)
	assert_true(_viewer.map_instance.reference_mode, "camera override keeps selected reference geometry/water semantics")
	_viewer.reset_camera()
	assert_true(_viewer.map_instance.reference_projection)
	assert_false(_viewer._custom_camera)
	assert_eq(_viewer.map_instance.projection_scale, Vector2(1, 0.9375))

func test_path_overlay_uses_shared_clock_and_releases_on_replacement() -> void:
	var source: MapSceneData = _scene()
	var packet := MapPacket.new()
	packet.count = 1
	packet.offsets = PackedInt32Array([100])
	source.map.packets["PATH"] = packet
	var path := MapPath.new()
	path.path_index = 0
	path.source_offset = 100
	var segment := MapPathSegment.new()
	segment.segment_type = 2
	segment.length = 160
	segment.source_offset = 112
	segment.start = Vector3i.ZERO
	segment.end = Vector3i(10, 0, 0)
	path.segments.append(segment)
	source.map.paths.append(path)
	assert_true(_viewer.show_scene(source))
	assert_not_null(_viewer._path_inspection)
	assert_false(_viewer._path_inspection.visible)
	_viewer.set_path_visibility(true)
	assert_true(_viewer._path_inspection.visible)
	var start := PathStart.new()
	start.speed = 16
	assert_true(_viewer.configure_path(0, start))
	assert_eq(_viewer.path_snapshot().tick_index, 0)
	_viewer.step_animation()
	assert_eq(_viewer.path_snapshot().tick_index, 1)
	assert_eq(_viewer.path_snapshot().segment_distance, 16)
	_viewer.seek_tick(0)
	assert_eq(_viewer.path_snapshot().segment_distance, 0)
	assert_false(_viewer.configure_path(99))
	assert_true(_viewer.show_scene(_scene()))
	assert_null(_viewer.path_snapshot())
	assert_null(_viewer._path_inspection)
	assert_false(_viewer._path_speed.editable)
	assert_eq(_viewer._world.get_child_count(), 3)

func test_synthetic_path_camera_frames_off_origin_geometry() -> void:
	assert_true(_viewer.show_scene(_scene()))
	var definition := PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 160
	segment.start = Vector3i(4000, -200, 6000)
	segment.end = Vector3i(5000, -200, 6000)
	definition.segments.append(segment)
	MapScenarioRun.frame_path(_viewer, definition)
	assert_eq(GameSpace.to_game(_viewer._target), Vector3i(4500, -200, 6000))
	assert_true(_viewer._custom_camera)
