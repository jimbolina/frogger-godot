extends GutTest
## Synthetic map group geometry, per-image lit materials and independent instance playback.

class UpscaledCatalog extends AssetCatalog:
	var scaled: Dictionary[VloImage, Texture2D] = {}

	func texture_set() -> TextureSet:
		return TextureSet.x4()

	func texture_of(image: VloImage) -> Texture2D:
		if image == null:
			return null
		if not scaled.has(image):
			var pixels: Image = image.texture.get_image()
			pixels.resize(image.padded_width * 4, image.padded_height * 4, Image.INTERPOLATE_NEAREST)
			scaled[image] = ImageTexture.create_from_image(pixels)
		return scaled[image]


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
	assert_eq(material.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.OPAQUE, false),
		"map polygon controls translucency despite texture flag")
	scene.map.polygons[0].flags = 1
	built = MapMeshBuilder.new().build(scene)
	material = built.groups[0].surface_get_material(0)
	assert_eq(material.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.AVERAGE, false))


func test_arrays_carry_normals_and_water_ranks_without_custom_data() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_rich_scene())
	var compared: int = 0
	for group: int in built.groups.size():
		for surface: int in built.groups[group].get_surface_count():
			var format: int = built.groups[group].surface_get_format(surface)
			assert_ne(format & Mesh.ARRAY_FORMAT_NORMAL, 0)
			assert_ne(format & Mesh.ARRAY_FORMAT_TEX_UV2, 0)
			assert_eq(format & Mesh.ARRAY_FORMAT_CUSTOM0, 0, "no reference depths")
			compared += 1
	assert_eq(compared, 4, "floor, slope, animated and untextured surfaces")
	var floor_normals: PackedVector3Array = built.groups[0].surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal: Vector3 in floor_normals:
		assert_almost_eq(normal, Vector3.UP, Vector3.ONE * 0.001)
	assert_eq(built.sky_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0, 0)
	var sky_layers: PackedVector2Array = built.sky_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_eq(sky_layers[0].x, 0.0)
	assert_eq(sky_layers[6].x, 1.0, "the second tile's texture has the second layer")


func test_material_binds_the_padded_image_texture() -> void:
	var scene: MapSceneData = _scene()
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.diagnostics.is_empty(), ", ".join(built.diagnostics))
	var material: ShaderMaterial = built.groups[0].surface_get_material(0)
	var nearest: Texture2D = material.get_shader_parameter("image_nearest")
	var linear: Texture2D = material.get_shader_parameter("image_linear")
	assert_eq(nearest.get_size(), Vector2(10, 6), "the padded image, not a 256 page")
	assert_same(linear, nearest)
	var origin: Vector2 = material.get_shader_parameter("image_origin")
	var padding: Vector2 = material.get_shader_parameter("image_padding")
	var padded_size: Vector2 = material.get_shader_parameter("image_padded_size")
	var textured: bool = material.get_shader_parameter("textured")
	var linear_filter: bool = material.get_shader_parameter("linear_filter")
	var missing: bool = material.get_shader_parameter("missing_image")
	assert_eq(origin, Vector2(1, 1))
	assert_eq(padding, Vector2(1, 1))
	assert_eq(padded_size, Vector2(10, 6))
	assert_true(textured)
	assert_false(linear_filter)
	assert_false(missing)
	assert_false(built.linear_filter, "the retail set stays nearest")
	assert_true(_unset(material, "pixel_scale"), "no page uniforms")
	assert_true(_unset(material, "texel_inset"))


func test_build_filters_as_the_library_texture_set_asks() -> void:
	var scene: MapSceneData = _scene()
	scene.library.catalog = UpscaledCatalog.new()
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.linear_filter)
	var material: ShaderMaterial = built.groups[0].surface_get_material(0)
	var texture: Texture2D = material.get_shader_parameter("image_linear")
	var linear_filter: bool = material.get_shader_parameter("linear_filter")
	var padded_size: Vector2 = material.get_shader_parameter("image_padded_size")
	assert_eq(texture.get_size(), Vector2(40, 24))
	assert_true(linear_filter)
	assert_eq(padded_size, Vector2(10, 6), "coordinates stay normalised over retail pixels")
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var node: MeshInstance3D = instance.get_child(0)
	var prepared: ShaderMaterial = node.get_surface_override_material(0)
	instance.set_filtering(false)
	linear_filter = prepared.get_shader_parameter("linear_filter")
	assert_false(linear_filter)
	assert_eq(prepared.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.OPAQUE, false),
		"filtering changes a uniform, not the variant")
	instance.free()
	built = MapMeshBuilder.new().build(scene, false)
	material = built.groups[0].surface_get_material(0)
	linear_filter = material.get_shader_parameter("linear_filter")
	assert_false(built.linear_filter, "an explicit choice wins")
	assert_false(linear_filter)


