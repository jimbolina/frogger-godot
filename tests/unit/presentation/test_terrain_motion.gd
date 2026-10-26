extends GutTest
## Presentation samples retain exact endpoints and a shared platform/camera timeline.

func _sample() -> RunSnapshot:
	var result := RunSnapshot.new()
	result.entities = EntityRunSnapshot.new()
	var entity := EntitySnapshot.new()
	entity.entity_index = 7
	result.entities.entities.append(entity)
	result.camera = GameplayCameraSnapshot.new()
	return result

func test_endpoints_camera_turn_and_caller_mutation_are_independent() -> void:
	var before: RunSnapshot = _sample()
	var current: RunSnapshot = before.copy()
	current.position_16 = Vector3i(512, -256, 0) * 65536
	current.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 512, -256, 0])
	current.camera.source_world = Vector3i(512, -256, 0)
	current.camera.axis_x_12 = Vector3i(0, 0, -4096)
	current.camera.axis_z_12 = Vector3i(4096, 0, 0)
	var motion := TerrainMotion.new()
	motion.capture(before, current)
	assert_eq(motion.frog(0.0), GameSpace.transform(before.matrix12))
	assert_eq(motion.frog(1.0), GameSpace.transform(current.matrix12))
	assert_eq(motion.frog(0.5).origin, Vector3(1, 0.5, 0))
	assert_eq(motion.camera(0.0), GameplayProjection.camera_transform(before.camera))
	assert_eq(motion.camera(1.0), GameplayProjection.camera_transform(current.camera))
	assert_eq(motion.camera(0.5).origin, Vector3(1, 0.5, 0))
	assert_true(motion.camera(0.5).basis.is_equal_approx(motion.frog(0.5).basis))
	var retained: Transform3D = motion.frog(1.0)
	current.position_16 = Vector3i.ZERO
	current.matrix12[0] = 123
	assert_eq(motion.frog(1.0), retained)

func test_rotating_platform_carries_rider_in_its_interpolated_frame() -> void:
	var before: RunSnapshot = _sample()
	before.current_entity_index = 7
	before.position_16 = Vector3i(256, 0, 0) * 65536
	var current: RunSnapshot = before.copy()
	current.entities.entities[0].matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 512, 0, 0])
	current.position_16 = Vector3i(512, 0, -256) * 65536
	current.matrix12 = current.entities.entities[0].matrix12.duplicate()
	var motion := TerrainMotion.new()
	motion.capture(before, current)
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var local: Vector3 = motion.entity(0, fraction).affine_inverse() * motion.frog(fraction).origin
		assert_almost_eq(local, Vector3.RIGHT, Vector3.ONE * 0.00001)
	current.current_entity_index = -1
	motion.capture(before, current)
	assert_eq(motion.frog(0.5).origin, Vector3(1.5, 0, 0.5), "transfers retain continuous world motion")

func test_recreated_or_disappearing_entities_collapse_and_reset_discards_history() -> void:
	var before: RunSnapshot = _sample()
	before.current_entity_index = 7
	var current: RunSnapshot = before.copy()
	current.position_16 = Vector3i(512, 0, 0) * 65536
	current.camera.source_world = Vector3i(512, 0, 0)
	current.entities.entities[0].matrix12[9] = 512
	current.entities.entities[0].generation += 1
	var motion := TerrainMotion.new()
	motion.capture(before, current)
	assert_eq(motion.entity(0, 0.0), motion.entity(0, 1.0))
	assert_eq(motion.frog(0.0), motion.frog(1.0), "a recreated attachment cannot carry old rider history")
	assert_eq(motion.camera(0.0), motion.camera(1.0))
	current.entities.entities[0].generation = 0
	current.entities.entities[0].unique_id += 1
	motion.capture(before, current)
	assert_eq(motion.entity(0, 0.0), motion.entity(0, 1.0), "changed identity collapses even with the same generation")
	assert_eq(motion.frog(0.0), motion.frog(1.0))
	current.entities.entities[0].unique_id = before.entities.entities[0].unique_id
	current.entities.entities[0].live = false
	motion.capture(before, current)
	assert_eq(motion.entity(0, 0.0), motion.entity(0, 1.0))
	current.position_16.x = 999 * 65536
	motion.capture(current, current)
	assert_eq(motion.frog(0.0), motion.frog(1.0), "reset/seek/teleport uses one committed sample")

func test_degenerate_basis_stays_finite_and_keeps_exact_endpoints() -> void:
	var before := Transform3D(Basis(Vector3.RIGHT, Vector3.ZERO, Vector3.BACK), Vector3.ZERO)
	var current := Transform3D(Basis.IDENTITY, Vector3(2, 4, 6))
	assert_eq(TerrainMotion.blend(before, current, 0.0), before)
	assert_eq(TerrainMotion.blend(before, current, 1.0), current)
	assert_true(TerrainMotion.blend(before, current, 0.5).is_finite())
	assert_eq(TerrainMotion.blend(before, current, 0.5).basis.y, Vector3(0, 0.5, 0))

func test_pink_frog_pickup_collapses_previous_parent_history() -> void:
	var before: RunSnapshot = _sample()
	before.entities.entities[0].background = EntityCustomState.new()
	before.entities.entities[0].background.parent_entity_index = 15
	var current: RunSnapshot = before.copy()
	current.entities.entities[0].background.carrier_index = 0
	current.entities.entities[0].background.parent_entity_index = -1
	current.entities.entities[0].matrix12[9] = 256
	var motion := TerrainMotion.new()
	motion.capture(before, current)
	assert_eq(motion.entity(0, 0.0), motion.entity(0, 1.0))

func test_inspector_axes_match_exact_pose_and_preserve_committed_contact_probe() -> void:
	var inspection := EntityInspection.new()
	add_child_autofree(inspection)
	inspection.configure([EntityDefinition.new()])
	inspection.configure_contacts([])
	var before: RunSnapshot = _sample()
	var current: RunSnapshot = before.copy()
	current.entities.entities[0].matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 512, 0, 0])
	inspection.set_snapshot(current.entities)
	inspection.set_contact(Vector3i(1, 2, 3), null)
	var exact: Transform3D = inspection._axes[0].transform
	var probe: Vector3 = inspection._contact_probe.position
	var motion := TerrainMotion.new()
	motion.capture(before, current)
	inspection.draw_motion(motion, 1.0)
	assert_eq(inspection._axes[0].transform, exact)
	inspection.draw_motion(motion, 0.5)
	assert_eq(inspection._positions[0].position, Vector3.RIGHT)
	assert_eq(inspection._contact_probe.position, probe, "contact queries stay tick-driven")
