extends GutTest
## The frog tint reaches a model's instance uniforms only while a flag is set, and part scales stay inert unless set.

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

func _tint(instance: AnimatedModelInstance) -> Array:
	var node: MeshInstance3D = instance.part_nodes[0]
	return [node.get_instance_shader_parameter(ModelShaders.TINT_SCALE), node.get_instance_shader_parameter(ModelShaders.TINT_AMBIENT)]

func test_unflagged_tint_leaves_the_shared_material_untinted() -> void:
	var instance: AnimatedModelInstance = _instance()
	var before: ShaderMaterial = _shown(instance)
	instance.set_tint(Vector3i(1, 2, 3), Vector3i(4, 5, 6), 0)
	assert_same(_shown(instance), before)
	assert_eq(_tint(instance), [null, null], "the part keeps the shader's identity defaults")

func test_flags_tint_the_instance_and_clearing_them_restores_it() -> void:
	var instance: AnimatedModelInstance = _instance()
	var shared: ShaderMaterial = instance.model_mesh.part_meshes[0].surface_get_material(0) as ShaderMaterial
	instance.set_tint(Vector3i(0, 64, 192), Vector3i(32, 64, 64), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS)
	assert_same(_shown(instance), shared, "the tint lives on the instance, not a material")
	var drowning: SceneTint = SceneTint.of(Vector3i(0, 64, 192), Vector3i(32, 64, 64), true, true)
	assert_eq(_tint(instance), [drowning.scale, drowning.ambient])
	instance.set_tint(Vector3i(128, 128, 128), Vector3i.ZERO, FrogTint.SCALED_COLOURS)
	assert_eq(_tint(instance), [Vector3.ONE, Color(0, 0, 0, 0)], "the neutral edge-fade grey is untinted")
	instance.set_tint(Vector3i(24, 0, 0), Vector3i(24, 0, 0), 0)
	assert_eq(_tint(instance), [Vector3.ONE, Color(0, 0, 0, 0)])
	assert_same(_shown(instance), shared)

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
