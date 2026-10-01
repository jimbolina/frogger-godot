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


func test_invalid_game_data_reports_failure_before_table_access() -> void:
	var invalid := GameData.new()
	invalid.error = "Invalid executable tables"
	_viewer.open_data(invalid)
	assert_string_contains(_viewer.facts_text(), "Invalid executable tables")
	assert_false(_viewer.load_level_by_code("SUB1"))

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