func test_polygon_flags_pick_variants_and_priorities() -> void:
	var cases: Array[Array] = [[0, ModelShaders.Blend.OPAQUE, false, 0], [1, ModelShaders.Blend.AVERAGE, false, 0],
		[4, ModelShaders.Blend.OPAQUE, true, -126], [5, ModelShaders.Blend.AVERAGE, true, -126],
		[2, ModelShaders.Blend.OPAQUE, true, -125], [6, ModelShaders.Blend.OPAQUE, true, -125]]
	for entry: Array in cases:
		var flags: int = entry[0]
		var priority: int = entry[3]
		var scene: MapSceneData = _scene()
		scene.map.polygons[0].flags = flags
		var built: MapMesh = MapMeshBuilder.new().build(scene)
		var material: ShaderMaterial = built.groups[0].surface_get_material(0)
		var blend: ModelShaders.Blend = entry[1]
		var far: bool = entry[2]
		assert_eq(material.shader.resource_path, MapShaders.shader_path(blend, far), "flags %d" % flags)
		assert_eq(material.render_priority, priority, "flags %d" % flags)
		var instance: MapMesh.Instance = built.create_instance()
		instance.set_tick(0)
		var node: MeshInstance3D = instance.get_child(0)
		var prepared: ShaderMaterial = node.get_surface_override_material(0)
		var environment: bool = prepared.get_shader_parameter("environment_uv")
		assert_eq(environment, (flags & 2) != 0, "flags %d" % flags)
		instance.free()
	var scene: MapSceneData = _scene()
	scene.preferred.images[0].texture_page_word |= 1 << 8
	scene.map.polygons[0].flags = 1
	var material: ShaderMaterial = MapMeshBuilder.new().build(scene).groups[0].surface_get_material(0)
	assert_eq(material.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.ADD, false))


func test_environment_and_water_attributes() -> void:
	var scene: MapSceneData = _scene()
	scene.environment_image = scene.preferred.images[1]
	scene.cave_enabled = true
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
	instance.set_camera_presentation(Vector3(500.25, -200.5, 900.75))
	instance.set_projection_scale(Vector2(1, 0.9375))
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var camera_game: Vector3 = material.get_shader_parameter("camera_game")
	var projection_scale: Vector2 = material.get_shader_parameter("projection_scale")
	var water_enabled: bool = material.get_shader_parameter("water_enabled")
	assert_eq(camera_game, Vector3(500.25, -200.5, 900.75))
	assert_eq(projection_scale, Vector2(1, 0.9375))
	assert_true(water_enabled)
	assert_eq(material.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.OPAQUE, true))
	assert_string_contains(material.shader.code, "#define MAP_FAR")
	assert_string_contains(material.shader.code, "depth_draw_never")
	instance.free()


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
	instance.set_filtering(true)
	instance.set_camera_presentation(Vector3(20, 30, 40))
	for tick: int in 4:
		instance.set_tick(tick)
		var material: ShaderMaterial = node.get_surface_override_material(0)
		var scale: Vector2 = material.get_shader_parameter("projection_scale")
		var camera: Vector3 = material.get_shader_parameter("camera_game")
		var linear_filter: bool = material.get_shader_parameter("linear_filter")
		assert_eq(scale, Vector2(1.0, 0.9375), "tick %d" % tick)
		assert_eq(camera, Vector3(20, 30, 40), "tick %d" % tick)
		assert_true(linear_filter, "tick %d" % tick)
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
	var texture: Texture2D = material.get_shader_parameter("image_nearest")
	assert_false(missing)
	assert_not_null(texture)
	var arrays: Array = built.groups[0].surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs, PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), "missing original dimensions retain explicit zero UV fallback")
	instance.free()


func test_missing_texture_keeps_the_magenta_fallback() -> void:
	var scene: MapSceneData = _scene()
	scene.preferred.images[0].texture = null
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var missing: bool = material.get_shader_parameter("missing_image")
	assert_true(missing, "an image without a texture draws magenta")
	scene.remap.texture_ids = PackedInt32Array([999, 101])
	built = MapMeshBuilder.new().build(scene)
	assert_eq(built.missing_texture_ids, PackedInt32Array([999]))
	assert_true(built.diagnostics.has("Map texture 999 is unavailable; rendered magenta"))
	instance.free()


