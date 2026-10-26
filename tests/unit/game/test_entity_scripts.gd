extends GutTest
## Source edge cases and ownership for the bounded entity script components.

func _definition(words: PackedInt32Array) -> EntityScriptDefinition:
	var result := EntityScriptDefinition.new()
	result.root_id = 1
	result.programs[1] = words
	result.names[1] = "SCRIPT_TURTLE"
	result.callbacks = {0: "SCRIPT_CB_FROG_TRAFFIC_SPLAT", 1: "SCRIPT_CB_LOG_SPLASH", 2: "SCRIPT_CB_DIVE_COLOUR_CHANGE", 8: "SCRIPT_CB_HIT_TURTLE"}
	return result

func _context() -> EntityUpdateContext:
	var result := EntityUpdateContext.new()
	result.has_path = true
	result.form_id = 21
	return result

func _update(definition: EntityScriptDefinition, state: EntityScriptState, context: EntityUpdateContext = null, animation: EntityAnimationState = null) -> EntityUpdateResult:
	return EntityScriptRunner.update(definition, state, animation if animation != null else EntityAnimationState.create([3, 4]), context if context != null else _context(), SourceRandom.create(1))

func test_prepared_definition_detaches_and_matches_standalone_execution() -> void:
	var definition: EntityScriptDefinition = _definition([11, 3, 1, 7, 0, 0, 12, 5])
	var animation: EntityAnimationState = EntityAnimationState.create([3, 4])
	var context: EntityUpdateContext = _context()
	var prepared: PreparedEntityScript = PreparedEntityScript.create(definition, animation.lengths, context.form_id, context.has_path)
	assert_eq(prepared.error, "")
	var original: EntityUpdateResult = _update(definition, EntityScriptState.create(1))
	definition.programs[1][0] = 999
	definition.names[1] = "UNKNOWN"
	var state: EntityScriptState = EntityScriptState.create(1)
	var random: SourceRandom = SourceRandom.create(1)
	var actual: EntityUpdateResult = EntityScriptRunner.update_prepared(prepared, state, animation, context, random)
	assert_eq(actual.error, "")
	assert_eq(actual.script_state.cursor, original.script_state.cursor)
	assert_eq(actual.script_state.loop_end, original.script_state.loop_end)
	assert_eq(actual.animation.action, original.animation.action)
	assert_eq(state.cursor, 0)
	assert_eq(animation.action, 0)
	actual.script_state.timer = 99
	assert_eq(state.timer, 0)
	assert_ne(_update(definition, state).error, "")

func test_prepared_dependencies_and_runtime_cursor_are_checked() -> void:
	var definition: EntityScriptDefinition = _definition([3, 1, 44, 0, 8, 0, 1, 128, 2048, -1, 9, 38])
	var prepared: PreparedEntityScript = PreparedEntityScript.create(definition, PackedInt32Array([3, 4]), 21, true)
	assert_eq(prepared.error, "")
	var context: EntityUpdateContext = _context()
	var animation: EntityAnimationState = EntityAnimationState.create([3, 4])
	var state: EntityScriptState = EntityScriptState.create(1)
	var random: SourceRandom = SourceRandom.create(1)
	state.cursor = 1
	assert_string_contains(EntityScriptRunner.update_prepared(prepared, state, animation, context, random).error, "cursor")
	state.cursor = 0
	context.form_id = 1
	assert_ne(EntityScriptRunner.update_prepared(prepared, state, animation, context, random).error, "")
	context.form_id = 21
	context.has_path = false
	assert_ne(EntityScriptRunner.update_prepared(prepared, state, animation, context, random).error, "")
	context.has_path = true
	animation.lengths = PackedInt32Array([3])
	assert_ne(EntityScriptRunner.update_prepared(prepared, state, animation, context, random).error, "")
	assert_eq(state.cursor, 0)
	assert_eq(random.draw_count, 0)
	assert_ne(PreparedEntityScript.create(_definition([11, 38]), PackedInt32Array([3]), 21, true).error, "")

