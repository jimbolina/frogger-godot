extends GutTest
## Front-end water meshes follow HSInitialiseWater's grids and texture mapping, move only their
## heights, and draw behind everything with the source's blends.


func test_water_shares_grid_vertices_with_spread_texture() -> void:
	var mesh: MenuWaterMesh = MenuWaterMesh.create()
	var arrays: Array = mesh.water.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(positions.size(), 15 * 17)
	assert_eq(indices.size(), 14 * 16 * 6)
	assert_eq(uvs[0], Vector2.ZERO)
	assert_eq(uvs[uvs.size() - 1], Vector2.ONE)
	assert_almost_eq(uvs[15 + 1], Vector2(1.0 / 14.0, 1.0 / 16.0), Vector2.ONE * 0.000001)
	assert_eq(positions[0], GameSpace.position(-4032, 0, 4608), "frame 0 starts flat at the far left corner")


func test_grid_indices_split_each_quad_like_model_quads() -> void:
	var indices: PackedInt32Array = MenuWaterMesh.grid_indices(14, 16)
	assert_eq(indices.slice(0, 6), PackedInt32Array([0, 1, 15, 1, 16, 15]))
	var last: PackedInt32Array = indices.slice(indices.size() - 6)
	var corners: PackedInt32Array = MenuWater.quad_vertices(13, 15, 14)
	assert_eq(last, PackedInt32Array([corners[0], corners[1], corners[2], corners[1], corners[3], corners[2]]))


func test_riverbed_quads_hold_the_whole_texture_flipped_on_even_rows() -> void:
	var mesh: MenuWaterMesh = MenuWaterMesh.create()
	var arrays: Array = mesh.riverbed.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(positions.size(), 14 * 16 * 4)
	assert_eq(uvs.slice(0, 4), PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]), "row 0 is even")
	var odd: int = 14 * 4
	assert_eq(uvs.slice(odd, odd + 4), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	assert_eq(positions[odd], GameSpace.position(-4032, 0, 4032))
	for at: Vector3 in positions:
		assert_eq(at.y, 0.0)


func test_set_heights_moves_only_vertex_heights() -> void:
	var mesh: MenuWaterMesh = MenuWaterMesh.create()
	var water: ArrayMesh = mesh.water
	var heights := PackedFloat32Array()
	for value: int in MenuWater.heights(7):
		heights.append(value + 0.5)
	mesh.set_heights(heights)
	assert_same(mesh.water, water)
	assert_eq(mesh.water.get_surface_count(), 1)
	assert_eq(mesh.water_positions.size(), 15 * 17)
	var grid: Array[Vector3i] = MenuWater.water_vertices()
	for index: int in [0, 20, 254]:
		var expected: Vector3 = Vector3(grid[index].x, -heights[index], -grid[index].z) / GameSpace.UNITS_PER_SQUARE
		assert_almost_eq(mesh.water_positions[index], expected, Vector3.ONE * 0.000001)
	assert_true(mesh.water.custom_aabb.has_point(Vector3(0.0, 144.0 / GameSpace.UNITS_PER_SQUARE, 0.0)))


func test_colours_are_the_prim_colours() -> void:
	var mesh: MenuWaterMesh = MenuWaterMesh.create()
	var water: PackedColorArray = mesh.water.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var bed: PackedColorArray = mesh.riverbed.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(water[0], Color8(0x60, 0x60, 0x40))
	assert_eq(bed[bed.size() - 1], Color8(0x30, 0x30, 0x30))


func test_materials_blend_and_sit_behind_everything() -> void:
	var image := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var water: ShaderMaterial = MenuWaterMesh.water_material(image, Vector2(1.0, 0.9))
	var bed: ShaderMaterial = MenuWaterMesh.riverbed_material(image)
	assert_string_contains(water.shader.code, "blend_add")
	assert_string_contains(water.shader.code, "cull_disabled")
	assert_string_contains(water.shader.code, "depth_draw_never")
	assert_string_contains(bed.shader.code, "blend_mix")
	assert_string_contains(bed.shader.code, "depth_draw_opaque")
	assert_string_contains(water.shader.code, "POSITION.z = background_clip.z")
	var water_depth: float = water.get_shader_parameter("background_depth")
	var bed_depth: float = bed.get_shader_parameter("background_depth")
	var scale: Vector2 = water.get_shader_parameter("projection_scale")
	var shown: Texture2D = water.get_shader_parameter("image")
	assert_eq(water_depth, MenuWaterMesh.WATER_DEPTH)
	assert_eq(bed_depth, MenuWaterMesh.RIVERBED_DEPTH)
	assert_eq(scale, Vector2(1.0, 0.9))
	assert_same(shown, image)
	assert_same(MenuWaterMesh.water_material(image).shader, water.shader, "shaders are shared")


func test_shader_code_keeps_the_unlit_model_recipe() -> void:
	var code: String = MenuWaterMesh.shader_code(true, ModelShaders.Blend.ADD)
	assert_string_contains(code, "render_mode unshaded, ")
	assert_false(code.contains("#include"), "the include is written out")
	assert_string_contains(code, "min(COLOR.rgb * 2.0, vec3(1.0))")
	assert_string_contains(code, "ALBEDO = to_linear(")
	assert_string_contains(code, "discard;")
	assert_string_contains(code, "uniform float background_depth")
	assert_lt(code.find("POSITION.xy *= projection_scale;"), code.find("background_clip"))
	assert_lt(code.find("uniform float depth_bias"), code.find("uniform float background_depth"))
