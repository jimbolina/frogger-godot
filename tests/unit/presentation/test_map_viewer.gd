extends GutTest
## Map camera, inspector controls, scene lighting and captures with synthetic map records.

class BookCatalog extends AssetCatalog:
	func map_book_entry(_level: int) -> MapBookEntry:
		return MapBookEntry.new()


var _viewer: MapViewer

func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)

func after_each() -> void:
	GraphicsProfile.reset()

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

func _lit_scene() -> MapSceneData:
	var source: MapSceneData = _scene()
	source.remap.texture_ids = PackedInt32Array([100])
	source.map.polygons[0].type_index = 3
	source.map.polygons[0].uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
	source.map.polygons[0].texture_id = 0
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	source.preferred = SyntheticVlo.bank([SyntheticVlo.spec(8, 4, 2, 100, 0, SyntheticVlo.abgr(pixels))])
	source.library.add_bank(source.preferred)
	var ambient := MapLight.new()
	ambient.light_type = 1
	ambient.enabled = true
	ambient.color = Color8(64, 64, 64)
	var parallel := MapLight.new()
	parallel.light_type = 2
	parallel.enabled = true
	parallel.color = Color8(128, 128, 128)
	parallel.direction = Vector3i(0, 4096, 0)
	source.map.lights.append_array([ambient, parallel])
	return source

func test_camera_offsets() -> void:
	var source: MapSceneData = _scene()
	var camera: MapCameraData = MapCameraData.for_scene(source)
	assert_eq(camera.source, Vector3i(0, -1024, -896))
	assert_eq(camera.target, Vector3i(0, -128, 128))
	assert_eq(camera.projection_distance, 256)
	assert_almost_eq(camera.vertical_fov(), rad_to_deg(2.0 * atan(240.0 / 256.0)), 0.0001)

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
	_viewer.reset_camera()
	assert_eq(_viewer.tick, 10)
	assert_same(_viewer.current_mesh, mesh)
	assert_same(_viewer.map_instance, instance)
	assert_string_contains(_viewer.facts_text(), "SUB1")
	assert_string_contains(_viewer.facts_text(), "default")

func test_failure_and_capture_destination_boundaries() -> void:
	assert_false(_viewer.load_level_by_code("SUB1"))
	var source := MapSceneData.new()
	source.error = "Broken map dependency"
	assert_false(_viewer.show_scene(source))
	assert_string_contains(_viewer.facts_text(), "Broken map dependency")
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
	assert_true(_viewer._custom_camera)
	assert_string_contains(_viewer.capture_basename(), "_custom_")
	_viewer.reset_camera()
	assert_false(_viewer._custom_camera)
	assert_eq(_viewer.projection_distance(), 256)
	assert_eq(GameSpace.to_game(_viewer._camera.position), Vector3i(0, -1024, -896))
	assert_eq(MapViewer._parse_vector("1,-2,3"), [1, -2, 3])
	assert_eq(MapViewer._parse_vector("1,two,3").size(), 0)
	assert_eq(MapViewer._parse_vector("1,2").size(), 0)

func test_manual_camera_motion_keeps_the_projection_and_reset_restores() -> void:
	assert_true(_viewer.show_scene(_scene()))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.relative = Vector2(20, 5)
	_viewer._unhandled_input(motion)
	assert_true(_viewer._custom_camera)
	assert_eq(_viewer.projection_distance(), 256)
	assert_eq(_viewer.map_instance.projection_scale, Vector2.ONE)
	assert_string_contains(_viewer.capture_basename(), "_custom_")
	_viewer.reset_camera()
	assert_false(_viewer._custom_camera)
	assert_eq(_viewer.map_instance.projection_scale, Vector2.ONE)

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
	assert_eq(_viewer._world.get_child_count(), 4, "camera, environment, map and its scene lighting")

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


func test_map_is_lit_by_scene_lighting_that_owns_the_environment() -> void:
	assert_true(_viewer.show_scene(_lit_scene()))
	var lighting: SceneLighting = _viewer.scene_lighting
	assert_not_null(lighting)
	assert_same(lighting.get_parent(), _viewer._world, "inside the viewport's own world")
	assert_eq(lighting.light_nodes().size(), 1, "the map's one parallel light")
	assert_not_null(lighting.applied_spec)
	assert_null(lighting.cave_light_node(), "no cave light outside cave maps")
	assert_null(_viewer._world_environment.environment, "the viewer's black environment steps aside")
	assert_same(_viewer._viewport.find_world_3d().environment, lighting.environment)


