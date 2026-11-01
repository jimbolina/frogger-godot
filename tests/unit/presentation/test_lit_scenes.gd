extends GutTest
## A level draws its terrain, frog and entities with the lit shaders under scene lights; a cave
## level draws under the cave omni light instead of the directional lights. The mapless sandbox
## draws its frog, entities and zone faces under the options lights.

var _data: ImportedAssets


func before_all() -> void:
	_data = ImportedAssets.open()


func after_all() -> void:
	_data.close()


func _open(data: ImportedAssets, level: String = "ORG1") -> GameplayScreen:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	assert_eq(screen.open_data(data, level), "")
	return screen


func _shader_paths(nodes: Array[MeshInstance3D]) -> Dictionary[String, bool]:
	var paths: Dictionary[String, bool] = {}
	for node: MeshInstance3D in nodes:
		if node == null or node.mesh == null:
			continue
		for surface: int in node.mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			paths[material.shader.resource_path if material != null and material.shader != null else "<none>"] = true
	return paths


func _terrain_nodes(screen: GameplayScreen) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for child: Node in screen._map_instance.get_children():
		if child is MeshInstance3D:
			nodes.append(child as MeshInstance3D)
	return nodes


func _model_nodes(screen: GameplayScreen) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	nodes.append_array(screen._frog_model.part_nodes)
	for model: AnimatedModelInstance in screen._entity_models:
		if model != null:
			nodes.append_array(model.part_nodes)
	return nodes


func _count(screen: GameplayScreen, type: String) -> int:
	return screen.find_children("*", type, true, false).size()


func _assert_all_lit(paths: Dictionary[String, bool], prefix: String, what: String) -> void:
	assert_false(paths.is_empty(), "%s draws surfaces" % what)
	for path: String in paths:
		assert_eq(path.get_base_dir(), ModelShaders.SHADER_DIR, "%s shader %s" % [what, path])
		assert_true(path.get_file().begins_with(prefix) and not path.get_file().begins_with(ModelShaders.UNLIT_PREFIX),
			"%s shader %s is lit" % [what, path])


func test_org1_is_lit_with_the_lit_shaders() -> void:
	assert_eq(_data.error, "")
	var note: String = _data.note_renderer(RenderingServer.get_current_rendering_method())
	assert_eq(_data.warnings, PackedStringArray([note]) if not note.is_empty() else PackedStringArray(), "only the renderer note is reported")
	var screen: GameplayScreen = _open(_data)
	assert_eq(_count(screen, "WorldEnvironment"), 1)
	var lights: Array[DirectionalLight3D] = screen.scene_lighting.light_nodes()
	assert_eq(_count(screen, "DirectionalLight3D"), lights.size())
	var casters: int = 0
	for light: DirectionalLight3D in lights:
		if light.shadow_enabled:
			casters += 1
	assert_eq(casters, 1, "one light casts the shadows")
	assert_not_null(screen.scene_lighting.environment)
	assert_ne(screen.scene_lighting.applied_ambient, Vector3.ONE)
	_assert_all_lit(_shader_paths(_terrain_nodes(screen)), "map_", "terrain")
	assert_gt(screen.entity_model_count(), 0)
	_assert_all_lit(_shader_paths(_model_nodes(screen)), "model_", "frog and entity part")
	screen.close_data()


func test_cav1_draws_under_the_cave_light() -> void:
	var screen: GameplayScreen = _open(_data, "CAV1")
	assert_true(screen._map_instance.source.scene.cave_enabled)
	screen.draw_state(1.0)
	var light: OmniLight3D = screen.scene_lighting.cave_light_node()
	assert_not_null(light)
	assert_eq(_count(screen, "OmniLight3D"), 1)
	assert_eq(_count(screen, "DirectionalLight3D"), 0)
	assert_almost_eq(screen.scene_lighting.environment.ambient_light_energy, CaveLightShape.CAVE_AMBIENT, 1e-6)
	if light != null:
		assert_gt(light.omni_range, 0.0)
		assert_gt(light.light_energy, 0.0)
	screen.close_data()


func test_sky1_draws_the_sky_from_a_tile_array() -> void:
	var screen: GameplayScreen = _open(_data, "SKY1")
	var sky: MeshInstance3D = screen._map_instance.get_node_or_null("SkyLand") as MeshInstance3D
	assert_not_null(sky)
	if sky != null:
		var material: ShaderMaterial = sky.get_active_material(0) as ShaderMaterial
		assert_not_null(material)
		if material != null:
			assert_true(material.get_shader_parameter("tiles") is Texture2DArray)
	screen.close_data()


func test_swp1_draws_reflective_water() -> void:
	var screen: GameplayScreen = _open(_data, "SWP1")
	var reflective: int = 0
	for node: MeshInstance3D in _terrain_nodes(screen):
		if node.mesh == null:
			continue
		for surface: int in node.mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			if material != null and is_equal_approx(_float(material.get_shader_parameter("reflection_emission")), MapMesh.Instance.WATER_REFLECTION):
				reflective += 1
	assert_gt(reflective, 0)
	screen.close_data()


func _float(value: Variant) -> float:
	if value is float:
		var result: float = value
		return result
	return 0.0


func _sandbox(data: ImportedAssets) -> SandboxScreen:
	var screen := SandboxScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	assert_eq(screen.open_sandbox(data), "")
	assert_eq(screen.load_preset("effects"), "")
	screen.draw_state(1.0)
	return screen


func _assert_zone_faces_lit(screen: SandboxScreen) -> void:
	var faces: int = 0
	for child: Node in screen._ground.get_children():
		var face: MeshInstance3D = child as MeshInstance3D
		if face == null:
			continue
		var material: ShaderMaterial = face.material_override as ShaderMaterial
		assert_not_null(material, String(face.name))
		if material != null:
			assert_eq(material.shader.resource_path, MapShaders.shader_path(ModelShaders.Blend.OPAQUE, false), String(face.name))
		assert_ne(face.layers & SceneLightingSpec.SHADOW_CASTER_LAYER, 0, String(face.name))
		var arrays: Array = face.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_eq(normals.size(), vertices.size(), String(face.name))
		assert_eq(colours.size(), vertices.size(), String(face.name))
		for index: int in range(0, vertices.size(), 3):
			var front: Vector3 = (vertices[index + 2] - vertices[index]).cross(vertices[index + 1] - vertices[index])
			assert_gt(front.y, 0.0, "%s corner %d faces up" % [face.name, index])
			assert_gt(normals[index].y, 0.0, "%s normal %d" % [face.name, index])
		faces += 1
	assert_gt(faces, 0)


func test_sandbox_is_lit_by_the_options_lights() -> void:
	var screen: SandboxScreen = _sandbox(_data)
	var expected: SceneLightingSpec = SceneLightingBuilder.from_lighting(OptionsModels.options_lighting())
	assert_gt(expected.lights.size(), 0)
	assert_eq(screen.scene_lighting.light_nodes().size(), expected.lights.size())
	assert_eq(_count(screen, "DirectionalLight3D"), expected.lights.size())
	assert_eq(_count(screen, "WorldEnvironment"), 1)
	assert_eq(screen.scene_lighting.applied_ambient, expected.ambient)
	assert_gt(screen.entity_model_count(), 0, "the effects preset places entity models")
	_assert_all_lit(_shader_paths(_model_nodes(screen)), "model_", "frog and entity part")
	_assert_zone_faces_lit(screen)
	screen.close_data()
