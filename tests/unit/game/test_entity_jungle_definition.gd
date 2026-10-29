extends GutTest
## Jungle definition ownership and resolved Jungle capabilities.

func test_definition_copy_detaches_jungle_operands() -> void:
	var definition := EntityDefinition.new()
	definition.jungle = EntityJungleDefinition.new()
	definition.jungle.snap_time = -6
	definition.jungle.snap_delay = 30
	definition.jungle.fall_delay = 65535
	definition.jungle.hops_before = 12
	definition.jungle.op_id = 8
	definition.jungle.outro_targets.append(Vector3i(1, -2, 3))
	definition.jungle.outro_times.append(4294967295)
	var copied: EntityDefinition = definition.copy()
	assert_ne(copied.jungle, definition.jungle)
	definition.jungle.outro_targets[0] = Vector3i.ZERO
	definition.jungle.outro_times[0] = 0
	definition.jungle.op_id = 0
	assert_eq(copied.jungle.outro_targets, [Vector3i(1, -2, 3)] as Array[Vector3i])
	assert_eq(copied.jungle.outro_times, PackedInt64Array([4294967295]))
	assert_eq([copied.jungle.snap_time, copied.jungle.snap_delay, copied.jungle.fall_delay, copied.jungle.hops_before, copied.jungle.op_id], [-6, 30, 65535, 12, 8])
	assert_null(EntityDefinition.new().copy().jungle)

func test_matrix_kinds_update_and_path_kinds_only_move() -> void:
	for kind: EntityBehavior.Kind in EntityBehavior.JUNGLE_KINDS:
		var behavior := EntityBehavior.new()
		behavior.kind = kind
		assert_true(behavior.has_form_contact(), str(kind))
		assert_false(behavior.has_custom_update(), str(kind))
		behavior.execution = EntityBehavior.Execution.UPDATE
		assert_eq(behavior.has_custom_update(), kind not in EntityBehavior.JUNGLE_PATH_KINDS, str(kind))
	assert_eq(EntityBehavior.JUNGLE_PATH_KINDS, [EntityBehavior.Kind.JUN_HIPPO, EntityBehavior.Kind.JUN_SCORPION] as Array[EntityBehavior.Kind])

func _environment() -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i(1000 + index * 256, -100, 2000))
	return environment

func test_static_jungle_kinds_have_empty_custom_updates() -> void:
	for kind: EntityBehavior.Kind in [EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM, EntityBehavior.Kind.JUN_OUTRO_DOOR, EntityBehavior.Kind.JUN_OUTRO, EntityBehavior.Kind.JUN_PLINTH, EntityBehavior.Kind.JUN_GOLD_FROG, EntityBehavior.Kind.JUN_STONE_FROG]:
		var definition := EntityDefinition.new()
		definition.behavior.kind = kind
		definition.behavior.layout = EntityBehavior.Layout.MATRIX
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, _environment(), SourceRandom.create(1), Vector3i.ZERO, true, false)
		assert_eq(result.error, "", str(kind))
		assert_eq(result.entity.matrix12, entity.matrix12, str(kind))
		assert_true(result.entity.requests.is_empty(), str(kind))
