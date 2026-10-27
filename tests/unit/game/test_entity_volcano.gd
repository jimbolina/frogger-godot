extends GutTest
## Volcano candidate ownership, ordered target writes and failed-contact rollback.

func _platform() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.unique_id = 21
	definition.behavior = EntityBehaviorCatalog.resolve("MOVING_PLATFORM")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.volcano = EntityVolcanoDefinition.new()
	definition.volcano.initial_movement = 1
	definition.volcano.play_chain_sound = true
	definition.path_definition = PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.end = Vector3i(100, 0, 0)
	definition.path_definition.segments.append(segment)
	definition.path_start = PathStart.new()
	definition.path_start.speed = 10
	return definition

func _switch() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 1
	definition.unique_id = 22
	definition.behavior = EntityBehaviorCatalog.resolve("VOL_COLOUR_SWITCH")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.volcano = EntityVolcanoDefinition.new()
	definition.volcano.target_ids = PackedInt32Array([21])
	definition.action_lengths = PackedInt32Array([4, 4])
	return definition

func test_target_failure_does_not_publish_earlier_toggle_or_cursor() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _switch()])
	assert_eq(run.error, "")
	var before: EntityRunSnapshot = run.snapshot()
	var effects: Array[EntityTargetEffect] = [EntityTargetEffect.create(21, EntityTargetEffect.Kind.TOGGLE), EntityTargetEffect.create(999, EntityTargetEffect.Kind.REVERSE)]
	assert_ne(run.apply_target_effects(effects), "")
	assert_eq(run.snapshot().entities[0].entity_flags, before.entities[0].entity_flags)
	assert_eq(run.snapshot().entities[0].path.flags, before.entities[0].path.flags)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position.x, 10)

func test_target_requests_preserve_order_and_do_not_resample_reverse() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _switch()])
	var effects: Array[EntityTargetEffect] = [EntityTargetEffect.create(21, EntityTargetEffect.Kind.INITIALIZE), EntityTargetEffect.create(21, EntityTargetEffect.Kind.TOGGLE), EntityTargetEffect.create(21, EntityTargetEffect.Kind.REVERSE)]
	assert_eq(run.apply_target_effects(effects), "")
	var pose: EntitySnapshot = run.snapshot().entities[0]
	assert_eq(pose.entity_flags & EntityDefinition.NO_MOVEMENT, 0)
	assert_true(bool(pose.path.flags & PathStart.ACTIVE))
	assert_true(bool(pose.path.flags & PathStart.BACKWARDS))
	assert_eq(pose.path.position, Vector3i.ZERO)

func test_failed_contact_does_not_publish_switch_or_first_target_changes() -> void:
	var trigger: EntityDefinition = _switch()
	trigger.volcano.target_ids.append(999)
	var run: EntityRun = EntityRun.create([_platform(), trigger])
	var result: EntityCustomResult = run.contact_colour_switch(1, GameplayState.new())
	assert_ne(result.error, "")
	var state: EntityRunSnapshot = run.snapshot()
	assert_eq(state.entities[1].custom_state.mode, EntityVolcanoSwitch.Mode.OFF_UP)
	assert_eq(state.entities[1].custom_state.timer, 0)
	assert_eq(state.entities[1].animation.action, 1)
	assert_eq(state.entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0)

func test_candidate_contact_and_animation_changes_do_not_escape_discarded_run() -> void:
	var run: EntityRun = EntityRun.create([_platform(), _switch()])
	var candidate: EntityRun = run.copy()
	assert_eq(candidate.contact_colour_switch(1, GameplayState.new()).error, "")
	candidate.advance_animations()
	assert_eq(candidate.snapshot().entities[1].custom_state.mode, EntityVolcanoSwitch.Mode.ON_DOWN)
	assert_eq(run.snapshot().entities[1].custom_state.mode, EntityVolcanoSwitch.Mode.OFF_UP)
	assert_eq(run.snapshot().entities[1].animation.cel, -1)
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0)

func test_paused_falling_animation_and_reset_restore_collision() -> void:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve("VOL_FALLING_PLATFORM")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.volcano = EntityVolcanoDefinition.new()
	definition.volcano.hops_before = 1
	definition.action_lengths = PackedInt32Array([5])
	definition.form_flags = 16
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	run.advance_animations()
	assert_eq(run.snapshot().entities[0].animation.cel, 0)
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var random: SourceRandom = SourceRandom.create(1)
	assert_eq(run.update_custom(0, environment, random, Vector3i.ZERO, true).error, "")
	assert_eq(run.update_custom(0, environment, random, Vector3i.ZERO, false).error, "")
	assert_true(bool(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_COLLISION))
	run.advance_animations()
	assert_eq(run.snapshot().entities[0].animation.cel, 1)
	assert_eq(run.reset_in_level(false, environment), "")
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_COLLISION, 0)
	assert_false(run.snapshot().entities[0].animation.stepping)
	assert_eq(run.snapshot().entities[0].custom_state.count, 0)
