extends GutTest
## The frog tint uses instance-local source lighting uniforms only while a flag is set, and part scales stay inert unless set.

func _instance() -> AnimatedModelInstance:
	var file: MofFile = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	var mesh: ModelMesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(file)
	var instance := AnimatedModelInstance.new()
	add_child_autofree(instance)
	instance.setup(mesh, ModelAnimationPlayer.new(file))
	return instance

func _shown(instance: AnimatedModelInstance) -> ShaderMaterial:
	var override: ShaderMaterial = instance.part_nodes[0].get_surface_override_material(0) as ShaderMaterial
	return override if override != null else instance.model_mesh.part_meshes[0].surface_get_material(0) as ShaderMaterial

func test_unflagged_tint_leaves_the_shared_unlit_material() -> void:
	var instance: AnimatedModelInstance = _instance()
	var before: ShaderMaterial = _shown(instance)
	instance.set_tint(Vector3i(1, 2, 3), Vector3i(4, 5, 6), 0)
	assert_same(_shown(instance), before)
	assert_eq(AnimatedModelInstance.tint_light(Vector3i.ZERO, Vector3i.ZERO, 0), Vector3(4096, 4096, 4096))

func test_flags_set_local_uniforms_and_clearing_them_restores_unlit_drawing() -> void:
	var instance: AnimatedModelInstance = _instance()
	var shared: ShaderMaterial = instance.model_mesh.part_meshes[0].surface_get_material(0) as ShaderMaterial
	instance.set_tint(Vector3i(0, 64, 192), Vector3i(32, 64, 64), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS)
	var local: ShaderMaterial = _shown(instance)
	assert_ne(local, shared)
	var lit: bool = local.get_shader_parameter("source_lighting")
	assert_true(lit)
	var light: Vector3 = local.get_shader_parameter("source_ambient")
	assert_eq(light, Vector3(0, (32 + 80) * 16, (96 + 240) * 16), "custom ambient replaces 0x60 and the scale multiplies both parts")
	var colour: Vector3 = local.get_shader_parameter("source_colour0")
	assert_eq(colour, Vector3.ZERO, "directional map lights stay off")
	var shared_lit: bool = shared.get_shader_parameter("source_lighting") == true
	assert_false(shared_lit, "shared materials are untouched")
	instance.set_tint(Vector3i(128, 128, 128), Vector3i.ZERO, FrogTint.SCALED_COLOURS)
	light = local.get_shader_parameter("source_ambient")
	assert_eq(light, Vector3(4096, 4096, 4096), "the neutral edge-fade grey is unlit")
	instance.set_tint(Vector3i(24, 0, 0), Vector3i(24, 0, 0), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS)
	light = local.get_shader_parameter("source_ambient")
	assert_eq(light, Vector3((4 + 30) * 16, 0, 0), "the Volcano char")
	instance.set_tint(Vector3i(24, 0, 0), Vector3i(24, 0, 0), 0)
	lit = local.get_shader_parameter("source_lighting")
	assert_false(lit)
	assert_same(_shown(instance), local)

func test_part_scale_applies_in_part_space_and_clears() -> void:
	var instance: AnimatedModelInstance = _instance()
	var posed: Transform3D = instance.part_nodes[0].transform
	instance.set_part_scale(0, 1.0)
	instance.render(1.0)
	assert_eq(instance.part_nodes[0].transform, posed, "an unset or unit scale is inert")
	instance.set_part_scale(0, 2.5)
	instance.render(1.0)
	assert_eq(instance.part_nodes[0].transform.basis, posed.basis * Basis.from_scale(Vector3.ONE * 2.5))
	assert_eq(instance.part_nodes[0].transform.origin, posed.origin)
	instance.clear_part_scales()
	instance.render(1.0)
	assert_eq(instance.part_nodes[0].transform, posed)
