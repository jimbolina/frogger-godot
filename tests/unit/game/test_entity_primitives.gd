extends GutTest
## Synthetic source-width cuboids, animated probes and stored-pose cache cases.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]

func _frog() -> FrogCollisionDefinition:
	var result := FrogCollisionDefinition.new()
	result.part_count = 2
	for index: int in 2:
		var probe := FrogCollisionDefinition.Probe.new()
		probe.part_index = index
		probe.hilite_index = 0
		probe.vertex = Vector3i(index + 1, -1, 3)
		result.probes.append(probe)
	var action := FrogCollisionDefinition.Action.new()
	var frame: PackedInt32Array = IDENTITY.duplicate()
	frame.append_array(IDENTITY)
	action.frames.assign([frame, frame.duplicate(), frame.duplicate()])
	action.frames[2][9] = 10
	action.actual_cels = PackedInt32Array([0, 0, 1])
	result.actions.append(action)
	return result

func _points(points: Array[Vector3i]) -> FrogCollisionQuery.Sample:
	var result := FrogCollisionQuery.Sample.new()
	result.points.assign(points)
	for index: int in points.size():
		result.part_indices.append(index + 4)
		result.hilite_indices.append(index + 8)
	return result

func test_cuboid_strict_boundaries_on_all_six_faces() -> void:
	var primitive := EntityPrimitiveDefinition.new()
	primitive.half_size = Vector3i(10, 20, 30)
	for axis: int in 3:
		for sign_value: int in [-1, 1]:
			var face := Vector3i.ZERO
			face[axis] = sign_value * primitive.half_size[axis]
			assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([face])).status, EntityPrimitiveQuery.MISS)
			face[axis] -= sign_value
			assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([face])).status, EntityPrimitiveQuery.CONTACT)
	primitive.half_size.x = 0
	assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([Vector3i.ZERO])).status, EntityPrimitiveQuery.MISS)

func test_offset_is_in_owner_axes_and_inverse_rotation_uses_columns() -> void:
	var primitive := EntityPrimitiveDefinition.new()
	primitive.offset = Vector3i(10, 20, 30)
	primitive.half_size = Vector3i(6, 5, 4)
	var matrix := PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 100, 200, 300])
	var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([primitive], matrix, _points([Vector3i(133, 224, 285)]))
	assert_eq(result.status, EntityPrimitiveQuery.CONTACT)
	assert_eq(result.local_position, Vector3i(5, 4, 3))
	assert_eq(result.world_point, Vector3i(133, 224, 285))

func test_displacement_narrows_to_short_before_inverse_rotation() -> void:
	var primitive := EntityPrimitiveDefinition.new()
	primitive.half_size = Vector3i(2, 2, 2)
	var matrix: PackedInt32Array = IDENTITY.duplicate()
	matrix[9] = 65536
	var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([primitive], matrix, _points([Vector3i(1, 0, 0)]))
	assert_eq(result.status, EntityPrimitiveQuery.CONTACT)
	assert_eq(result.local_position, Vector3i(1, 0, 0))

func test_first_hilite_hit_wins_and_disabled_cuboids_do_not_hit() -> void:
	var primitive := EntityPrimitiveDefinition.new()
	primitive.half_size = Vector3i(3, 3, 3)
	var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([primitive], IDENTITY, _points([Vector3i(4, 0, 0), Vector3i(2, 0, 0), Vector3i.ZERO]))
	assert_eq(result.status, EntityPrimitiveQuery.CONTACT)
	assert_eq(result.part_index, 5)
	assert_eq(result.hilite_index, 9)
	assert_eq(result.primitive_part_index, 0)
	assert_eq(result.primitive_index, 0)
	assert_eq(result.reaction, 1)
	primitive.flags = 258
	assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([Vector3i.ZERO])).status, EntityPrimitiveQuery.DISABLED)

