extends GutTest
## Trigger first-update pause, per-type callback effects, failed-contact rollback and recreation.

func _platform(flags: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.unique_id = 21
	definition.flags = flags
	definition.behavior = EntityBehaviorCatalog.resolve("MOVING_PLATFORM")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.volcano = EntityVolcanoDefinition.new()
	definition.path_definition = PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.end = Vector3i(100, 0, 0)
	definition.path_definition.segments.append(segment)
	definition.path_start = PathStart.new()
	definition.path_start.speed = 10
	return definition

func _trigger(trigger_type: EntityTrigger.Type, ids: PackedInt32Array, form_flags: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 1
	definition.unique_id = 22
	definition.form_flags = form_flags
	definition.behavior = EntityBehaviorCatalog.resolve("TRIGGER")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.trigger = EntityTriggerDefinition.new()
	definition.trigger.trigger_type = trigger_type
	definition.trigger.target_ids = ids
	return definition

func _ids(first: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = first.duplicate()
	while result.size() < 10:
		result.append(-1)
	return result

func _result() -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = EntitySnapshot.new()
	result.entity.custom_state = EntityCustomState.new()
	return result

func _environment() -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	return environment

func _update(run: EntityRun) -> String:
	return run.update_custom(1, _environment(), SourceRandom.create(1), Vector3i.ZERO, false).error

func _kinds(result: EntityCustomResult) -> Array:
	var kinds: Array = []
	for effect: EntityTargetEffect in result.target_effects:
		kinds.append([effect.unique_id, effect.kind])
	return kinds

func test_first_update_pauses_each_listed_target_once() -> void:
	var definition: EntityDefinition = _trigger(EntityTrigger.Type.BEGIN, _ids(PackedInt32Array([-1, 21, 65534])))
	var result: EntityCustomResult = _result()
	assert_eq(EntityTrigger.update(definition, result), "")
	assert_eq(_kinds(result), [[21, EntityTargetEffect.Kind.PAUSE], [65534, EntityTargetEffect.Kind.PAUSE]])
	assert_true(result.entity.custom_state.initialized)
	result.target_effects.clear()
	assert_eq(EntityTrigger.update(definition, result), "")
	assert_true(result.target_effects.is_empty())
	definition.trigger = null
	assert_ne(EntityTrigger.update(definition, _result()), "")

func test_contact_emits_the_source_operation_for_each_type() -> void:
	var expected: Dictionary[EntityTrigger.Type, EntityTargetEffect.Kind] = {
		EntityTrigger.Type.FREEZE: EntityTargetEffect.Kind.TOGGLE,
		EntityTrigger.Type.REVERSE: EntityTargetEffect.Kind.FORWARD,
		EntityTrigger.Type.START: EntityTargetEffect.Kind.TOGGLE,
		EntityTrigger.Type.BEGIN: EntityTargetEffect.Kind.RESUME,
	}
	for type: EntityTrigger.Type in expected:
		var result: EntityCustomResult = _result()
		assert_eq(EntityTrigger.contact(_trigger(type, _ids(PackedInt32Array([21, -1, 9]))), result), "")
		assert_eq(_kinds(result), [[21, expected[type]], [9, expected[type]]], str(type))
	var invalid: EntityDefinition = _trigger(EntityTrigger.Type.BEGIN, _ids(PackedInt32Array([21])))
	invalid.trigger.trigger_type = 4
	assert_ne(EntityTrigger.contact(invalid, _result()), "")

func test_run_pauses_on_first_update_and_begin_releases_on_contact() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _trigger(EntityTrigger.Type.BEGIN, _ids(PackedInt32Array([21])))])
	assert_eq(run.error, "")
	assert_eq(_update(run), "")
	var paused: EntitySnapshot = run.snapshot().entities[0]
	assert_true(bool(paused.entity_flags & EntityDefinition.NO_MOVEMENT))
	assert_false(bool(paused.path.flags & PathStart.ACTIVE))
	assert_true(run.snapshot().entities[1].custom_state.initialized)
	assert_eq(run.contact_trigger(1), "")
	var released: EntitySnapshot = run.snapshot().entities[0]
	assert_eq(released.entity_flags & EntityDefinition.NO_MOVEMENT, 0)
	assert_true(bool(released.path.flags & PathStart.ACTIVE))
	assert_eq(run.contact_trigger(1), "")
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0, "BEGIN never pauses")
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position.x, 10)

func test_failed_toggle_contact_publishes_no_target_change() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _trigger(EntityTrigger.Type.FREEZE, _ids(PackedInt32Array([21, 999])))])
	assert_eq(run.error, "")
	var before: EntityRunSnapshot = run.snapshot()
	assert_string_contains(run.contact_trigger(1), "not live")
	assert_eq(run.snapshot().entities[0].entity_flags, before.entities[0].entity_flags)
	assert_eq(run.snapshot().entities[0].path.flags, before.entities[0].path.flags)
	assert_ne(run.contact_trigger(0), "", "only a trigger entity runs the trigger callback")

func test_pause_skips_a_target_that_is_not_live() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _trigger(EntityTrigger.Type.BEGIN, _ids(PackedInt32Array([999, 21])))])
	assert_eq(_update(run), "")
	assert_true(run.snapshot().entities[1].custom_state.initialized)
	assert_true(bool(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT))

func test_recreated_trigger_pauses_a_released_target_again_without_reauthoring_its_flags() -> void:
	var run: EntityRun = EntityRun.create([_platform(EntityDefinition.NO_MOVEMENT), _trigger(EntityTrigger.Type.BEGIN, _ids(PackedInt32Array([21])), 16)])
	assert_eq(run.error, "")
	assert_eq(_update(run), "")
	assert_eq(run.contact_trigger(1), "")
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0)
	assert_eq(run.reset_in_level(false, _environment()), "")
	assert_false(run.snapshot().entities[1].custom_state.initialized)
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0, "map entity flags survive trigger recreation")
	assert_true(bool(run.snapshot().entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(_update(run), "")
	assert_true(bool(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT))
	assert_false(bool(run.snapshot().entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(run.contact_trigger(1), "")
	assert_eq(run.reset(), "")
	assert_true(bool(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT), "level start restores authored flags")
	assert_false(bool(run.snapshot().entities[0].path.flags & PathStart.ACTIVE))
