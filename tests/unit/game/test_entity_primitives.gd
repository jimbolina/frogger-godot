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
	definition.actions[0].frames[0][0] = 20000
	definition.probes[0].vertex = Vector3i(2, 0, 0)
	root = IDENTITY.duplicate()
	root[0] = 8192
	root[9] = 10
	sample = FrogCollisionQuery.sample(definition, 0, 0, root)
	assert_eq(sample.points[0], Vector3i(-3, 0, 0))
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
	assert_eq(candidate.refresh(definition, 0, -1, IDENTITY), "")
	assert_eq(candidate.probes.points[0], Vector3i(111, -1, 3))
	assert_eq(candidate.actual_cel, 1)
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

func test_collected_gold_omits_model_primitives_but_keeps_form_fallback() -> void:
	var gold := EntityDefinition.new()
	gold.entity_index = 0
	gold.behavior = EntityBehaviorCatalog.resolve("GEN_GOLD_FROG")
	gold.behavior.execution = EntityBehavior.Execution.CONTACT
	gold.form_flags = 16
	gold.action_lengths = PackedInt32Array([4])
	var definitions: Array[EntityDefinition] = [gold]
	var run: EntityRun = EntityRun.create(definitions)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var contact := FormContactDefinition.new()
	contact.entity_index = 0
	contact.radius_squared = 10000
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-128, -128)
	contact.height = -10
	contact.max_y = 10
	contact.grid_flags = PackedInt32Array([GridSquareFlags.USABLE])
	var primitive := EntityPrimitiveDefinition.new()
	primitive.half_size = Vector3i(10, 10, 10)
	contact.primitives.append(primitive)
	var state := GameplayState.new()
	state.frog.frog_collision_pose = FrogCollisionPose.new()
	state.frog.frog_collision_pose.probes = _points([Vector3i.ZERO])
	var frog := Frog.new()
	var pose: EntitySnapshot = run.entity_snapshot(0)
	assert_true(pose.model_present)
	assert_eq(frog.contacts.contact_primitive(frog, state, contact, pose).status, EntityPrimitiveQuery.CONTACT)
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	assert_eq(run.reset_in_level(false, environment, true), "")
	pose = run.entity_snapshot(0)
	assert_true(pose.live)
	assert_false(pose.model_present)
	assert_null(pose.animation)
	assert_eq(frog.contacts.contact_primitive(frog, state, contact, pose).status, EntityPrimitiveQuery.MISS)
	assert_eq(FormContactQuery.query(contact, pose, Vector3i.ZERO).status, FormContactResult.CONTACT)
	var collision := EntityCollisionDefinition.new()
	collision.entities = definitions
	collision.contacts.append(contact)
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(1024, 1024)
	frog.entity_collision = collision
	state.entities = run.snapshot()
	var result := TickResult.new()
	assert_eq(frog.contacts.contact_entities(frog, state, result), "")
	assert_eq(result.primitive_contacts.size(), 1)
	assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.MISS)
	assert_eq(result.entity_contacts.size(), 1)
	assert_eq(result.entity_contacts[0].contact.status, FormContactResult.CONTACT)
	assert_eq(state.frog.flags & FrogFlags.MUST_DIE, 0)
	assert_eq(run.step(0), "")
	assert_false(run.entity_snapshot(0).model_present)
	var detached: EntitySnapshot = run.entity_snapshot(0)
	detached.model_present = true
	assert_false(run.entity_snapshot(0).model_present)
	var trace: Dictionary = TerrainTrace.facts(run.entity_snapshot(0), true)
	var traced_model: bool = trace.model_present
	assert_false(traced_model)
	assert_eq(run.reset_in_level(false, environment, false), "")
	pose = run.entity_snapshot(0)
	assert_true(pose.model_present)
	assert_eq(frog.contacts.contact_primitive(frog, state, contact, pose).status, EntityPrimitiveQuery.CONTACT)