func test_animation_updates_materials_without_rebuilding_shared_meshes() -> void:
	var scene: MapSceneData = _scene()
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
	first.set_camera_presentation(Vector3(500, -200, 900))
	for tick: int in 4:
		first.set_tick(tick)
		var prepared: ShaderMaterial = node.get_surface_override_material(0)
		var camera: Vector3 = prepared.get_shader_parameter("camera_game")
		assert_eq(camera, Vector3(500, -200, 900))
	first.set_tick(2)
	material = node.get_surface_override_material(0)
	assert_eq(material.get_instance_id(), material_id, "prepared frame material reused")
	assert_eq(built.groups[0].get_instance_id(), mesh_id)
	assert_eq(scene.map.polygons[0].uvs[0], Vector2.ZERO)
	first.set_filtering(true)
	var linear_filter: bool = material.get_shader_parameter("linear_filter")
	assert_true(linear_filter)
	first.free()
	second.free()


func test_animation_frames_carry_offsets_and_wrap_inside_the_image() -> void:
	var scene: MapSceneData = _scene()
	var track := MapAnimation.new()
	track.type = 3
	track.delta_v = 1
	track.uv_frame_count = 4
	track.frames_per_texture = 2
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([0])
	scene.map.animations.append(track)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	var node: MeshInstance3D = instance.get_child(0)
	var image: VloImage = scene.preferred.images[0]
	var corners: PackedVector2Array = built.groups[0].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	for tick: int in 6:
		instance.set_tick(tick)
		var material: ShaderMaterial = node.get_surface_override_material(0)
		var offset: Vector2 = material.get_shader_parameter("animation_offset")
		var expected: Vector2i = instance.animation.track_offset(0)
		assert_eq(offset, Vector2(expected), "tick %d" % tick)
		var texture: Texture2D = material.get_shader_parameter("image_nearest")
		var frame_id: int = instance.animation.track_image_id(0)
		assert_same(texture, scene.library.image_for_id(frame_id, scene.preferred).texture, "tick %d" % tick)
		var low := Vector2(1, 1 + offset.y) / Vector2(10, 6)
		var high := Vector2(9, 5 + offset.y) / Vector2(10, 6)
		assert_almost_eq(MapShaders.normalised_uv(corners[0], image, offset), low, Vector2.ONE * 0.0001)
		assert_almost_eq(MapShaders.normalised_uv(corners[4], image, offset), high, Vector2.ONE * 0.0001)
	assert_eq(MapShaders.normalised_uv(Vector2(255, 0), image), Vector2(0, 1) / Vector2(10, 6),
		"byte wrap lands on the first padding column")
	assert_eq(MapShaders.normalised_uv(Vector2(8, 4), image), Vector2(9, 5) / Vector2(10, 6),
		"u == width samples the first right padding column")
	instance.free()


func test_cave_surfaces_ignore_the_vertex_tint_and_wrap_the_omni_light() -> void:
	var scene: MapSceneData = _scene()
	scene.cave_enabled = true
	scene.cave_min_r2 = 100
	scene.cave_max_r2 = 1000
	scene.map.polygons[0].type_index = 7
	scene.map.polygons.append(_quad(1, 3))
	scene.map.groups[0].polygon_indices = PackedInt32Array([0, 1])
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	instance.set_vertex_tint(0.75)
	var node: MeshInstance3D = instance.get_child(0)
	var seen: int = 0
	for surface: int in node.mesh.get_surface_count():
		var material: ShaderMaterial = node.get_surface_override_material(surface)
		var cave: bool = built.surface_specs[0][surface].cave
		var tint: float = material.get_shader_parameter("vertex_tint")
		var wrap: float = material.get_shader_parameter("omni_wrap")
		assert_eq(tint, 0.0 if cave else 0.75)
		assert_eq(wrap, 1.0 if cave else 0.0)
		for parameter: String in ["cave_enabled", "cave_frog", "cave_min_r2", "cave_max_r2", "reference_projection"]:
			assert_true(_unset(material, parameter), parameter)
		seen += 1
	assert_eq(seen, 2)
	instance.free()


