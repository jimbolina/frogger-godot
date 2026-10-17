extends GutTest
## Synthetic map group geometry, materials and independent instance playback.


func test_material_settings_invalidate_inactive_animation_frames() -> void:
	var scene: MapSceneData = _scene()
	scene.map.polygons[0].flags = 2
	var track := MapAnimation.new()
	track.type = 2
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([0])
	scene.map.animations.append(track)
	var instance: MapMesh.Instance = MapMeshBuilder.new().build(scene).create_instance()
	var node: MeshInstance3D = instance.get_child(0)
	instance.set_tick(0)
	instance.set_projection_scale(Vector2(1.0, 0.9375))
	instance.set_reference_projection(true)
	instance.set_filtering(true)
	instance.set_camera_position(Vector3i(20, 30, 40))
	for tick: int in 4:
		instance.set_tick(tick)
		var material: ShaderMaterial = node.get_surface_override_material(0)
		var scale: Vector2 = material.get_shader_parameter("projection_scale")
		var camera: Vector3 = material.get_shader_parameter("camera_game")
		var reference: bool = material.get_shader_parameter("reference_projection")
		assert_eq(scale, Vector2(1.0, 0.9375))
		assert_eq(camera, Vector3(20, 30, 40))
		assert_true(reference)
		assert_true(material.shader.code.contains("filter_linear"))
	instance.free()

func test_reference_polygon_budget_skips_whole_groups_and_excludes_lines() -> void:
	var groups: Array[MapGroup] = []
	for count: int in [2000, 600, 400, 100, 1]:
		var group := MapGroup.new()
		group.counts = PackedInt32Array([count, 0, 0, 0, 0, 0, 0, 0, 999])
		groups.append(group)
	assert_eq(MapMesh.Instance.reference_budget(groups, PackedInt32Array([0, 1, 2, 3, 4])),
		PackedInt32Array([0, 2, 3]), "600 cannot fit; 400 and 100 fill remaining budget, G2 ignored")


func test_reference_empty_budget_hides_geometry() -> void:
	var scene: MapSceneData = _scene()
	scene.map.groups[0].counts = PackedInt32Array([2501, 0, 0, 0, 0, 0, 0, 0])
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	assert_eq(instance.visible_group_indices(), PackedInt32Array([0]))
	instance.set_reference_mode(true)
	assert_true(instance.visible_group_indices().is_empty())
	instance.set_reference_mode(false)
	assert_eq(instance.visible_group_indices(), PackedInt32Array([0]))
	instance.free()


func test_valid_animation_cel_recovers_missing_original_texture() -> void:
	var scene: MapSceneData = _scene()
	scene.remap.texture_ids = PackedInt32Array([999, 101])
	var track := MapAnimation.new()
	track.type = 2
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([0])
	scene.map.animations.append(track)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var missing: bool = material.get_shader_parameter("missing_image")
	var texture: Texture2D = material.get_shader_parameter("image")
	assert_false(missing)
	assert_not_null(texture)
	var arrays: Array = built.groups[0].surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs, PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), "missing original dimensions retain explicit zero UV fallback")
	instance.free()


func _scene() -> MapSceneData:
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.vertices = [Vector3i(0, 0, 256), Vector3i(256, 0, 256),
		Vector3i(0, 0, 0), Vector3i(256, 0, 0)]
	scene.map.group_size = Vector2i(256, 256)
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	polygon.texture_id = 0
	polygon.visible = true
	scene.map.polygons.append(polygon)
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	scene.map.groups.append(group)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 100, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(pixels))
	var second: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 101, 0, SyntheticVlo.abgr(pixels))
	scene.preferred = VloFile.parse(SyntheticVlo.build_vlo([spec, second]))
	scene.library.add_bank(scene.preferred)
	scene.remap = TextureRemap.new()
	scene.remap.texture_ids = PackedInt32Array([100, 101])
	return scene


