extends GutTest
## Independent modern map and sky UV facts from synthetic C texture records
## through MapMeshBuilder, the modern instance, MapLitShaders and MapSkyTiles.

class ModernCatalog extends AssetCatalog:
	func rendering_profile() -> RenderingProfile:
		return RenderingProfile.modern()


const FACTS_PATH: String = "res://tests/golden/synthetic/map_modern_uv.json"

var _facts: Dictionary = {}
var _tolerance: float = 0.0


func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	_tolerance = _facts["tolerance"]


func test_schema() -> void:
	var schema: String = _facts["schema"]
	assert_eq(schema, "map-modern-uv-v1")
	var fixtures: Array = _facts["fixtures"]
	assert_eq(fixtures.size(), 7)


func test_map_fixtures_match_independent_facts() -> void:
	var checked: int = 0
	for fixture: Dictionary in _facts["fixtures"]:
		var kind: String = fixture["kind"]
		if kind == "map":
			_check_map(fixture)
			checked += 1
	assert_eq(checked, 6)


func test_sky_fixture_matches_independent_facts() -> void:
	var checked: int = 0
	for fixture: Dictionary in _facts["fixtures"]:
		var kind: String = fixture["kind"]
		if kind == "sky":
			_check_sky(fixture)
			checked += 1
	assert_eq(checked, 1)


func _check_map(fixture: Dictionary) -> void:
	var fixture_name: String = fixture["name"]
	var scene: MapSceneData = _scene(fixture)
	var rows: Array = fixture["polygons"]
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var corners: Array = row["corners"]
		var bytes: Array = row["uv_bytes"]
		var polygon := MapPolygon.new()
		polygon.type_index = 3
		polygon.visible = true
		polygon.texture_id = _int(row["texture"])
		polygon.flags = _int(row["flags"])
		polygon.colors = PackedColorArray([Color8(128, 128, 128)])
		for corner: int in 4:
			var position: Array = corners[corner]
			var uv: Array = bytes[corner]
			polygon.vertex_indices.append(scene.map.vertices.size())
			scene.map.vertices.append(Vector3i(_int(position[0]), _int(position[1]), _int(position[2])))
			polygon.uvs.append(Vector2(_float(uv[0]), _float(uv[1])) / 255.0)
		scene.map.polygons.append(polygon)
		var group := MapGroup.new()
		group.polygon_indices = PackedInt32Array([index])
		scene.map.groups.append(group)
	if fixture.has("animation"):
		var source: Dictionary = fixture["animation"]
		var track := MapAnimation.new()
		track.type = _int(source["type"])
		track.delta_u = _int(source["du"])
		track.delta_v = _int(source["dv"])
		track.uv_frame_count = _int(source["uv_duration"])
		track.frames_per_texture = _int(source["cel_period"])
		for cel: Variant in source["cels"]:
			track.texture_ids.append(_int(cel))
		track.target_polygon_indices = PackedInt32Array([_int(source["target"])])
		scene.map.animations.append(track)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.modern, fixture_name)
	assert_true(built.diagnostics.is_empty(), "%s: %s" % [fixture_name, ", ".join(built.diagnostics)])
	var instance: MapMesh.Instance = built.create_instance()
	var disagreements: int = 0
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var arrays: Array = built.groups[index].surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var node: MeshInstance3D = instance.get_child(index)
		for state: Dictionary in row["states"]:
			var tick: int = _int(state["tick"])
			var label: String = "%s polygon %d tick %d" % [fixture_name, index, tick]
			instance.set_tick(tick)
			if state.has("camera"):
				var camera: Array = state["camera"]
				instance.set_camera_presentation(Vector3(_float(camera[0]), _float(camera[1]), _float(camera[2])))
				label += " camera %s" % [camera]
			var material: ShaderMaterial = node.get_surface_override_material(0)
			var image: VloImage = _bound_image(scene, built, instance, index, state, label)
			_assert_material_image(material, image, label)
			var animated: bool = material.get_shader_parameter("animated")
			var environment: bool = material.get_shader_parameter("environment_uv")
			assert_eq(animated, state.has("offset"), label + " animated")
			assert_eq(environment, state.has("camera"), label + " environment")
			var expected_uvs: Array = state["uv"]
			var sampled: Array = state["sampled"]
			var texels: Array = state["retail_texel"]
			for vertex: int in uvs.size():
				var corner: int = MapMeshBuilder.triangle_corners(4)[vertex]
				var actual: Vector2
				if environment:
					var camera_game: Vector3 = material.get_shader_parameter("camera_game")
					actual = MapLitShaders.normalised_environment_uv(vertices[vertex] * Vector3(256.0, -256.0, -256.0),
						camera_game, image)
				elif animated:
					var offset: Vector2 = material.get_shader_parameter("animation_offset")
					actual = MapLitShaders.normalised_uv(uvs[vertex], image, offset)
				else:
					actual = MapLitShaders.normalised_uv(uvs[vertex], image)
				var corner_label: String = "%s corner %d" % [label, corner]
				_assert_pair(actual, expected_uvs[corner], corner_label + " uv")
				var repeated := Vector2(fposmod(actual.x, 1.0), fposmod(actual.y, 1.0))
				_assert_pair(repeated, sampled[corner], corner_label + " sampled")
				var texel: Array = texels[corner]
				var modern_texel := Vector2i(floori(repeated.x * image.padded_width + 1e-4),
					floori(repeated.y * image.padded_height + 1e-4))
				if modern_texel != Vector2i(_int(texel[0]), _int(texel[1])):
					disagreements += 1
	if fixture.has("divergence"):
		assert_gt(disagreements, 0, "%s shows its documented divergence" % fixture_name)
	else:
		assert_eq(disagreements, 0, "%s samples the texel retail's page held" % fixture_name)
	instance.free()


