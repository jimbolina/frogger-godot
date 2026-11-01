extends GutTest
## Water: environment-mapped surfaces draw a partial reflection with
## specular; riverbeds stay plain lit terrain.

const WATER_UNIFORMS: Array[String] = ["reflection_emission", "specular_strength", "shininess"]


func test_water_surfaces_take_the_default_water_look() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_scene())
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var surfaces: Dictionary[int, ShaderMaterial] = _materials_by_layer(built, instance)
	assert_eq(surfaces.keys(), [-1, 1, 2], "ordinary terrain, riverbed and water surfaces")
	var water: ShaderMaterial = surfaces[2]
	assert_eq(_float(water, "reflection_emission"), MapMesh.Instance.WATER_REFLECTION)
	assert_eq(_float(water, "specular_strength"), MapMesh.Instance.WATER_SPECULAR)
	assert_eq(_float(water, "shininess"), MapMesh.Instance.WATER_SHININESS)
	assert_eq(MapMesh.Instance.WATER_REFLECTION, 0.35)
	assert_eq(MapMesh.Instance.WATER_SPECULAR, 0.2)
	assert_eq(MapMesh.Instance.WATER_SHININESS, 512.0)
	assert_lt(MapMesh.Instance.WATER_SPECULAR * PI, 1.0, "the highlight's peak alone stays below a full light")
	for layer: int in [-1, 1]:
		for parameter: String in WATER_UNIFORMS:
			assert_true(_unset(surfaces[layer], parameter), "layer %d leaves %s at the shader default" % [layer, parameter])
	assert_eq(instance.water_look(), PackedFloat32Array([0.35, 0.2, 512.0]))
	instance.free()


func test_set_water_look_changes_water_only() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_scene())
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	instance.set_water_look(0.25, 0.75, 16.0)
	var surfaces: Dictionary[int, ShaderMaterial] = _materials_by_layer(built, instance)
	assert_eq(_float(surfaces[2], "reflection_emission"), 0.25)
	assert_eq(_float(surfaces[2], "specular_strength"), 0.75)
	assert_eq(_float(surfaces[2], "shininess"), 16.0)
	for parameter: String in WATER_UNIFORMS:
		assert_true(_unset(surfaces[1], parameter), "the riverbed keeps %s unset" % parameter)
	instance.set_filtering(true)
	assert_eq(_float(surfaces[2], "reflection_emission"), 0.25, "reconfiguration keeps the tuned look")
	assert_eq(instance.water_look(), PackedFloat32Array([0.25, 0.75, 16.0]))
	instance.free()


func test_include_draws_reflection_as_emission_and_blends_the_vertex_shading() -> void:
	var include: String = FileAccess.get_file_as_string(MapShaders.INCLUDE_PATH)
	assert_string_contains(include, "uniform float reflection_emission = 0.0;")
	assert_string_contains(include, "ALBEDO = shown * (1.0 - reflection_emission);")
	assert_string_contains(include, "EMISSION = shown * reflection_emission;")
	assert_string_contains(include, "texel.rgb * mix(vec3(1.0), to_linear(min(COLOR.rgb * 2.0, vec3(1.0))), vertex_tint)")
	assert_string_contains(include, "mix(vec3(1.0), to_linear(COLOR.rgb), vertex_tint)")
	assert_string_contains(include, "SPECULAR_LIGHT += specular_strength * pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), shininess)")


func _materials_by_layer(built: MapMesh, instance: MapMesh.Instance) -> Dictionary[int, ShaderMaterial]:
	var found: Dictionary[int, ShaderMaterial] = {}
	var node: MeshInstance3D = instance.get_child(0)
	for surface: int in node.mesh.get_surface_count():
		var spec: MapMesh.Surface = built.surface_specs[0][surface]
		found[spec.layer] = node.get_surface_override_material(surface)
	found.sort()
	return found


func _float(material: ShaderMaterial, parameter: String) -> float:
	return material.get_shader_parameter(parameter)


func _unset(material: ShaderMaterial, parameter: String) -> bool:
	return typeof(material.get_shader_parameter(parameter)) == TYPE_NIL


func _scene() -> MapSceneData:
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.vertices = [Vector3i(0, 0, 256), Vector3i(256, 0, 256),
		Vector3i(0, 0, 0), Vector3i(256, 0, 0)]
	scene.map.group_size = Vector2i(256, 256)
	var ground: MapPolygon = _quad(0)
	var riverbed: MapPolygon = _quad(0)
	riverbed.flags = 4
	var water: MapPolygon = _quad(1)
	water.flags = 2
	scene.map.polygons.append_array([ground, riverbed, water])
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0, 1, 2])
	scene.map.groups.append(group)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([40, 90, 160])
	var first: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 100, 0, SyntheticVlo.abgr(pixels))
	var second: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 101, 0, SyntheticVlo.abgr(pixels))
	second.vram_y = 256
	scene.preferred = SyntheticVlo.bank([first, second])
	scene.library.add_bank(scene.preferred)
	scene.remap = TextureRemap.new()
	scene.remap.texture_ids = PackedInt32Array([100, 101])
	return scene


func _quad(texture: int) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	polygon.texture_id = texture
	polygon.visible = true
	return polygon
