extends GutTest
## Swamp definition ownership, hand-derived ENTSTRSwpCreateRat timing and resolved Swamp capabilities.

func _rat(speed: int, targets: Array[Vector3i]) -> EntitySwampDefinition:
	var swamp := EntitySwampDefinition.new()
	swamp.rat_speed = speed
	swamp.rat_targets = targets
	return swamp

func _targets() -> Array[Vector3i]:
	return [Vector3i(100, -600, 200), Vector3i(400, -600, 200), Vector3i(393, -600, 150), Vector3i(453, 0, 150)] as Array[Vector3i]

func test_definition_copy_detaches_swamp_operands() -> void:
	var definition := EntityDefinition.new()
	definition.swamp = _rat(60, _targets())
	definition.swamp.time_delay = -3
	definition.swamp.motion_type = 4294967295
	assert_eq(definition.swamp.resolve_rat(), "")
	var copied: EntityDefinition = definition.copy()
	assert_ne(copied.swamp, definition.swamp)
	definition.swamp.rat_targets[0] = Vector3i.ZERO
	definition.swamp.jump1_velocity_4 = Vector3i.ZERO
	definition.swamp.time_delay = 0
	assert_eq(copied.swamp.rat_targets, _targets())
	assert_eq([copied.swamp.jump1_velocity_4, copied.swamp.time_delay, copied.swamp.motion_type], [Vector3i(480, 0, 0), -3, 4294967295])
	assert_null(EntityDefinition.new().copy().swamp)

func test_rat_timing_truncates_square_roots_and_signed_divisions() -> void:
	var swamp: EntitySwampDefinition = _rat(60, _targets())
	assert_eq(swamp.resolve_rat(), "")
	assert_eq(swamp.run_speed, 2)
	assert_eq([swamp.jump1_time, swamp.jump1_velocity_4, swamp.jump1_sine_step], [10, Vector3i(480, 0, 0), 204], "isqrt(300^2) / 30; 2048 / 10")
	assert_eq([swamp.run_time, swamp.run_velocity_4], [25, Vector3i(-4, 0, -32)], "isqrt(2549) = 50, / 2; -112 / 25 truncates toward zero")
	assert_eq([swamp.jump2_time, swamp.jump2_velocity_4, swamp.jump2_sine_step], [20, Vector3i(48, 480, 0), 102], "isqrt(363600) = 602, / 30")
	swamp = _rat(-59, _targets())
	assert_eq(swamp.resolve_rat(), "")
	assert_eq([swamp.run_speed, swamp.run_time, swamp.run_velocity_4], [-1, -50, Vector3i(2, 0, 16)], "A negative speed truncates toward zero and reverses the run time")

func test_rat_resolution_reports_source_divisions_by_zero() -> void:
	var targets: Array[Vector3i] = _targets()
	var three: Array[Vector3i] = [targets[0], targets[1], targets[2]]
	assert_ne(_rat(60, three).resolve_rat(), "")
	targets[1] = Vector3i(129, -600, 200)
	assert_string_contains(_rat(60, targets).resolve_rat(), "first jump")
	targets = _targets()
	assert_string_contains(_rat(29, targets).resolve_rat(), "speed")
	targets[2] = Vector3i(401, -600, 200)
	assert_string_contains(_rat(60, targets).resolve_rat(), "run")
	targets = _targets()
	targets[3] = Vector3i(393, -571, 150)
	assert_string_contains(_rat(60, targets).resolve_rat(), "second jump")
	targets[3] = Vector3i(393, -570, 150)
	assert_eq(_rat(60, targets).resolve_rat(), "")

func test_matrix_kinds_update_and_path_kinds_only_move() -> void:
	for kind: EntityBehavior.Kind in EntityBehavior.SWAMP_KINDS:
		var behavior := EntityBehavior.new()
		behavior.kind = kind
		assert_true(behavior.has_form_contact(), str(kind))
		assert_false(behavior.has_custom_update(), str(kind))
		behavior.execution = EntityBehavior.Execution.UPDATE
		assert_eq(behavior.has_custom_update(), kind not in EntityBehavior.SWAMP_PATH_KINDS, str(kind))
	assert_eq(EntityBehavior.SWAMP_PATH_KINDS, [EntityBehavior.Kind.SWP_SLUG, EntityBehavior.Kind.NUCLEAR_BARREL] as Array[EntityBehavior.Kind])

func test_weir_has_an_empty_custom_update() -> void:
	var definition := EntityDefinition.new()
	definition.behavior.kind = EntityBehavior.Kind.SWP_STAT_WEIR
	definition.behavior.layout = EntityBehavior.Layout.MATRIX
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i(1000 + index * 256, -100, 2000))
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, true, false)
	assert_eq(result.error, "")
	assert_eq(result.entity.matrix12, entity.matrix12)
	assert_true(result.entity.requests.is_empty())