func test_vertex_tint_reaches_every_frame_material() -> void:
	var scene: MapSceneData = _scene()
	var track := MapAnimation.new()
	track.type = 2
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([0])
	scene.map.animations.append(track)
	var instance: MapMesh.Instance = MapMeshBuilder.new().build(scene).create_instance()
	instance.set_vertex_tint(0.5)
	var node: MeshInstance3D = instance.get_child(0)
	for tick: int in 3:
		instance.set_tick(tick)
		var material: ShaderMaterial = node.get_surface_override_material(0)
		var tint: float = material.get_shader_parameter("vertex_tint")
		assert_eq(tint, 0.5, "tick %d" % tick)
	instance.set_vertex_tint(1.0)
	var current: ShaderMaterial = node.get_surface_override_material(0)
	var restored: float = current.get_shader_parameter("vertex_tint")
	assert_eq(restored, 1.0)
	instance.free()


func test_inspection_geometry_default_hidden_and_group_selection() -> void:
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
	assert_true(instance.water.enabled)
	instance.set_inspection_visibility(true)
	assert_eq(instance.visible_group_indices().size(), 142)
	instance.set_inspection_visibility(false)
	instance.set_group_selection(PackedInt32Array([3, 70]))
	assert_eq(instance.visible_group_indices(), PackedInt32Array([3, 70]))
	instance.set_group_selection(PackedInt32Array())
	assert_eq(instance.visible_group_indices().size(), 140)
	instance.free()


func test_groups_cast_shadows_and_the_sky_does_not() -> void:
	var instance: MapMesh.Instance = MapMeshBuilder.new().build(_rich_scene()).create_instance()
	var group: MeshInstance3D = instance.get_child(0)
	assert_ne(group.layers & SceneLightingSpec.SHADOW_CASTER_LAYER, 0)
	assert_ne(group.layers & 1, 0, "the default layer stays")
	var sky: MeshInstance3D = instance.get_node("SkyLand")
	assert_eq(sky.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var material: ShaderMaterial = sky.get_surface_override_material(0)
	assert_eq(material.shader.resource_path, MapShaders.sky_shader_path())
	var tiles: Texture2DArray = material.get_shader_parameter("tiles")
	assert_same(tiles, instance.source.sky_tiles)
	assert_true(_unset(material, "pixel_scale"), "no atlas uniforms")
	instance.free()


func test_sky_samples_a_tile_array() -> void:
	var scene: MapSceneData = _rich_scene()
	scene.sky_land.dimensions = Vector2i(3, 1)
	scene.sky_land.texture_ids = PackedInt32Array([1, 0, 1])
	scene.sky_land.rotations = PackedInt32Array([0, 1, 2])
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.diagnostics.is_empty(), ", ".join(built.diagnostics))
	assert_not_null(built.sky_tiles)
	assert_eq(built.sky_tiles.get_layers(), 2, "one layer per distinct tile texture")
	var narrow := Image.create(9, 6, false, Image.FORMAT_RGBA8)
	scene.preferred.images[0].texture = ImageTexture.create_from_image(narrow)
	var mismatched: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(Array(mismatched.diagnostics).any(func(line: String) -> bool: return line.contains("Sky tile layer 1 (texture 100)")),
		"first-seen texture 101 takes layer 0, so 100 is layer 1")
	var arrays: Array = built.sky_mesh.surface_get_arrays(0)
	var slots: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(slots.size(), 18)
	for corner: int in slots.size():
		var expected: float = 1.0 if corner >= 6 and corner < 12 else 0.0
		assert_eq(slots[corner].x, expected, "corner %d layer" % corner)
	assert_eq(uvs.slice(0, 6), PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(0, 4), Vector2(8, 0),
		Vector2(8, 4), Vector2(0, 4)]), "image-relative pixels without the page origin")
	var material: ShaderMaterial = built.sky_mesh.surface_get_material(0)
	var padding: Vector2 = material.get_shader_parameter("tile_padding")
	var padded_size: Vector2 = material.get_shader_parameter("tile_padded_size")
	assert_eq(padding, Vector2(1, 1))
	assert_eq(padded_size, Vector2(10, 6))


func test_sky_rotations_camera_translation_and_fixed_height() -> void:
	var scene: MapSceneData = _sky_scene(1)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_not_null(built.sky_mesh)
	var arrays: Array = built.sky_mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(positions[0], Vector3(-2, -24, -2))
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[0], Vector2(0, 4), "rotation 1 puts the image's bottom-left corner first")
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color8(16, 32, 48))
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_camera_presentation(Vector3(256, 512, 768))
	var sky_node: MeshInstance3D = instance.get_child(instance.get_child_count() - 1)
	assert_eq(sky_node.position, Vector3(1, -2, -3))
	instance.set_camera_presentation(Vector3(256.5, 512.25, 768.75))
	assert_eq(sky_node.position, Vector3(256.5, -512.25, -768.75) / 256.0)
	instance.set_tick(0)
	var drift: Vector3 = Vector3(instance.sky.translation())
	assert_eq(sky_node.position, Vector3(256.5 + drift.x, -512.25 - drift.y, -768.75 - drift.z) / 256.0)
	instance.free()


