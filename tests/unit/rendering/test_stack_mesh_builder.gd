extends GutTest
## Stack box meshes follow SelectCreateMOF's faces, slice UVs and normals; boxes are lit and tinted per instance.

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")


func _layout() -> StackLayout:
	return StackLayout.create(StackLayoutTest.retail_stack())


func _surface(mesh: ArrayMesh, surface: int) -> Array:
	return mesh.surface_get_arrays(surface)


func test_side_region_is_the_rows_strip() -> void:
	assert_eq(StackMeshBuilder.side_region(64, 1, 4), Rect2(0.0, 0.25, 1.0, 0.25))
	assert_eq(StackMeshBuilder.side_region(30, 2, 4), Rect2(0.0, 14.0 / 30.0, 1.0, 7.0 / 30.0), "integer strip height")
	assert_eq(StackMeshBuilder.side_region(0, 1, 4), StackMeshBuilder.FULL_REGION)


func test_row_box_has_world_faces_then_end_face() -> void:
	var layout: StackLayout = _layout()
	var mesh: ArrayMesh = StackMeshBuilder.row_mesh(layout, 0, 64, 0, 5)
	assert_eq(mesh.get_surface_count(), 2)
	var world: Array = _surface(mesh, 0)
	var end: Array = _surface(mesh, 1)
	var positions: PackedVector3Array = world[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = world[Mesh.ARRAY_INDEX]
	var end_positions: PackedVector3Array = end[Mesh.ARRAY_VERTEX]
	assert_eq(positions.size(), 20)
	assert_eq(indices.size(), 30)
	assert_eq(end_positions.size(), 4)
	var vertices: Array[Vector3i] = layout.row_vertices(0)
	var mof: PackedInt32Array = StackLayout.face_indices(0)
	for corner: int in 4:
		var expected: Vector3i = vertices[mof[corner]]
		assert_eq(positions[corner], GameSpace.position(expected.x, expected.y, expected.z))


func test_side_face_shows_the_strip_upright() -> void:
	var mesh: ArrayMesh = StackMeshBuilder.row_mesh(_layout(), 1, 64, 1, 4)
	var uvs: PackedVector2Array = _surface(mesh, 0)[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs.slice(0, 4), PackedVector2Array([Vector2(0, 0.25), Vector2(1, 0.25), Vector2(1, 0.5), Vector2(0, 0.5)]))
	assert_eq(uvs.slice(16, 20), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), "face 4 shows the whole image")


func test_spin_box_turns_the_level_picture() -> void:
	var layout: StackLayout = _layout()
	var mesh: ArrayMesh = StackMeshBuilder.spin_mesh(layout, 0, 64, 0, 5)
	var end: Array = _surface(mesh, 1)
	var uvs: PackedVector2Array = end[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs, PackedVector2Array([Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]))
	var positions: PackedVector3Array = end[Mesh.ARRAY_VERTEX]
	var top: Vector3 = GameSpace.position(0, -layout.y_size(0), 0)
	assert_almost_eq(absf(positions[0].y), absf(top.y), 0.0001, "centred on the spin frame")


