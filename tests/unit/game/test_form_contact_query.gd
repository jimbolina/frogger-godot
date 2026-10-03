extends GutTest
## Pure source-width FORM point checks, without frog reaction state.

func _definition() -> FormContactDefinition:
	var result := FormContactDefinition.new()
	result.entity_index = 12
	result.unique_id = 42
	result.form_grid_id = 3
	result.form_id = 5
	result.form_name = "TEST_FORM"
	result.dimensions = Vector2i(2, 2)
	result.offsets = Vector2i(-256, -256)
	result.height = -20
	result.max_y = 40
	result.radius_squared = 1000000
	result.grid_flags = PackedInt32Array([1, 3, 5, 7])
	return result

func _snapshot() -> EntitySnapshot:
	var result := EntitySnapshot.new()
	result.entity_index = 12
	result.unique_id = 42
	return result

func test_edges_flags_and_height_are_source_exact() -> void:
	var form: FormContactDefinition = _definition()
	var pose: EntitySnapshot = _snapshot()
	for point: Vector3i in [Vector3i(-256, 0, 0), Vector3i(256, 0, 0), Vector3i(0, 0, -256), Vector3i(0, 0, 256)]:
		assert_eq(FormContactQuery.query(form, pose, point).status, FormContactResult.MISS)
	for point: Vector3i in [Vector3i(-255, -20, -255), Vector3i(255, 40, 255)]:
		assert_eq(FormContactQuery.query(form, pose, point).status, FormContactResult.CONTACT)
	assert_eq(FormContactQuery.query(form, pose, Vector3i(0, -21, 0)).status, FormContactResult.MISS)
	assert_eq(FormContactQuery.query(form, pose, Vector3i(0, 41, 0)).status, FormContactResult.MISS)
	var contact: FormContactResult = FormContactQuery.query(form, pose, Vector3i(0, 0, 0))
	assert_eq(contact.cell, Vector2i(1, 1))
	assert_eq(contact.cell_flags, 7)
	assert_eq(contact.height, -20)
	assert_eq([contact.entity_index, contact.unique_id, contact.form_grid_id, contact.form_id, contact.form_name], [12, 42, 3, 5, "TEST_FORM"])
	form.grid_flags[3] = 0
	assert_eq(FormContactQuery.query(form, pose, Vector3i(0, 0, 0)).status, FormContactResult.CONTACT)
	assert_eq(FormContactQuery.query(form, pose, Vector3i(0, 0, 0)).cell_flags, 0)

func test_dormant_inspection_pose_cannot_supply_collision() -> void:
	var pose: EntitySnapshot = _snapshot()
	pose.live = false
	var result: FormContactResult = FormContactQuery.query(_definition(), pose, Vector3i.ZERO)
	assert_eq(result.status, FormContactResult.DISABLED)
	assert_eq(result.reason, "Entity has no live instance")
	pose.live = true
	assert_eq(FormContactQuery.query(_definition(), pose, Vector3i.ZERO).status, FormContactResult.CONTACT)

func test_strict_sphere_and_signed_short_displacement() -> void:
	var form: FormContactDefinition = _definition()
	var pose: EntitySnapshot = _snapshot()
	form.radius_squared = 100
	assert_eq(FormContactQuery.query(form, pose, Vector3i(6, 8, 0)).status, FormContactResult.MISS)
	assert_eq(FormContactQuery.query(form, pose, Vector3i(6, 7, 0)).status, FormContactResult.CONTACT)
	form.radius_squared = 1000000
	pose.matrix12[9] = 32767
	var wrapped: FormContactResult = FormContactQuery.query(form, pose, Vector3i(-32768, 0, 0))
	assert_eq(wrapped.status, FormContactResult.CONTACT)
	assert_eq(wrapped.local_position, Vector3i(1, 0, 0))
	# An overflowed signed-32 squared sum still follows the frozen comparison.
	form.radius_squared = 1
	pose.matrix12[9] = 0
	var far: FormContactResult = FormContactQuery.query(form, pose, Vector3i(32767, 32767, 32767))
	assert_eq(far.status, FormContactResult.MISS)

func test_transposed_rotation_and_signed_32_dot() -> void:
	var form: FormContactDefinition = _definition()
	var pose: EntitySnapshot = _snapshot()
	pose.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0])
	var rotated: FormContactResult = FormContactQuery.query(form, pose, Vector3i(10, 0, 20))
	assert_eq(rotated.status, FormContactResult.CONTACT)
	assert_eq(rotated.local_position, Vector3i(-20, 0, 10))
	pose.matrix12 = PackedInt32Array([32767, 0, 0, 32767, 4096, 0, 32767, 0, 4096, 0, 0, 0])
	form.radius_squared = 2147483647
	var extreme: FormContactResult = FormContactQuery.query(form, pose, Vector3i(32767, 32767, 32767))
	assert_eq(extreme.status, FormContactResult.MISS)
	assert_eq(extreme.local_position.x, -262192)

func test_invalid_disabled_unsupported_and_detached_copies() -> void:
	var form: FormContactDefinition = _definition()
	var pose: EntitySnapshot = _snapshot()
	assert_eq(FormContactQuery.query(null, pose, Vector3i.ZERO).status, FormContactResult.INVALID)
	pose.unique_id = 99
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.INVALID)
	pose.unique_id = 42
	pose.matrix12[0] = 32768
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.INVALID)
	pose.matrix12[0] = 4096
	form.entity_flags = EntityDefinition.NO_COLLISION
	form.unsupported_reason = "needs collprims"
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.DISABLED)
	form.entity_flags = 0
	form.dimensions = Vector2i.ZERO
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.UNSUPPORTED)
	form.unsupported_reason = ""
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.INVALID)
	form.dimensions = Vector2i(2, 2)
	var copy: FormContactDefinition = form.copy()
	copy.grid_flags[0] = 99
	assert_eq(form.grid_flags[0], 1)
	var contact: FormContactResult = FormContactQuery.query(form, pose, Vector3i.ZERO)
	var result_copy: FormContactResult = contact.copy()
	result_copy.cell = Vector2i(-1, -1)
	assert_eq(contact.cell, Vector2i(1, 1))