func test_map_without_lights_uses_the_options_lights() -> void:
	var source: MapSceneData = _lit_scene()
	source.map.lights.clear()
	assert_true(_viewer.show_scene(source))
	assert_eq(_viewer.scene_lighting.light_nodes().size(),
		SceneLightingBuilder.from_lighting(OptionsModels.options_lighting()).lights.size())


func test_cave_map_places_the_cave_light_at_the_static_start() -> void:
	var source: MapSceneData = _lit_scene()
	source.cave_enabled = true
	source.cave_min_r2 = 0x100000
	source.cave_max_r2 = 0x200000
	assert_true(_viewer.show_scene(source))
	var light: OmniLight3D = _viewer.scene_lighting.cave_light_node()
	assert_not_null(light)
	assert_almost_eq(light.position, GameSpace.position(0, 0, 128) + Vector3.UP * CaveLightShape.HEIGHT, Vector3.ONE * 0.0001)


func test_the_map_look_and_cave_mode_follow_the_profile() -> void:
	var source: MapSceneData = _lit_scene()
	source.cave_enabled = true
	source.cave_min_r2 = 0x100000
	source.cave_max_r2 = 0x200000
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.water_reflection = 0.5
	values.vertex_tint = 0.4
	values.lava_emission = 2.5
	GraphicsProfile.replace(values)
	assert_true(_viewer.show_scene(source))
	assert_almost_eq(_viewer.map_instance.water_look()[0], 0.5, 1e-6)
	assert_almost_eq(_viewer.map_instance._vertex_tint, 0.4, 1e-6)
	assert_eq(_viewer.map_instance.emission_scale(), 2.5)
	var light: OmniLight3D = _viewer.scene_lighting.cave_light_node()
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(0x200000, CaveLightShape.Mode.EXACT_EDGE), 1e-5)
	values.water_reflection = 0.2
	values.vertex_tint = 1.0
	values.lava_emission = 0.5
	values.cave_light_mode = GraphicsSettings.CaveMode.FITTED_RANGE
	GraphicsProfile.replace(values)
	assert_almost_eq(_viewer.map_instance.water_look()[0], 0.2, 1e-6)
	assert_eq(_viewer.map_instance.emission_scale(), 0.5)
	assert_eq(_viewer.map_instance._vertex_tint, 1.0)
	assert_eq(_viewer.scene_lighting.cave_light_node(), light, "the same cave light")
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(0x200000, CaveLightShape.Mode.FITTED_RANGE), 1e-5)
	assert_almost_eq(light.position, GameSpace.position(0, 0, 128) + Vector3.UP * CaveLightShape.HEIGHT, Vector3.ONE * 0.0001)


func test_capture_metadata_and_allocations() -> void:
	assert_true(_viewer.show_scene(_lit_scene()))
	_viewer.data = BookCatalog.new()
	var allocations: Dictionary = _viewer.capture_allocations()
	var sky_tiles_id: int = allocations["sky_tiles_id"]
	var mesh_count: int = allocations["mesh_count"]
	assert_eq(sky_tiles_id, 0, "no sky on this map")
	assert_eq(mesh_count, _viewer.current_mesh.groups.size())
	var metadata: Dictionary = _viewer.capture_metadata({}, allocations, allocations)
	var growth: bool = metadata["allocation_growth"]
	var camera: String = metadata["camera"]
	var projection: int = metadata["projection_distance"]
	assert_false(growth)
	assert_eq(camera, "default")
	assert_eq(projection, 256)
	for retired: String in ["rendering_profile", "page_texture_growth", "effective_projection", "clip_scale"]:
		assert_false(metadata.has(retired), retired)
	_viewer.data = null


func test_replacement_releases_the_scene_lighting_and_restores_the_environment() -> void:
	assert_true(_viewer.show_scene(_lit_scene()))
	var old: WeakRef = weakref(_viewer.scene_lighting)
	assert_true(_viewer.show_scene(_lit_scene()))
	await get_tree().process_frame
	var released: SceneLighting = old.get_ref()
	assert_null(released)
	assert_not_null(_viewer.scene_lighting)
	_viewer.open_data(null)
	await get_tree().process_frame
	assert_null(_viewer.scene_lighting)
	assert_eq(_viewer._world.get_child_count(), 2, "Only the inspection camera and environment remain")
	assert_same(_viewer._world_environment.environment, _viewer._viewer_environment)
	assert_same(_viewer._viewport.find_world_3d().environment, _viewer._viewer_environment)

