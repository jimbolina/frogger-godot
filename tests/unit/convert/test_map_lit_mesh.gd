extends GutTest
## Modern-profile map meshes: shared arrays, per-image lit materials and instance behaviour.

class ModernCatalog extends AssetCatalog:
	func rendering_profile() -> RenderingProfile:
		return RenderingProfile.modern()


class ModernUpscaledCatalog extends ModernCatalog:
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


func test_arrays_match_across_profiles_and_carry_normals() -> void:
	var retail: MapMesh = MapMeshBuilder.new().build(_rich_scene(false))
	var modern: MapMesh = MapMeshBuilder.new().build(_rich_scene(true))
	assert_false(retail.modern)
	assert_true(modern.modern)
	assert_eq(modern.groups.size(), retail.groups.size())
	var compared: int = 0
	for group: int in retail.groups.size():
		assert_eq(modern.groups[group].get_surface_count(), retail.groups[group].get_surface_count())
		for surface: int in retail.groups[group].get_surface_count():
			assert_eq(modern.groups[group].surface_get_format(surface), retail.groups[group].surface_get_format(surface))
			assert_true(retail.groups[group].surface_get_format(surface) & Mesh.ARRAY_FORMAT_NORMAL != 0)
			var expected: Array = retail.groups[group].surface_get_arrays(surface)
			var actual: Array = modern.groups[group].surface_get_arrays(surface)
			for kind: int in Mesh.ARRAY_MAX:
				assert_eq(var_to_str(actual[kind]), var_to_str(expected[kind]), "group %d surface %d array %d" % [group, surface, kind])
			compared += 1
	assert_eq(compared, 4, "floor, slope, animated and untextured surfaces")
	var floor_normals: PackedVector3Array = retail.groups[0].surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal: Vector3 in floor_normals:
		assert_almost_eq(normal, Vector3.UP, Vector3.ONE * 0.001)
	assert_eq(var_to_str(modern.sky_mesh.surface_get_arrays(0)), var_to_str(retail.sky_mesh.surface_get_arrays(0)))
	var sky_custom: PackedFloat32Array = retail.sky_mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	var sky_ranks: PackedVector2Array = retail.sky_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	for corner: int in sky_ranks.size():
		assert_eq(sky_custom[corner * 4], sky_ranks[corner].x, "the sky page slot also sits in CUSTOM0.x")
		assert_eq(sky_custom[corner * 4 + 1], 0.0)
	assert_eq(sky_custom[6 * 4], 1.0, "the second tile's page has the second atlas slot")


func test_modern_material_binds_the_padded_image_texture() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_scene())
	var material: ShaderMaterial = built.groups[0].surface_get_material(0)
	assert_eq(material.shader.resource_path, MapLitShaders.shader_path(ModelShaders.Blend.OPAQUE, false))
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
	assert_true(_unset(material, "pixel_scale"), "no page uniforms")
	assert_true(_unset(material, "texel_inset"))


func test_modern_build_needs_no_page_set() -> void:
	var scene: MapSceneData = _scene()
	assert_null(scene.page_set)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.diagnostics.is_empty(), ", ".join(built.diagnostics))
	assert_eq(scene.texture_pages.cached_texture_count(), 0)
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	var missing: bool = material.get_shader_parameter("missing_image")
	assert_false(missing)
	instance.free()


func test_x4_counterpart_samples_linearly() -> void:
	var scene: MapSceneData = _scene()
	var catalog := ModernUpscaledCatalog.new()
	scene.library.catalog = catalog
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
	assert_eq(prepared.shader.resource_path, MapLitShaders.shader_path(ModelShaders.Blend.OPAQUE, false),
		"filtering changes a uniform, not the variant")
	instance.free()


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
		assert_eq(material.shader.resource_path, MapLitShaders.shader_path(blend, far), "flags %d" % flags)
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
	assert_eq(material.shader.resource_path, MapLitShaders.shader_path(ModelShaders.Blend.ADD, false))