func _check_sky(fixture: Dictionary) -> void:
	var fixture_name: String = fixture["name"]
	var scene: MapSceneData = _scene(fixture)
	var dimensions: Array = fixture["dimensions"]
	var tiles: Array = fixture["tiles"]
	scene.level = 43
	scene.sky_land = SkyLandFile.new()
	scene.sky_land.dimensions = Vector2i(_int(dimensions[0]), _int(dimensions[1]))
	for tile: Dictionary in tiles:
		scene.sky_land.texture_ids.append(_int(tile["texture"]))
		scene.sky_land.rotations.append(_int(tile["rotation"]))
	scene.sky_remap = scene.remap
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	assert_true(built.diagnostics.is_empty(), "%s: %s" % [fixture_name, ", ".join(built.diagnostics)])
	assert_null(scene.page_set)
	assert_eq(built.sky_tiles.get_layers(), _int(fixture["layer_count"]), fixture_name + " layers")
	assert_eq(built.sky_mesh.get_surface_count(), 1, fixture_name + " one surface")
	var arrays: Array = built.sky_mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	assert_eq(uvs.size(), tiles.size() * 6, fixture_name + " vertices")
	for index: int in tiles.size():
		var tile: Dictionary = tiles[index]
		var image: VloImage = scene.library.image_for_id(scene.remap.global_id(_int(tile["texture"])), scene.preferred)
		var expected: Array = tile["uv"]
		for vertex: int in 6:
			var corner: int = MapMeshBuilder.triangle_corners(4)[vertex]
			var at: int = index * 6 + vertex
			var label: String = "%s tile %d corner %d" % [fixture_name, index, corner]
			assert_eq(int(custom[at * 4]), _int(tile["layer"]), label + " layer")
			_assert_pair(MapSkyTiles.layer_uv(uvs[at], image), expected[corner], label + " uv")


func _scene(fixture: Dictionary) -> MapSceneData:
	var scene := MapSceneData.new()
	scene.library.catalog = ModernCatalog.new()
	scene.map = MapFile.new()
	scene.map.group_size = Vector2i(256, 256)
	scene.remap = TextureRemap.new()
	var bank := VloFile.new()
	for row: Dictionary in fixture["images"]:
		var image := VloImage.new()
		image.index = bank.images.size()
		image.texture_id = _int(row["texture_id"])
		image.vram_x = _int(row["vram_x"])
		image.vram_y = _int(row["vram_y"])
		image.padded_width = _int(row["padded_width"])
		image.padded_height = _int(row["padded_height"])
		image.width = _int(row["width"])
		image.height = _int(row["height"])
		image.flags = _int(row["flags"])
		image.u = _int(row["u"])
		image.v = _int(row["v"])
		image.texture_page_word = image.page()
		var pixels := Image.create(image.padded_width, image.padded_height, false, Image.FORMAT_RGBA8)
		pixels.fill(Color8(40 + 20 * bank.images.size(), 120, 200))
		image.texture = ImageTexture.create_from_image(pixels)
		bank.images.append(image)
		scene.remap.texture_ids.append(image.texture_id)
	scene.preferred = bank
	scene.library.add_bank(bank)
	return scene


func _bound_image(scene: MapSceneData, built: MapMesh, instance: MapMesh.Instance, index: int,
		state: Dictionary, label: String) -> VloImage:
	if state.has("texture"):
		var expected: VloImage = scene.library.image_for_id(scene.remap.global_id(_int(state["texture"])), scene.preferred)
		var current: VloImage = scene.library.image_for_id(instance.animation.track_image_id(0), scene.preferred)
		assert_same(current, expected, label + " cel")
		var offset: Array = state["offset"]
		assert_eq(instance.animation.track_offset(0), Vector2i(_int(offset[0]), _int(offset[1])), label + " offset")
		return current
	var spec: MapMesh.Surface = built.surface_specs[index][0]
	return spec.image


func _assert_material_image(material: ShaderMaterial, image: VloImage, label: String) -> void:
	var origin: Vector2 = material.get_shader_parameter("image_origin")
	var padding: Vector2 = material.get_shader_parameter("image_padding")
	var padded_size: Vector2 = material.get_shader_parameter("image_padded_size")
	assert_eq(origin, Vector2(image.u, image.v), label + " origin")
	assert_eq(padding, Vector2(image.left_padding(), image.top_padding()), label + " padding")
	assert_eq(padded_size, Vector2(image.padded_width, image.padded_height), label + " padded size")


func _assert_pair(actual: Vector2, expected: Variant, label: String) -> void:
	var pair: Array = expected
	var target := Vector2(_float(pair[0]), _float(pair[1]))
	assert_true(absf(actual.x - target.x) <= _tolerance and absf(actual.y - target.y) <= _tolerance,
		"%s: %s against %s" % [label, actual, target])


func _float(value: Variant) -> float:
	var result: float = value
	return result


func _int(value: Variant) -> int:
	var result: float = value
	return roundi(result)