func test_committed_sky_drift_replaces_the_internal_clock() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_sky_scene(0))
	var instance: MapMesh.Instance = built.create_instance()
	var sky_node: MeshInstance3D = instance.get_child(instance.get_child_count() - 1)
	instance.set_camera_presentation(Vector3(256, 512, 768))
	instance.set_sky_drift(Vector3(12.5, 0, -3))
	assert_eq(sky_node.position, Vector3(268.5, -512, -765) / 256.0)
	instance.set_tick(300)
	for tick: int in 4:
		instance.step()
	assert_eq(instance.sky.tick, -1, "the internal drift clock stays stopped")
	assert_eq(instance.tick, 304)
	assert_eq(sky_node.position, Vector3(268.5, -512, -765) / 256.0)
	instance.set_camera_presentation(Vector3(0, 0, 0))
	assert_eq(sky_node.position, Vector3(12.5, 0, 3) / 256.0)
	instance.free()


func _unset(material: ShaderMaterial, parameter: String) -> bool:
	var value: Variant = material.get_shader_parameter(parameter)
	return typeof(value) == TYPE_NIL


func _scene() -> MapSceneData:
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.vertices = [Vector3i(0, 0, 256), Vector3i(256, 0, 256),
		Vector3i(0, 0, 0), Vector3i(256, 0, 0)]
	scene.map.group_size = Vector2i(256, 256)
	scene.map.polygons.append(_quad(0, 3))
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	scene.map.groups.append(group)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 100, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(pixels))
	var second: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 101, 0, SyntheticVlo.abgr(pixels))
	second.vram_y = 256
	scene.preferred = SyntheticVlo.bank([spec, second])
	scene.library.add_bank(scene.preferred)
	scene.remap = TextureRemap.new()
	scene.remap.texture_ids = PackedInt32Array([100, 101])
	return scene


func _rich_scene() -> MapSceneData:
	var scene: MapSceneData = _scene()
	scene.map.vertices.append_array([Vector3i(0, -256, 512), Vector3i(256, -256, 512)])
	var slope: MapPolygon = _quad(1, 7)
	slope.vertex_indices = PackedInt32Array([4, 5, 0, 1])
	slope.colors = PackedColorArray([Color8(10, 20, 30), Color8(40, 50, 60), Color8(70, 80, 90), Color8(100, 110, 120)])
	scene.map.polygons.append(slope)
	var flat := MapPolygon.new()
	flat.type_index = 4
	flat.vertex_indices = PackedInt32Array([0, 2, 4])
	flat.colors = PackedColorArray([Color8(10, 20, 30), Color8(40, 50, 60), Color8(70, 80, 90)])
	scene.map.polygons.append(flat)
	var animated: MapPolygon = _quad(0, 3)
	animated.flags = 1
	scene.map.polygons.append(animated)
	scene.map.groups[0].polygon_indices = PackedInt32Array([0, 1, 2, 3])
	var track := MapAnimation.new()
	track.type = 3
	track.delta_v = 1
	track.uv_frame_count = 4
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([3])
	scene.map.animations.append(track)
	scene.sky_land = SkyLandFile.new()
	scene.sky_land.dimensions = Vector2i(2, 1)
	scene.sky_land.texture_ids = PackedInt32Array([0, 1])
	scene.sky_land.rotations = PackedInt32Array([1, 2])
	scene.sky_remap = scene.remap
	scene.level = 43
	return scene


func _sky_scene(rotation: int) -> MapSceneData:
	var scene: MapSceneData = _scene()
	scene.sky_land = SkyLandFile.new()
	scene.sky_land.dimensions = Vector2i(1, 1)
	scene.sky_land.texture_ids = PackedInt32Array([0])
	scene.sky_land.rotations = PackedInt32Array([rotation])
	scene.sky_remap = scene.remap
	scene.level = 43
	return scene


func _quad(texture: int, type_index: int) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = type_index
	polygon.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	polygon.texture_id = texture
	polygon.visible = true
	return polygon