func test_cave_surfaces_draw_black_and_ignore_the_cave_ramp() -> void:
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
	instance.set_cave_frog(Vector3i(5, 6, 7))
	instance.set_cave_radii(10, 20)
	instance.set_vertex_tint(0.75)
	var node: MeshInstance3D = instance.get_child(0)
	var seen: int = 0
	for surface: int in node.mesh.get_surface_count():
		var material: ShaderMaterial = node.get_surface_override_material(surface)
		var spec: MapMesh.Surface = built.surface_specs[0][surface]
		var cave: bool = spec.cave
		var tint: float = material.get_shader_parameter("vertex_tint")
		var wrap: float = material.get_shader_parameter("omni_wrap")
		assert_eq(tint, 0.0 if cave else 0.75)
		assert_eq(wrap, 1.0 if cave else 0.0)
		for parameter: String in ["cave_enabled", "cave_frog", "cave_min_r2", "cave_max_r2", "reference_projection"]:
			assert_true(_unset(material, parameter), parameter)
		seen += 1
	assert_eq(seen, 2)
	assert_true(instance._cave_materials.is_empty())
	instance.free()


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
		assert_almost_eq(MapLitShaders.normalised_uv(corners[0], image, offset), low, Vector2.ONE * 0.0001)
		assert_almost_eq(MapLitShaders.normalised_uv(corners[4], image, offset), high, Vector2.ONE * 0.0001)
	assert_eq(MapLitShaders.normalised_uv(Vector2(255, 0), image), Vector2(0, 1) / Vector2(10, 6),
		"byte wrap lands on the first padding column")
	assert_eq(MapLitShaders.normalised_uv(Vector2(8, 4), image), Vector2(9, 5) / Vector2(10, 6),
		"u == width samples the first right padding column")
	instance.free()


func test_reference_projection_is_a_no_op_with_a_diagnostic() -> void:
	var instance: MapMesh.Instance = MapMeshBuilder.new().build(_scene()).create_instance()
	instance.set_tick(0)
	instance.set_reference_projection(true)
	instance.set_reference_projection(true)
	assert_false(instance.reference_projection)
	assert_eq(instance.diagnostics.count(MapMesh.Instance.MODERN_REFERENCE_DIAGNOSTIC), 1)
	var node: MeshInstance3D = instance.get_child(0)
	var material: ShaderMaterial = node.get_surface_override_material(0)
	assert_true(_unset(material, "reference_projection"))
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


func test_groups_cast_shadows_and_the_sky_does_not() -> void:
	var instance: MapMesh.Instance = MapMeshBuilder.new().build(_rich_scene(true)).create_instance()
	var group: MeshInstance3D = instance.get_child(0)
	assert_ne(group.layers & SceneLightingSpec.SHADOW_CASTER_LAYER, 0)
	assert_ne(group.layers & 1, 0, "the default layer stays")
	var sky: MeshInstance3D = instance.get_node("SkyLand")
	assert_eq(sky.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var material: ShaderMaterial = sky.get_surface_override_material(0)
	assert_eq(material.shader.resource_path, MapLitShaders.sky_shader_path())
	var atlas: Texture2D = material.get_shader_parameter("image_nearest")
	assert_same(atlas, instance.source.sky_atlas)
	var pixel_scale: Vector2 = material.get_shader_parameter("pixel_scale")
	assert_eq(pixel_scale, Vector2(1.0 / 256.0, 1.0 / (258.0 * 2.0)))
	instance.free()
	var retail: MapMesh.Instance = MapMeshBuilder.new().build(_rich_scene(false)).create_instance()
	group = retail.get_child(0)
	assert_eq(group.layers & SceneLightingSpec.SHADOW_CASTER_LAYER, 0, "retail groups are unchanged")
	sky = retail.get_node("SkyLand")
	assert_eq(sky.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	material = sky.get_surface_override_material(0)
	assert_eq(material.shader.resource_path, MapShaders.sky_shader_path(false))
	retail.free()


func _unset(material: ShaderMaterial, parameter: String) -> bool:
	var value: Variant = material.get_shader_parameter(parameter)
	return typeof(value) == TYPE_NIL


func _scene() -> MapSceneData:
	var scene := MapSceneData.new()
	scene.library.catalog = ModernCatalog.new()
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


func _rich_scene(modern: bool) -> MapSceneData:
	var scene: MapSceneData = _scene()
	if not modern:
		scene.library.catalog = null
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
	var banks: Array[VloFile] = [scene.preferred]
	scene.page_set = SyntheticVlo.page_set(banks, true, PackedInt32Array([0, 1]))
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