func test_stop_timer_wrap_previous_hits_and_repeated_once() -> void:
	var definition: EntityScriptDefinition = _definition([34, 0, 1, 0, 0, 38])
	var original: EntityScriptState = EntityScriptState.create(1)
	original.timer = 65534
	var first: EntityUpdateResult = _update(definition, original)
	assert_eq(first.error, "")
	assert_eq(TickEvent.trace_lines(first.requests), [])
	assert_eq(first.script_state.timer, 65535)
	assert_eq(original.timer, 65534)
	var context: EntityUpdateContext = _context()
	context.previous_hit = true
	var second: EntityUpdateResult = _update(definition, first.script_state, context)
	assert_eq(second.script_state.timer, 0)
	assert_eq(TickEvent.trace_lines(second.requests), ["sound:19:0:0:0"])
	assert_eq(second.script_state.callbacks[0][3], 2)
	var third: EntityUpdateResult = _update(definition, second.script_state, context)
	assert_eq(TickEvent.trace_lines(third.requests), TickEvent.trace_lines(second.requests))
	assert_eq(third.script_state.cursor, first.script_state.cursor)

func test_callbacks_use_slot_order_and_called_source_enum() -> void:
	var definition: EntityScriptDefinition = _definition([34, 1, 1, 0, 0, 34, 0, 8, 0, 0, 38])
	var context: EntityUpdateContext = _context()
	context.previous_hit = true
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context)
	assert_eq(TickEvent.trace_lines(result.requests), ["sound:14:0:0:0", "sound:15:0:0:0", "sound:19:0:0:0"])
	result.script_state.callbacks[0][3] = 3
	var next: EntityUpdateResult = _update(definition, result.script_state, context)
	assert_eq(TickEvent.trace_lines(next.requests), ["sound:19:0:0:0"])

func test_loop_yield_and_action_restart() -> void:
	var definition: EntityScriptDefinition = _definition([11, 3, 1, 7, 0, 0, 12, 5])
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1))
	assert_eq(result.error, "")
	assert_eq(result.script_state.cursor, 1)
	assert_eq(result.script_state.timer, 1)
	assert_eq(result.animation.cel, -1)
	for frame: int in 6:
		result.animation.advance()
	assert_eq(result.animation.cel, 1)
	result = _update(definition, result.script_state, null, result.animation)
	assert_eq(result.animation.cel, -1)

func test_dive_threshold_colour_fade_and_no_display() -> void:
	var definition: EntityScriptDefinition = _definition([34, 1, 2, 7, 1, 8, 0, 1, 128, 2048, -1, 9, 38])
	var context: EntityUpdateContext = _context()
	context.previous_carry = true
	var state: EntityScriptState = EntityScriptState.create(1)
	var result: EntityUpdateResult
	for tick: int in 16:
		result = _update(definition, state, context)
		assert_eq(result.error, "")
		assert_eq(result.script_state.deviation, (tick + 1) * 8)
		assert_eq(result.drown, tick == 15)
		state = result.script_state
	assert_eq(result.matrix12[10], 128)
	assert_eq(state.colours, Vector3i(0, 64, 255))
	assert_eq(state.ambient, Vector3i(64, 64, 192))
	context.no_display = true
	assert_false(_update(definition, state, context).drown)
	context.no_display = false
	context.fade_bounds = PackedInt32Array([1, 2, 1, 2])
	result = _update(definition, state, context)
	assert_true(result.drown)
	assert_false(result.script_state.no_screen_fade)

func test_source_widths_and_logical_sound_owner() -> void:
	var definition: EntityScriptDefinition = _definition([7, 0, -1, 8, 0, 1, 0, 65535, 1, 11, 37, 11, 0, 512, 1024, 44, 0, 12, 5])
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1))
	assert_eq(result.error, "")
	assert_eq(result.script_state.timer, 0)
	assert_eq(result.script_state.deviation, -1)
	assert_eq(TickEvent.trace_lines(result.requests), ["moving:11:512:1024", "sprite:0:-64:-256:1:-16", "sprite:0:-64:0:1:-16", "sprite:0:-64:256:1:-16"])
	var next: EntityUpdateResult = _update(definition, result.script_state)
	assert_eq(next.requests.size(), 3)
	result.script_state.moving_sound.clear()
	var context: EntityUpdateContext = _context()
	context.sound_allocation_enabled = false
	assert_eq(_update(definition, result.script_state, context).requests.size(), 3)
	context.sound_allocation_enabled = true
	assert_eq(_update(definition, result.script_state, context).requests.size(), 4)