func test_map_strip_corner_order_uvs_and_polygon_blend_flag() -> void:
	var scene: MapSceneData = _scene()
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_eq(built.group_count, 1)
	assert_eq(built.surface_count, 1)
	assert_eq(built.triangle_count, 2)
	assert_eq(MapMeshBuilder.triangle_corners(4), PackedInt32Array([0, 1, 2, 1, 3, 2]))
	var arrays: Array = built.groups[0].surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(positions, PackedVector3Array([Vector3(0, 0, -1), Vector3(1, 0, -1),
		Vector3.ZERO, Vector3(1, 0, -1), Vector3(1, 0, 0), Vector3.ZERO]))
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs, PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(0, 4),
		Vector2(8, 0), Vector2(8, 4), Vector2(0, 4)]))
	var material: ShaderMaterial = built.groups[0].surface_get_material(0)
	var texture: Texture2D = material.get_shader_parameter("image")
	var pixel_scale: Vector2 = material.get_shader_parameter("pixel_scale")
	var pixel_padding: Vector2 = material.get_shader_parameter("pixel_padding")
	assert_eq(texture.get_width(), 256, "physical page includes neighbouring images")
	assert_eq(pixel_scale, Vector2.ONE / 256.0)
	assert_eq(pixel_padding, Vector2.ONE / 256.0)
	assert_false(material.shader.code.contains("ALPHA = 0.5"), "map polygon controls translucency despite texture flag")
	scene.map.polygons[0].flags = 1
	built = MapMeshBuilder.new().build(scene)
	material = built.groups[0].surface_get_material(0)
	assert_true(material.shader.code.contains("ALPHA = 0.5"))


func test_animation_updates_materials_without_rebuilding_shared_meshes() -> void:
	var scene: MapSceneData = _scene()
	scene.cave_enabled = true
	scene.map.polygons[0].type_index = 7
	scene.map.polygons[0].flags = 2
	var track := MapAnimation.new()
	track.type = 3
	track.delta_u = 1
	track.uv_frame_count = 4
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([0])
	scene.map.animations.append(track)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var mesh_id: int = built.groups[0].get_instance_id()
	var first: MapMesh.Instance = built.create_instance()
	var second: MapMesh.Instance = built.create_instance()
	first.set_tick(0)
	assert_eq(first.animation.image_id(0), 101)
	assert_eq(second.animation.image_id(0), 100)
	var node: MeshInstance3D = first.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var animation_offset: Vector2 = material.get_shader_parameter("animation_offset")
	assert_eq(animation_offset, Vector2(1, 0))
	assert_ne(material, built.groups[0].surface_get_material(0))
	var material_id: int = material.get_instance_id()
	first.set_camera_position(Vector3i(500, -200, 900))
	first.set_cave_frog(Vector3i(100, -64, 200))
	for tick: int in 4:
		first.set_tick(tick)
		var prepared: ShaderMaterial = node.get_surface_override_material(0)
		var camera: Vector3 = prepared.get_shader_parameter("camera_game")
		var frog: Vector3 = prepared.get_shader_parameter("cave_frog")
		assert_eq(camera, Vector3(500, -200, 900))
		assert_eq(frog, Vector3(100, -64, 200))
	first.set_tick(2)
	material = node.get_surface_override_material(0)
	assert_eq(material.get_instance_id(), material_id, "prepared frame material reused")
	assert_eq(built.groups[0].get_instance_id(), mesh_id)
	assert_eq(scene.map.polygons[0].uvs[0], Vector2.ZERO)
	first.set_filtering(true)
	assert_true(material.shader.code.contains("filter_linear"))
	first.free()
	second.free()


func test_inspection_geometry_default_hidden_and_reference_group_cap() -> void:
	var scene: MapSceneData = _scene()
	scene.map.groups.clear()
	for index: int in 140:
		var group := MapGroup.new()
		group.coordinates = Vector2i(index, 0)
		group.polygon_indices = PackedInt32Array([0])
		scene.map.groups.append(group)
	var hidden := MapGroup.new()
	hidden.visible = false
	hidden.polygon_indices = PackedInt32Array([0])
	scene.map.groups.append(hidden)
	var unreferenced := MapPolygon.new()
	unreferenced.type_index = 0
	unreferenced.vertex_indices = PackedInt32Array([0, 1, 2])
	unreferenced.colors = PackedColorArray([Color8(5, 10, 15)])
	scene.map.polygons.append(unreferenced)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_eq(built.group_count, 140)
	assert_eq(built.groups.size(), 142)
	var instance: MapMesh.Instance = built.create_instance()
	assert_eq(instance.visible_group_indices().size(), 140)
	instance.set_reference_target(Vector3i(70 * 256, 0, 0))
	instance.set_reference_mode(true)
	var visible: PackedInt32Array = instance.visible_group_indices()
	assert_eq(visible.size(), 128)
	assert_false(visible.has(0))
	assert_true(visible.has(70))
	assert_false(instance.water.enabled)
	instance.set_inspection_visibility(true)
	assert_eq(instance.visible_group_indices().size(), 130)
	instance.set_inspection_visibility(false)
	instance.set_reference_mode(false)
	assert_eq(instance.visible_group_indices().size(), 140)
	instance.free()


