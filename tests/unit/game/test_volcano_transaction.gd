extends GutTest
## Late aggregate rejection restores Volcano target cursors and continuation.

class RejectFinal extends TickGuard:
	func check(phase: Phase, _candidate: TickGuardCandidate) -> String:
		return "Volcano final rejected" if phase == Phase.FINAL else ""

func _level() -> LevelDefinition:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.spawn_cell = Vector2i(1, 1)
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	level.camera.source_offset = Vector3i(0, -512, -512)
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(4096, 4096)
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	var names := PackedStringArray(["MOVING_PLATFORM", "VOL_COLOUR_SWITCH", "VOL_FALLING_PLATFORM"])
	for index: int in names.size():
		var entity := EntityDefinition.new()
		entity.entity_index = index
		entity.unique_id = 20 + index
		entity.flags = EntityDefinition.NO_COLLISION
		entity.behavior = EntityBehaviorCatalog.resolve(names[index])
		entity.behavior.execution = EntityBehavior.Execution.CONTACT
		entity.volcano = EntityVolcanoDefinition.new()
		entity.action_lengths = PackedInt32Array([4, 4])
		if index == 0:
			entity.volcano.initial_movement = 1
			entity.path_definition = PathDefinition.new()
			var segment := PathSegmentDefinition.new()
			segment.segment_type = PathSegmentDefinition.LINE
			segment.length = 100
			segment.end = Vector3i(100, 0, 0)
			entity.path_definition.segments.append(segment)
			entity.path_start = PathStart.new()
			entity.path_start.speed = 10
		elif index == 1:
			entity.volcano.target_ids = PackedInt32Array([20])
		var contact := FormContactDefinition.new()
		contact.entity_index = index
		contact.unique_id = entity.unique_id
		contact.form_id = entity.form_id
		contact.form_grid_id = entity.form_grid_id
		contact.entity_flags = entity.flags
		contact.has_form_data = false
		collision.entities.append(entity)
		collision.contacts.append(contact)
	level.entity_collision = collision
	for sound_id: int in [171, 173]:
		var sample := LogicalSoundDefinition.new()
		sample.sound_id = sound_id
		sample.frame_count = 30
		level.sounds.append(sample)
	return level

func _prime(run: GameplayRun) -> void:
	var trigger: EntitySnapshot = run._entities._state.entities[1]
	trigger.custom_state.mode = EntityVolcanoSwitch.Mode.ON_DOWN
	trigger.custom_state.timer = 1
	trigger.custom_state.no_frog_contact = true
	trigger.animation.select(0)
	var falling: EntitySnapshot = run._entities._state.entities[2]
	falling.custom_state.mode = EntityVolcanoFallingPlatform.Mode.WAITING_TO_FALL
	falling.custom_state.timer = 0
	run._state.entities = run._entities.snapshot()

func test_final_rejection_restores_switch_target_collapse_and_retry() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var clean: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	assert_eq(clean.error, "")
	if not run.error.is_empty() or not clean.error.is_empty():
		return
	_prime(run)
	_prime(clean)
	var command := TickCommand.new()
	var expected: TickResult = clean.step(command)
	assert_eq(expected.error, "")
	if not expected.error.is_empty():
		return
	var entities: Array[EntitySnapshot] = expected.final_snapshot.entities.entities
	assert_eq(entities[0].path.position.x, 10)
	assert_false(bool(entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(entities[1].custom_state.mode, EntityVolcanoSwitch.Mode.ON_UP)
	assert_eq(entities[1].custom_state.timer, 6)
	assert_eq(entities[1].animation.action, 1)
	assert_true(entities[1].custom_state.initialized)
	assert_eq(entities[2].custom_state.mode, EntityVolcanoFallingPlatform.Mode.FALLING)
	assert_true(entities[2].animation.stepping)
	var before: String = ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true))
	run._tick_guard = RejectFinal.new()
	var failed: TickResult = run.step(command)
	assert_eq(failed.error, "Volcano final rejected")
	assert_null(failed.final_snapshot)
	assert_true(failed.events.is_empty())
	assert_true(failed.rng_consumers.is_empty())
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), before)
	run._tick_guard = null
	var retry: TickResult = run.step(command)
	assert_eq(retry.error, "")
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(retry.final_snapshot, true)),
		ZoneLifecycleChecks.canonical(TerrainTrace.facts(expected.final_snapshot, true)))
	assert_eq(TickEvent.trace_lines(retry.events), TickEvent.trace_lines(expected.events))

func test_jump_reads_nudged_matrix_height_without_rewriting_fixed_position() -> void:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var state: GameplayState = run.snapshot()
	var height: int = state.frog.matrix12[10]
	state.frog.matrix12[10] = height - 32
	var original_position: Vector3i = state.frog.position_16
	var events: Array[TickEvent] = []
	assert_eq(run._frog.jump(state, 0, events), "")
	assert_eq(state.frog.position_16, original_position)
	@warning_ignore("integer_division")
	var expected_velocity: int = (32 << 16) / 7 - ((Frog.GRAVITY_16 * 7) >> 1)
	assert_eq(state.frog.velocity_16.y, expected_velocity)

func test_completed_run_retains_pending_demo_tick_in_rejection() -> void:
	var run: GameplayRun = GameplayRun.create(TerrainScenario.builtin("normal").level)
	run._state.tick_index = 12
	run._state.completed = true
	var session := DemoPlaybackSession.new()
	session.configure(30, PackedByteArray([128]))
	var result: TickResult = run.step(session.command(12))
	assert_eq(result.tick_index, 12)
	assert_string_contains(session.accept(result), "Terrain run completed")
	assert_eq(session.elapsed_ticks, 0)
	assert_eq(session.input_cursor, 0)