func test_random_branch_preserves_root_and_transactional_failure() -> void:
	var definition: EntityScriptDefinition = _definition([11, 13, 0, 6, 2, 2, 12, 5])
	definition.programs[2] = PackedInt32Array([37, 11, 0, 10, 20, 5])
	definition.names[2] = "SCRIPT_ORG_TRUCK_SFX"
	var state: EntityScriptState = EntityScriptState.create(1)
	var rng: SourceRandom = SourceRandom.create(1)
	var result: EntityUpdateResult = EntityScriptRunner.update(definition, state, EntityAnimationState.create([3, 4]), _context(), rng)
	assert_eq(result.error, "")
	assert_eq(result.script_state.root_id, 1)
	assert_gt(result.random.draw_count, 0)
	assert_eq(rng.draw_count, 0)
	assert_eq(state.cursor, 0)
	definition.programs[1] = PackedInt32Array([37, 11, 0, 10, 20, 13, 0, 6, 2, 1, 5])
	result = EntityScriptRunner.update(definition, state, EntityAnimationState.create([3, 4]), _context(), rng)
	assert_string_contains(result.error, "Non-yielding")
	assert_null(result.script_state)
	assert_null(result.random)
	assert_eq(TickEvent.trace_lines(result.requests), [])
	assert_eq(rng.state, 1)

func test_unsupported_instructions_names_operands_and_malformed_loops() -> void:
	var cases: Array[PackedInt32Array] = [PackedInt32Array([999]), PackedInt32Array([3, 9, 38]), PackedInt32Array([11, 38]), PackedInt32Array([12, 38]), PackedInt32Array([11, 11, 12, 12, 5]), PackedInt32Array([0, 1, -1, 38]), PackedInt32Array([34, 0, 99, 0, 0, 38]), PackedInt32Array([7, 0]), PackedInt32Array([7, 0, 1])]
	for words: PackedInt32Array in cases:
		assert_ne(_update(_definition(words), EntityScriptState.create(1)).error, "", str(words))
	var definition: EntityScriptDefinition = _definition([38])
	definition.names[1] = "UNKNOWN"
	assert_ne(_update(definition, EntityScriptState.create(1)).error, "")

func test_entity_run_owns_script_and_animation_snapshots() -> void:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.entity_name = "STATIC"
	definition.behavior = EntityBehaviorCatalog.resolve(definition.entity_name)
	definition.action_lengths = PackedInt32Array([3, 4])
	definition.script_definition = _definition([3, 1, 38])
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	var context: EntityUpdateContext = _context()
	context.has_path = false
	var updated: EntityUpdateResult = run.update_script(0, context, SourceRandom.create(1))
	assert_eq(updated.error, "")
	updated.script_state.timer = 99
	run.advance_animations()
	var saved: EntityRunSnapshot = run.snapshot()
	assert_eq(saved.entities[0].script_state.timer, 1)
	assert_eq(saved.entities[0].animation.cel, 0)
	var clone: EntityRun = run.copy()
	assert_eq(clone.reset(), "")
	assert_eq(clone.snapshot().entities[0].animation.cel, -1)
	assert_eq(run.snapshot().entities[0].animation.cel, 0)

func test_new_instruction_validation_rejects_unsafe_contexts() -> void:
	var malformed: Array[PackedInt32Array] = [PackedInt32Array([10, 13, 65536, 6]), PackedInt32Array([14, 0, 3, 6]), PackedInt32Array([20, 6, 6]), PackedInt32Array([13, 1, 9, 99, 0, 6])]
	for words: PackedInt32Array in malformed:
		assert_ne(_update(_definition(words), EntityScriptState.create(1)).error, "", str(words))
	var context: EntityUpdateContext = _context()
	context.has_path = false
	for opcode: int in [2, 15, 16]:
		assert_ne(_update(_definition(PackedInt32Array([opcode, 6])), EntityScriptState.create(1), context).error, "")
	assert_ne(_update(_definition([1, 6]), EntityScriptState.create(1), context, EntityAnimationState.create([])).error, "")

func test_path_and_random_requests_disappear_on_late_script_failure() -> void:
	var definition: EntityScriptDefinition = _definition([15, 10, 13, 2, 5])
	var state: EntityScriptState = EntityScriptState.create(1)
	var random: SourceRandom = SourceRandom.create(1)
	var result: EntityUpdateResult = EntityScriptRunner.update(definition, state, EntityAnimationState.create([3]), _context(), random)
	assert_string_contains(result.error, "Non-yielding")
	assert_eq(result.path_active_request, -1)
	assert_null(result.script_state)
	assert_null(result.random)
	assert_eq(result.requests.size(), 0)
	assert_eq(state.cursor, 0)
	assert_eq(random.state, 1)