func test_front_faces_wind_against_the_inward_normals() -> void:
	var layout: StackLayout = _layout()
	var mesh: ArrayMesh = StackMeshBuilder.row_mesh(layout, 3, 64, 3, 5)
	var box_centre: Vector3 = GameSpace.position(0, layout.y_position(3), 0)
	for surface: int in mesh.get_surface_count():
		var arrays: Array = _surface(mesh, surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for first: int in range(0, indices.size(), 3):
			var a: Vector3 = positions[indices[first]]
			var b: Vector3 = positions[indices[first + 1]]
			var c: Vector3 = positions[indices[first + 2]]
			var centre: Vector3 = (a + b + c) / 3.0
			assert_lt((centre - box_centre).dot(normals[indices[first]]), 0.0, "normal points into the box")
			assert_gt((b - a).cross(c - a).dot(normals[indices[first]]), 0.0, "clockwise from outside")


func test_gold_frog_quad_keeps_gpu_corner_uvs() -> void:
	var corners: Array[Vector3i] = _layout().gold_frog_quad(0)
	var mesh: ArrayMesh = StackMeshBuilder.quad_mesh(corners)
	var arrays: Array = _surface(mesh, 0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for gpu: int in 4:
		var at: int = positions.find(GameSpace.position(corners[gpu].x, corners[gpu].y, corners[gpu].z))
		assert_eq(uvs[at], StackMeshBuilder.corner_uv(gpu, StackMeshBuilder.FULL_REGION))
	assert_eq(StackMeshBuilder.quad_mesh([]).get_surface_count(), 0)


func test_box_material_draws_through_the_lit_shaders() -> void:
	var flat: ShaderMaterial = StackMeshBuilder.box_material(null, Vector2(1.0, 0.9))
	assert_eq(flat.shader.resource_path, ModelShaders.SHADER_DIR.path_join("model_flat_opaque.gdshader"))
	assert_false(flat.shader.code.contains("unshaded"), "the scene lights it")
	var projection: Vector2 = flat.get_shader_parameter("projection_scale")
	assert_eq(projection, Vector2(1.0, 0.9))
	var image := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var textured: ShaderMaterial = StackMeshBuilder.box_material(image, Vector2.ONE, true)
	assert_eq(textured.shader.resource_path, ModelShaders.SHADER_DIR.path_join("model_textured_opaque_linear.gdshader"))
	var bound: Texture2D = textured.get_shader_parameter("image")
	assert_eq(bound, image)
	assert_eq(StackMeshBuilder.box_material(image).shader.resource_path, ModelShaders.SHADER_DIR.path_join("model_textured_opaque.gdshader"))


func test_gold_frog_quad_material_is_unlit_two_sided_and_nearer() -> void:
	var image := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var quad: ShaderMaterial = StackMeshBuilder.quad_material(image, Vector2(1.0, 0.9))
	assert_eq(quad.shader.resource_path, ModelShaders.SHADER_DIR.path_join("model_unlit_textured_opaque_two_sided.gdshader"))
	var bias: float = quad.get_shader_parameter("depth_bias")
	assert_eq(bias, StackMeshBuilder.GOLD_FROG_DEPTH_BIAS)
	var linear: ShaderMaterial = StackMeshBuilder.quad_material(image, Vector2.ONE, true)
	assert_eq(linear.shader.resource_path, ModelShaders.SHADER_DIR.path_join("model_unlit_textured_opaque_linear_two_sided.gdshader"))


func test_instance_tint_of_a_dark_row_scales_the_lit_box() -> void:
	var box := MeshInstance3D.new()
	StackMeshBuilder.set_instance_tint(box, StackSelector.DARK_COLOUR)
	var scale: Vector3 = box.get_instance_shader_parameter(ModelShaders.TINT_SCALE)
	var ambient: Color = box.get_instance_shader_parameter(ModelShaders.TINT_AMBIENT)
	assert_almost_eq(scale, Vector3.ONE * pow(0.5, SceneLightingBuilder.GAMMA), Vector3.ONE * 1e-6)
	assert_eq(ambient, Color(0.0, 0.0, 0.0, 0.0), "no custom ambient")
	StackMeshBuilder.set_instance_tint(box, StackSelector.LIGHT_COLOUR)
	scale = box.get_instance_shader_parameter(ModelShaders.TINT_SCALE)
	assert_eq(scale, Vector3.ONE, "the neutral colour leaves the box as lit")
	box.free()


func test_surface_mesh_keeps_one_surface() -> void:
	var mesh: ArrayMesh = StackMeshBuilder.spin_mesh(_layout(), 0, 64, 0, 5)
	var picture: ArrayMesh = StackMeshBuilder.surface_mesh(mesh, 1)
	assert_eq(picture.get_surface_count(), 1)
	var picture_uvs: PackedVector2Array = _surface(picture, 0)[Mesh.ARRAY_TEX_UV]
	var end_uvs: PackedVector2Array = _surface(mesh, 1)[Mesh.ARRAY_TEX_UV]
	var picture_positions: PackedVector3Array = _surface(picture, 0)[Mesh.ARRAY_VERTEX]
	var end_positions: PackedVector3Array = _surface(mesh, 1)[Mesh.ARRAY_VERTEX]
	assert_eq(picture_uvs, end_uvs)
	assert_eq(picture_positions, end_positions)
	assert_eq(StackMeshBuilder.surface_mesh(mesh, 0).get_surface_count(), 1)
