extends GutTest
## The map viewer under the modern profile: scene lights own the environment,
## caves get the cave light, the reference projection stays off, captures name
## their profile and terrain binds per-image textures. Retail stays unchanged.

class ModernCatalog extends AssetCatalog:
	func rendering_profile() -> RenderingProfile:
		return RenderingProfile.modern()


class BookCatalog extends AssetCatalog:
	func map_book_entry(_level: int) -> MapBookEntry:
		return MapBookEntry.new()


var _viewer: MapViewer


func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)


func test_modern_map_is_lit_by_scene_lighting_that_owns_the_environment() -> void:
	assert_true(_viewer.show_scene(_scene(true)))
	assert_true(_viewer.current_mesh.modern)
	var lighting: SceneLighting = _viewer.scene_lighting
	assert_not_null(lighting)
	assert_same(lighting.get_parent(), _viewer._world, "inside the viewport's own world")
	assert_eq(lighting.light_nodes().size(), 1, "the map's one parallel light")
	assert_not_null(lighting.applied_spec)
	assert_null(lighting.cave_light_node(), "no cave light outside cave maps")
	assert_null(_viewer._world_environment.environment, "the viewer's black environment steps aside")
	assert_same(_viewer._viewport.find_world_3d().environment, lighting.environment)


func test_modern_map_without_lights_uses_the_options_lights() -> void:
	var source: MapSceneData = _scene(true)
	source.map.lights.clear()
	assert_true(_viewer.show_scene(source))
	assert_eq(_viewer.scene_lighting.light_nodes().size(),
		SceneLightingBuilder.from_lighting(OptionsModels.options_lighting()).lights.size())


func test_modern_cave_map_places_the_cave_light_at_the_static_start() -> void:
	var source: MapSceneData = _scene(true)
	source.cave_enabled = true
	source.cave_min_r2 = 0x100000
	source.cave_max_r2 = 0x200000
	assert_true(_viewer.show_scene(source))
	var light: OmniLight3D = _viewer.scene_lighting.cave_light_node()
	assert_not_null(light)
	assert_almost_eq(light.position, GameSpace.position(0, 0, 128) + Vector3.UP * CaveLightShape.HEIGHT, Vector3.ONE * 0.0001)


func test_modern_map_slice_keeps_the_pose_without_the_reference_projection() -> void:
	assert_true(_viewer.show_scene(_scene(true)))
	assert_true(_viewer.set_camera_preset("map-slice"))
	_viewer.reset_camera()
	var instance: MapMesh.Instance = _viewer.map_instance
	assert_false(instance.reference_mode)
	assert_false(instance.reference_projection)
	assert_true(instance.water.enabled, "water keeps moving")
	assert_false(instance.diagnostics.has(MapMesh.Instance.MODERN_REFERENCE_DIAGNOSTIC))
	assert_eq(GameSpace.to_game(_viewer._camera.position), Vector3i(0, -10000, -9872), "the map-slice pose")
	assert_eq(_viewer.effective_projection_distance(), 2000)


func test_capture_metadata_names_the_rendering_profile() -> void:
	for modern: bool in [true, false]:
		assert_true(_viewer.show_scene(_scene(modern)))
		var book := BookCatalog.new()
		_viewer.data = book
		var allocations: Dictionary = _viewer.capture_allocations()
		var metadata: Dictionary = _viewer.capture_metadata({}, allocations, allocations)
		var profile: String = metadata["rendering_profile"]
		assert_eq(profile, RenderingProfile.MODERN if modern else RenderingProfile.RETAIL)
		_viewer.data = null


func test_modern_terrain_binds_padded_per_image_textures() -> void:
	assert_true(_viewer.show_scene(_scene(true)))
	assert_eq(_viewer.modern_texture_issues(), PackedStringArray())
	var spec: MapMesh.Surface = _viewer.current_mesh.surface_specs[0][0]
	var page := ImageTexture.create_from_image(Image.create(256, 256, false, Image.FORMAT_RGBA8))
	spec.original.set_shader_parameter("image_nearest", page)
	var issues: PackedStringArray = _viewer.modern_texture_issues()
	assert_eq(issues.size(), 1)
	assert_string_contains(issues[0], "256x256")
	_viewer.capture_allocations()
	assert_true(_viewer._combined_diagnostics().has(issues[0]), "a capture reports the binding")


func test_replacement_releases_the_scene_lighting_and_restores_the_environment() -> void:
	assert_true(_viewer.show_scene(_scene(true)))
	var old: WeakRef = weakref(_viewer.scene_lighting)
	assert_true(_viewer.show_scene(_scene(false)))
	await get_tree().process_frame
	var released: SceneLighting = old.get_ref()
	assert_null(released)
	assert_null(_viewer.scene_lighting)
	assert_same(_viewer._world_environment.environment, _viewer._viewer_environment)
	assert_true(_viewer.show_scene(_scene(true)))
	_viewer.open_data(null)
	await get_tree().process_frame
	assert_null(_viewer.scene_lighting)
	assert_eq(_viewer._world.get_child_count(), 2, "Only the inspection camera and environment remain")
	assert_same(_viewer._viewport.find_world_3d().environment, _viewer._viewer_environment)


func test_retail_viewer_creates_no_scene_lighting_and_keeps_the_reference_camera() -> void:
	assert_true(_viewer.show_scene(_scene(false)))
	assert_false(_viewer.current_mesh.modern)
	assert_null(_viewer.scene_lighting)
	assert_same(_viewer._viewport.find_world_3d().environment, _viewer._viewer_environment)
	assert_eq(_viewer.modern_texture_issues(), PackedStringArray())
	assert_true(_viewer.set_camera_preset("map-slice"))
	assert_true(_viewer.map_instance.reference_mode)
	assert_true(_viewer.map_instance.reference_projection)


func _scene(modern: bool) -> MapSceneData:
	var source := MapSceneData.new()
	if modern:
		source.library.catalog = ModernCatalog.new()
	source.level = 48
	source.map = MapFile.new()
	source.remap = TextureRemap.new()
	source.remap.texture_ids = PackedInt32Array([100])
	source.map.vertices = [Vector3i(-256, 0, 0), Vector3i(256, 0, 0), Vector3i(0, 0, 256)]
	source.map.general.camera_source_offset = Vector3i(0, -1024, -1024)
	source.map.general.camera_target_offset = Vector3i(0, -128, 0)
	source.midpoint = Vector3i(0, 0, 128)
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([0, 1, 2])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
	polygon.texture_id = 0
	polygon.visible = true
	source.map.polygons.append(polygon)
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	source.map.groups.append(group)
	source.map.group_dimensions = Vector2i.ONE
	source.map.group_size = Vector2i(768, 768)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	source.preferred = SyntheticVlo.bank([SyntheticVlo.spec(8, 4, 2, 100, 0, SyntheticVlo.abgr(pixels))])
	source.library.add_bank(source.preferred)
	if not modern:
		var banks: Array[VloFile] = [source.preferred]
		source.page_set = SyntheticVlo.page_set(banks)
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
