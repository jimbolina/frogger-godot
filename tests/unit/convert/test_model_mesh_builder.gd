extends GutTest
## Turning models into Godot meshes: positions, corner order, texture
## coordinates, surfaces and shaders. Needs no game files.


func _bank(flags: int = 0, blend_mode: int = 0) -> VloFile:
	var pixels: Array[int] = []
	for _i: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 7, flags, SyntheticVlo.abgr(pixels))
	spec.blend_mode = blend_mode
	var bank: VloFile = VloFile.parse(SyntheticVlo.build_vlo([spec]))
	assert_eq(bank.error, "")
	return bank


func _build(parts: Array[SyntheticMof.Part], bank: VloFile = null) -> ModelMesh:
	var file: MofFile = MofFile.parse(SyntheticMof.build_static(parts))
	assert_eq(file.error, "")
	var library := TextureLibrary.new()
	if bank != null:
		library.add_bank(bank, "bank")
	return ModelMeshBuilder.new(library, bank).build(file.static_models[0])


func _vertices(mesh: ArrayMesh, surface: int = 0) -> PackedVector3Array:
	var found: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	return found


func test_game_space() -> void:
	assert_eq(GameSpace.position(256, 0, 0), Vector3(1, 0, 0))
	assert_eq(GameSpace.position(0, -512, 0), Vector3(0, 2, 0), "up is minus y in the game")
	assert_eq(GameSpace.position(0, 0, 128), Vector3(0, 0, -0.5))
	assert_eq(GameSpace.normal(0, -4096, 0), Vector3(0, 1, 0))
	assert_eq(GameSpace.to_game(Vector3(1, 2, -0.5)), Vector3i(256, -512, 128))


func test_a_quad_becomes_two_triangles_in_the_stored_direction() -> void:
	assert_eq(ModelMeshBuilder.triangle_corners(4), PackedInt32Array([0, 1, 3, 1, 2, 3]))
	assert_eq(ModelMeshBuilder.triangle_corners(3), PackedInt32Array([0, 1, 2]))
	assert_eq(ModelMeshBuilder.triangle_corners(2), PackedInt32Array())
	var built: ModelMesh = _build([SyntheticMof.square(MofPolygonType.F4, Color8(10, 20, 30))])
	assert_eq(built.triangle_count, 2)
	assert_eq(built.surface_count, 1)
	var corners: PackedVector3Array = _vertices(built.part_meshes[0])
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(1, -1, 0)
	var d := Vector3(0, -1, 0)
	assert_eq(corners, PackedVector3Array([a, b, d, b, c, d]))
	assert_eq(built.bounds, AABB(Vector3(0, -1, 0), Vector3(1, 1, 0)))
	var around: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
	assert_lt(around.z, 0.0, "clockwise seen from plus z")
	var colours: PackedColorArray = built.part_meshes[0].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0].r8, 10)
	assert_eq(colours[5].b8, 30)
	var normals: PackedVector3Array = built.part_meshes[0].surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_almost_eq(normals[0], Vector3(0, 0, 1), Vector3.ONE * 0.001, "the stored normal, towards the viewer")


func test_texture_coordinates_cover_the_in_game_part_of_the_image() -> void:
	var bank: VloFile = _bank()
	var image: VloImage = bank.images[0]
	assert_eq(ModelMeshBuilder.texture_coordinate(image, 0, 0), Vector2(1.0 / 10.0, 1.0 / 6.0))
	assert_eq(ModelMeshBuilder.texture_coordinate(image, 255, 255), Vector2(9.0 / 10.0, 5.0 / 6.0))
	assert_eq(ModelMeshBuilder.texture_coordinate(image, 128, 128), Vector2(5.0 / 10.0, 3.0 / 6.0), "whole pixels")
	var built: ModelMesh = _build([SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)], bank)
	var uvs: PackedVector2Array = built.part_meshes[0].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[0], Vector2(0.1, 1.0 / 6.0), "corner 0")
	assert_eq(uvs[2], Vector2(0.1, 5.0 / 6.0), "corner 3")
	assert_eq(uvs[4], Vector2(0.9, 5.0 / 6.0), "corner 2")
	var material := built.part_meshes[0].surface_get_material(0) as ShaderMaterial
	var shown: Texture2D = material.get_shader_parameter("image")
	assert_not_null(shown)


