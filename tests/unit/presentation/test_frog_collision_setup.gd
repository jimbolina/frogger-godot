extends GutTest
## Setup rejects unsupported model topology and detaches collision dependencies.

func _frog_model() -> MofFile:
	var model := MofFile.new()
	model.kind = MofFile.Kind.ANIMATED
	model.animated = MofAnimated.new()
	model.animated.transform_code = 2
	model.animated.starts_at_frame_zero = true
	var mesh := MofStatic.new()
	var part := MofPart.new()
	part.hilite_count = 1
	part.vertex_count = 1
	var cel := MofPart.Partcel.new()
	cel.vertices = PackedInt32Array([4, 5, 6])
	part.partcels.append(cel)
	var alternate := MofPart.Partcel.new()
	alternate.vertices = PackedInt32Array([40, 50, 60])
	part.partcels.append(alternate)
	var hilite := MofPart.Hilite.new()
	hilite.attach = MofPart.ATTACH_VERTEX
	part.hilites.append(hilite)
	mesh.parts.append(part)
	model.static_models.append(mesh)
	var model_set := MofAnimated.ModelSet.new()
	var info := MofAnimated.ModelInfo.new()
	info.animation_type = 1
	info.flags = 1
	info.part_count = 1
	model_set.models.append(info)
	var action := MofAnimated.Action.new()
	action.part_count = 1
	action.frame_count = 1
	action.cel_count = 1
	action.flags = 1
	action.cel_numbers = PackedInt32Array([0])
	action.transform_indices = PackedInt32Array([0])
	model_set.actions.append(action)
	model.animated.model_sets.append(model_set)
	var transform := MofTransform.new()
	transform.code = 2
	transform.raw_values = PackedInt32Array([64, 0, 0, 0, 10, 20, 30])
	model.animated.transforms.append(transform)
	return model

func _vehicle() -> MofFile:
	var model := MofFile.new()
	model.kind = MofFile.Kind.STATIC
	var mesh := MofStatic.new()
	var part := MofPart.new()
	var primitive := MofPart.Collprim.new()
	primitive.flags = 2
	primitive.size = Vector3i(100, 20, 30)
	primitive.user = 1
	part.collprims.append(primitive)
	mesh.parts.append(part)
	model.static_models.append(mesh)
	return model

func test_frog_setup_uses_partcel_zero_and_detaches_all_source_arrays() -> void:
	var model: MofFile = _frog_model()
	var setup: FrogCollisionSetup = FrogCollisionSetup.from_model(model)
	assert_eq(setup.error, "")
	assert_not_null(setup.definition)
	if setup.definition == null:
		return
	assert_eq(setup.definition.probes[0].vertex, Vector3i(4, 5, 6))
	assert_eq(setup.definition.actions[0].frames[0].slice(9), PackedInt32Array([10, 20, 30]))
	assert_eq(setup.definition.actions[0].actual_cels, PackedInt32Array([0]))
	model.static_models[0].parts[0].partcels[0].vertices[0] = 123
	model.animated.transforms[0].raw_values[4] = 456
	assert_eq(setup.definition.probes[0].vertex.x, 4)
	assert_eq(setup.definition.actions[0].frames[0][9], 10)

func test_frog_setup_rejects_interpolation_polygon_hilites_and_incomplete_meshes() -> void:
	var model: MofFile = _frog_model()
	model.animated.model_sets[0].actions[0].flags = 2
	assert_ne(FrogCollisionSetup.from_model(model).error, "")
	model = _frog_model()
	model.static_models[0].parts[0].hilites[0].attach = MofPart.ATTACH_POLYGON
	assert_ne(FrogCollisionSetup.from_model(model).error, "")
	model = _frog_model()
	model.is_incomplete = true
	assert_ne(FrogCollisionSetup.from_model(model).error, "")

func test_frog_setup_rejects_collision_hilites_on_imported_throat() -> void:
	var model: MofFile = _frog_model()
	var part: MofPart = model.static_models[0].parts[0]
	model.static_models[0].parts.clear()
	for index: int in 15:
		model.static_models[0].parts.append(MofPart.new())
	model.static_models[0].parts.append(part)
	model.animated.model_sets[0].models[0].part_count = 16
	assert_ne(FrogCollisionSetup.from_model(model).error, "")

func test_vehicle_setup_copies_cuboid_and_fails_closed_on_extra_geometry() -> void:
	var model: MofFile = _vehicle()
	var setup: EntityPrimitiveSetup = EntityPrimitiveSetup.from_model(model)
	assert_eq(setup.error, "")
	assert_eq(setup.primitives.size(), 1)
	model.static_models[0].parts[0].collprims[0].size.x = 500
	assert_eq(setup.primitives[0].half_size, Vector3i(100, 20, 30))
	model.static_models[0].parts[0].collprims.append(MofPart.Collprim.new())
	assert_ne(EntityPrimitiveSetup.from_model(model).error, "")
	model = _vehicle()
	model.static_models[0].parts[0].collprims[0].matrix_index = 0
	assert_ne(EntityPrimitiveSetup.from_model(model).error, "")