func test_environment_cave_water_attributes_and_affine_shader() -> void:
	var scene: MapSceneData = _scene()
	scene.environment_image = scene.preferred.images[1]
	scene.cave_enabled = true
	scene.cave_min_r2 = 1
	scene.cave_max_r2 = 1000000
	scene.map.polygons[0].type_index = 7
	scene.map.polygons[0].flags = 6
	for index: int in scene.map.vertices.size():
		scene.map.vertices[index].y = 1100
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var spec: MapMesh.Surface = built.surface_specs[0][0]
	assert_true(spec.environment)
	assert_eq(spec.image.texture_id, 100, "map ENVMAP retains polygon remap texture")
	assert_true(spec.cave)
	assert_eq(spec.layer, 2, "environment overrides MAX_OT ordering")
	var arrays: Array = built.groups[0].surface_get_arrays(0)
	var ranks: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(ranks[0], Vector2(0, 4))
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	instance.set_camera_position(Vector3i(500, -200, 900))
	instance.set_projection_scale(Vector2(1, 0.9375))
	instance.set_cave_frog(Vector3i(0, 1100, 0))
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var camera_game: Vector3 = material.get_shader_parameter("camera_game")
	var cave_frog: Vector3 = material.get_shader_parameter("cave_frog")
	var projection_scale: Vector2 = material.get_shader_parameter("projection_scale")
	assert_eq(camera_game, Vector3(500, -200, 900))
	instance.set_camera_presentation(Vector3(500.25, -200.5, 900.75))
	camera_game = material.get_shader_parameter("camera_game")
	assert_eq(camera_game, Vector3(500.25, -200.5, 900.75))
	assert_eq(instance.camera_position, Vector3i(500, -200, 900), "presentation does not change the committed camera")
	assert_eq(cave_frog, Vector3(0, 1100, 0))
	assert_eq(projection_scale, Vector2(1, 0.9375))
	assert_true(material.shader.code.contains("affine_uv / affine_weight"))
	assert_true(material.shader.code.contains("CLIP_SPACE_FAR"))
	assert_true(material.shader.code.contains("depth_draw_never"))
	assert_true(material.shader.code.contains("through_renderer"))
	instance.free()


func test_sky_rotations_camera_translation_and_fixed_height() -> void:
	var scene: MapSceneData = _scene()
	scene.sky_land = SkyLandFile.new()
	scene.sky_land.dimensions = Vector2i(1, 1)
	scene.sky_land.texture_ids = PackedInt32Array([0])
	scene.sky_land.rotations = PackedInt32Array([1])
	scene.sky_remap = scene.remap
	scene.level = 43
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_not_null(built.sky_mesh)
	var arrays: Array = built.sky_mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(positions[0], Vector3(-2, -24, -2))
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[0], Vector2(1, 5), "rotated sky endpoint includes physical image origin (1,1)")
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color8(16, 32, 48))
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_camera_position(Vector3i(256, 512, 768))
	var sky_node: MeshInstance3D = instance.get_child(instance.get_child_count() - 1)
	assert_eq(sky_node.position, Vector3(1, -2, -3))
	instance.set_camera_presentation(Vector3(256.5, 512.25, 768.75))
	assert_eq(sky_node.position, Vector3(256.5, -512.25, -768.75) / 256.0)
	instance.set_tick(0)
	var drift: Vector3 = Vector3(instance.sky.translation())
	assert_eq(sky_node.position, Vector3(256.5 + drift.x, -512.25 - drift.y, -768.75 - drift.z) / 256.0)
	instance.free()


func test_optional_model_map_lighting_uses_probe_world_normal() -> void:
	var scene: MapSceneData = _scene()
	var light := MapLight.new()
	light.light_type = 1
	light.enabled = true
	light.color = Color8(64, 64, 64)
	var lighting := MapLighting.new()
	lighting.configure([light])
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4, Color8(128, 128, 128))]))
	var builder := ModelMeshBuilder.new(scene.library)
	builder.lighting = lighting
	var built: ModelMesh = builder.build(file.static_models[0])
	var colours: PackedColorArray = built.part_meshes[0].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color8(32, 32, 32))


func test_missing_page_reports_and_keeps_visible_fallback() -> void:
	var scene: MapSceneData = _scene()
	scene.preferred.images[0].vram_y = 14 * 256
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.diagnostics.has("Invalid PC texture page 14"))
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var missing: bool = material.get_shader_parameter("missing_image")
	assert_true(missing, "invalid page remains magenta even with a valid image header")
	assert_true(material.shader.code.contains("texel.a < 0.5 && !missing_image"))
	instance.free()