func test_surfaces_are_split_by_texture_and_by_how_they_are_drawn() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	part.polygons.append(SyntheticMof.polygon(MofPolygonType.F3, [0, 1, 2], [0]))
	part.polygons.append(SyntheticMof.polygon(MofPolygonType.G3, [0, 2, 3], [0, 0, 0]))
	part.polygons.append(SyntheticMof.polygon(MofPolygonType.FT3, [0, 1, 2], [0], Color8(128, 128, 128), 7, [0, 0, 255, 0, 255, 255]))
	var built: ModelMesh = _build([part], _bank())
	assert_eq(built.surface_count, 2, "plain and textured")
	assert_eq(built.triangle_count, 5)
	assert_eq(built.missing_image_ids.size(), 0)

	var translucent: ModelMesh = _build([SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)],
		_bank(VloImage.FLAG_TRANSLUCENT, 1))
	var material := translucent.part_meshes[0].surface_get_material(0) as ShaderMaterial
	assert_string_contains(material.shader.code, "blend_add")
	assert_string_contains(material.shader.code, "depth_draw_never")


func test_a_texture_nobody_has_gives_an_untextured_polygon() -> void:
	var built: ModelMesh = _build([SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 99)], _bank())
	assert_eq(built.missing_image_ids, PackedInt32Array([99]))
	assert_eq(built.triangle_count, 2)
	var material := built.part_meshes[0].surface_get_material(0) as ShaderMaterial
	assert_false(material.shader.code.contains("sampler2D image"))


func test_parts_stay_apart_and_empty_ones_have_no_mesh() -> void:
	var empty: SyntheticMof.Part = SyntheticMof.part([0, 0, 0], [0, 0, -4096], [])
	var built: ModelMesh = _build([SyntheticMof.square(MofPolygonType.F4), empty, SyntheticMof.square(MofPolygonType.G4)])
	assert_eq(built.part_meshes.size(), 3)
	assert_not_null(built.part_meshes[0])
	assert_null(built.part_meshes[1])
	assert_not_null(built.part_meshes[2])
	assert_false(built.is_empty())


func test_shader_choices() -> void:
	var plain: String = ModelShaders.shader_code(false, ModelShaders.Blend.OPAQUE, false, false)
	assert_string_contains(plain, "cull_back")
	assert_string_contains(plain, "depth_draw_opaque")
	assert_false(plain.contains("* 2.0"), "an untextured colour is not doubled")
	var textured: String = ModelShaders.shader_code(true, ModelShaders.Blend.OPAQUE, true, true)
	assert_string_contains(textured, "filter_linear")
	assert_string_contains(textured, "cull_disabled")
	assert_string_contains(textured, "COLOR.rgb * 2.0")
	assert_string_contains(textured, "discard")
	assert_string_contains(ModelShaders.shader_code(true, ModelShaders.Blend.AVERAGE, false, false), "ALPHA = 0.5")
	assert_string_contains(ModelShaders.shader_code(true, ModelShaders.Blend.SUBTRACT, false, false), "blend_sub")
	assert_string_contains(ModelShaders.shader_code(true, ModelShaders.Blend.ADD_QUARTER, false, false), "* 0.25")
	assert_eq(ModelShaders.blend_for_mode(0), ModelShaders.Blend.AVERAGE)
	assert_eq(ModelShaders.blend_for_mode(3), ModelShaders.Blend.ADD_QUARTER)
	assert_same(ModelShaders.shader(false, ModelShaders.Blend.OPAQUE, false, false),
		ModelShaders.shader(false, ModelShaders.Blend.OPAQUE, true, false), "filtering does not matter without a texture")