func test_unsupported_shape_axes_flags_and_reactions_fail_explicitly() -> void:
	var primitive := EntityPrimitiveDefinition.new()
	for shape: int in [1, 2, 3, 4]:
		primitive.shape = shape
		assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([Vector3i.ZERO])).status, EntityPrimitiveQuery.UNSUPPORTED)
	primitive.shape = 0
	primitive.matrix_index = 0
	assert_ne(primitive.validate(), "")
	primitive.matrix_index = -1
	primitive.flags = 6
	assert_ne(primitive.validate(), "")
	primitive.flags = 0
	assert_ne(primitive.validate(), "")
	primitive.flags = 2
	primitive.reaction = 2
	assert_ne(primitive.validate(), "")
	primitive.reaction = 0
	assert_eq(primitive.validate(), "")
	assert_eq(EntityPrimitiveQuery.query([primitive, primitive], IDENTITY, _points([Vector3i.ZERO])).status, EntityPrimitiveQuery.INVALID)
	assert_eq(EntityPrimitiveQuery.query([primitive], IDENTITY, _points([Vector3i(32768, 0, 0)])).status, EntityPrimitiveQuery.INVALID)

func test_animated_hilites_use_part_matrices_and_two_short_stores() -> void:
	var definition: FrogCollisionDefinition = _frog()
	assert_eq(definition.validate(), "")
	var root: PackedInt32Array = IDENTITY.duplicate()
	root[9] = 32767
	var sample: FrogCollisionQuery.Sample = FrogCollisionQuery.sample(definition, 0, 2, root)
	assert_eq(sample.error, "")
	assert_eq(sample.points[0], Vector3i(-32758, -1, 3))
	assert_eq(sample.points[1], Vector3i(-32767, -1, 3))
	assert_eq(sample.part_indices, PackedInt32Array([0, 1]))
	assert_eq(sample.hilite_indices, PackedInt32Array([0, 0]))
	# Matrix composition narrows 40000 to -25536 before applying vertex x=2.
	definition.actions[0].frames[0][0] = 20000
	definition.probes[0].vertex = Vector3i(2, 0, 0)
	root = IDENTITY.duplicate()
	root[0] = 8192
	root[9] = 10
	sample = FrogCollisionQuery.sample(definition, 0, 0, root)
	assert_eq(sample.points[0], Vector3i(-3, 0, 0))
	# Arithmetic shifts round a negative fractional world unit down.
	root = IDENTITY.duplicate()
	root[4] = 2048
	definition.probes[0].vertex = Vector3i(2, -1, 0)
	sample = FrogCollisionQuery.sample(definition, 0, 1, root)
	assert_eq(sample.points[0].y, -1)

func test_static_frog_cache_keeps_previous_root_for_repeated_actual_cel() -> void:
	var definition: FrogCollisionDefinition = _frog()
	var pose := FrogCollisionPose.new()
	assert_eq(pose.refresh(definition, 0, 0, IDENTITY), "")
	var moved: PackedInt32Array = IDENTITY.duplicate()
	moved[9] = 100
	assert_eq(pose.refresh(definition, 0, 1, moved), "")
	assert_eq(pose.probes.points[0], Vector3i(1, -1, 3))
	var candidate: FrogCollisionPose = pose.copy()
	assert_eq(candidate.refresh(definition, 0, 2, moved), "")
	assert_eq(candidate.probes.points[0], Vector3i(111, -1, 3))
	assert_eq(pose.probes.points[0], Vector3i(1, -1, 3))
	assert_ne(candidate.refresh(definition, 0, 4, moved), "")
	assert_eq(candidate.probes.points[0], Vector3i(111, -1, 3))

func test_detached_definition_and_samples_reject_invalid_dependencies() -> void:
	var definition: FrogCollisionDefinition = _frog()
	var copied: FrogCollisionDefinition = definition.copy()
	definition.probes[0].vertex.x = 30
	definition.actions[0].frames[0][9] = 40
	definition.actions[0].actual_cels[0] = 50
	assert_eq(copied.probes[0].vertex.x, 1)
	assert_eq(copied.actions[0].frames[0][9], 0)
	assert_eq(copied.actions[0].actual_cels[0], 0)
	copied.actions[0].actual_cels.clear()
	assert_ne(copied.validate(), "")
	assert_ne(FrogCollisionQuery.sample(definition, 1, 0, IDENTITY).error, "")
	assert_ne(FrogCollisionQuery.sample(definition, 0, 9, IDENTITY).error, "")
