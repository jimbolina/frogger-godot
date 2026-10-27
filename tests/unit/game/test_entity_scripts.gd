extends GutTest
## Source edge cases and ownership for the bounded entity script components.

func _definition(words: PackedInt32Array) -> EntityScriptDefinition:
	var result := EntityScriptDefinition.new()
	result.root_id = 1
	result.programs[1] = words
	result.names[1] = "SCRIPT_TURTLE"
	result.callbacks = {0: EntityScriptDefinition.CallbackKind.FROG_TRAFFIC_SPLAT, 1: EntityScriptDefinition.CallbackKind.LOG_SPLASH, 2: EntityScriptDefinition.CallbackKind.DIVE_COLOUR_CHANGE, 8: EntityScriptDefinition.CallbackKind.HIT_TURTLE}
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
	assert_eq(EntityScriptRunner.update_prepared(prepared, state, animation, context, random).error, "")
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
	definition.names[1] = ""
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

func test_named_programs_are_admitted_by_dependencies() -> void:
	var definition: EntityScriptDefinition = _definition([13, 0, 9, 2, 0, 6])
	definition.names[1] = "SCRIPT_GEN_BUTTERFLY"
	definition.names[2] = "SCRIPT_ORG_SNAKE_SFX"
	definition.programs[2] = PackedInt32Array([4, 13, 6])
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1))
	assert_eq(result.error, "")
	assert_eq(TickEvent.trace_lines(result.requests), ["sound:13:0:0:0"])
	definition.programs[2] = PackedInt32Array([999, 6])
	assert_ne(_update(definition, EntityScriptState.create(1)).error, "")

func test_rotation_wait_stop_and_condition_use_all_axes() -> void:
	var definition: EntityScriptDefinition = _definition([17, 0, 1024, 512, -1, 18, 13, 0, 3, 2, 0, 6])
	definition.names[2] = "SCRIPT_ROTATION_FINISHED"
	definition.programs[2] = PackedInt32Array([17, 2, 0, 256, 10, 29, 6])
	var state: EntityScriptState = EntityScriptState.create(1)
	for tick: int in 3:
		var result: EntityUpdateResult = _update(definition, state)
		assert_eq(result.error, "")
		state = result.script_state
		assert_eq(state.angles.x, mini(tick + 1, 2) * 512)
	assert_eq(state.angular_counts, Vector3i.ZERO)
	assert_eq(state.angles.z, 0)
	assert_false(state.active)

func test_three_axis_register_deviation_return_and_clear() -> void:
	var definition: EntityScriptDefinition = _definition([31, 12, 3, 8, 1, 0, 0, 1, 2, 8, 0, 5, -8, 1024, -1, 9, 33, 0, 3, 1024, 9, 32, 6])
	definition.payload_offset = 12
	definition.payload_registers = PackedInt32Array([8, 1024, 0])
	var first: EntityUpdateResult = _update(definition, EntityScriptState.create(1))
	assert_eq(first.error, "")
	assert_eq(first.script_state.offsets, Vector3i(4, 0, -4))
	var state: EntityScriptState = first.script_state
	for tick: int in 5:
		var result: EntityUpdateResult = _update(definition, state)
		assert_eq(result.error, "")
		state = result.script_state
	assert_eq(state.offsets, Vector3i.ZERO)
	assert_eq(state.counts, Vector3i.ZERO)
	assert_false(state.active)

func test_new_motion_rejects_invalid_axes_and_rolls_back() -> void:
	var malformed: Array[PackedInt32Array] = [PackedInt32Array([17, 3, 0, 1, 1, 6]), PackedInt32Array([8, 0, 6, 0, 1, 1, 6]), PackedInt32Array([33, 1, 3, 0, 6])]
	for words: PackedInt32Array in malformed:
		assert_ne(_update(_definition(words), EntityScriptState.create(1)).error, "")
	var state: EntityScriptState = EntityScriptState.create(1)
	var result: EntityUpdateResult = _update(_definition([17, 0, 0, 128, 5, 8, 0, 0, 10, 256, 5, 5]), state)
	assert_string_contains(result.error, "Non-yielding")
	assert_null(result.script_state)
	assert_eq(state.angular_counts, Vector3i.ZERO)
	assert_eq(state.counts, Vector3i.ZERO)

func test_start_script_changes_restart_root_without_branching_or_resetting() -> void:
	var definition: EntityScriptDefinition = _definition([25, 2, 4, 13, 0, 0, 2, 5])
	definition.programs[2] = PackedInt32Array([4, 15, 38])
	definition.names[2] = "restart_destination"
	var state: EntityScriptState = EntityScriptState.create(1)
	var first: EntityUpdateResult = _update(definition, state)
	assert_eq(first.error, "")
	assert_eq(first.script_state.root_id, 2)
	assert_eq(first.script_state.program_id, 1)
	assert_eq(TickEvent.trace_lines(first.requests), ["sound:13:0:0:0"])
	assert_eq(state.root_id, 1)
	var second: EntityUpdateResult = _update(definition, first.script_state)
	var third: EntityUpdateResult = _update(definition, second.script_state)
	assert_eq(third.script_state.program_id, 2)
	assert_eq(TickEvent.trace_lines(third.requests), ["sound:15:0:0:0"])
	definition.programs.erase(2)
	assert_string_contains(_update(definition, state).error, "restart target")

func test_source_award_instructions_are_noops_even_with_carried_frog() -> void:
	var definition: EntityScriptDefinition = _definition([26, 999, 27, -1, 28, 2147483647, 6])
	var context: EntityUpdateContext = _context()
	context.previous_carry = true
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context)
	assert_eq(result.error, "")
	assert_eq(result.requests.size(), 0)
	assert_eq(result.random.draw_count, 0)
	assert_false(result.script_state.active)

func test_change_animation_narrows_action_and_respects_model_and_display() -> void:
	var definition: EntityScriptDefinition = _definition([43, 65537, 38])
	var context: EntityUpdateContext = _context()
	var animation: EntityAnimationState = EntityAnimationState.create([3, 4])
	animation.cel = 2
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context, animation)
	assert_eq(result.error, "")
	assert_eq(result.animation.action, 1)
	assert_eq(result.animation.cel, -1)
	assert_eq(animation.cel, 2)
	context.no_display = true
	result = _update(definition, EntityScriptState.create(1), context, animation)
	assert_eq(result.animation.action, 0)
	assert_eq(result.animation.cel, 2)
	context.no_display = false
	result = _update(definition, EntityScriptState.create(1), context, EntityAnimationState.create([]))
	assert_eq(result.error, "")
	assert_eq(result.animation.action, -1)

func test_mutate_colour_uses_pre_deviation_height_and_byte_storage() -> void:
	var definition: EntityScriptDefinition = _definition([39, 38])
	var context: EntityUpdateContext = _context()
	context.base_matrix[10] = -512
	var state: EntityScriptState = EntityScriptState.create(1)
	state.offsets.y = 100
	var result: EntityUpdateResult = _update(definition, state, context)
	assert_eq(result.error, "")
	assert_eq(result.script_state.colours, Vector3i(32, 96, 128))
	assert_eq(result.script_state.ambient, Vector3i(64, 128, 192))
	assert_eq(result.matrix12[10], -412)
	context.no_display = true
	assert_eq(_update(definition, state, context).script_state.colours, Vector3i.ZERO)

func test_helium_callback_branches_after_instructions_and_preserves_root() -> void:
	var definition: EntityScriptDefinition = _definition([34, 0, 11, 0, 1, 38])
	definition.callbacks[11] = EntityScriptDefinition.CallbackKind.SKY_HELIUM_BALLOON
	definition.callback_programs[11] = 2
	definition.programs[2] = PackedInt32Array([4, 13, 38])
	definition.names[2] = "SCRIPT_SKY_HELIUM_BALLOON_RISING"
	var context: EntityUpdateContext = _context()
	context.previous_hit = true
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context)
	assert_eq(result.error, "")
	assert_eq(result.script_state.root_id, 1)
	assert_eq(result.script_state.program_id, 2)
	assert_eq(result.script_state.cursor, 0)
	assert_eq(result.requests.size(), 0)
	context.previous_hit = false
	result = _update(definition, result.script_state, context)
	assert_eq(TickEvent.trace_lines(result.requests), ["sound:13:0:0:0"])
	definition.callback_programs.clear()
	assert_ne(_update(definition, EntityScriptState.create(1), context).error, "")

func test_hippo_and_mechanism_deaths_preserve_callback_order() -> void:
	var definition: EntityScriptDefinition = _definition([34, 0, 12, 7, 1, 34, 1, 13, 7, 1, 38])
	definition.callbacks[12] = EntityScriptDefinition.CallbackKind.JUN_HIPPO_DIVE
	definition.callbacks[13] = EntityScriptDefinition.CallbackKind.VOL_MECHANISM
	var context: EntityUpdateContext = _context()
	context.previous_carry = true
	context.authored_matrix[10] = 128
	var state: EntityScriptState = EntityScriptState.create(1)
	state.offsets.y = 128
	var result: EntityUpdateResult = _update(definition, state, context)
	assert_eq(result.error, "")
	assert_eq(result.frog_deaths, PackedInt32Array([FrogAnimationCatalog.DROWN]))
	assert_eq(result.script_state.colours, Vector3i(64, 64, 255))
	context.authored_matrix[10] = 160
	result = _update(definition, state, context)
	assert_eq(result.frog_deaths, PackedInt32Array([FrogAnimationCatalog.DROWN]))
	context.no_display = true
	assert_true(_update(definition, state, context).frog_deaths.is_empty())

func test_new_script_effects_are_discarded_when_later_execution_fails() -> void:
	var definition: EntityScriptDefinition = _definition([39, 43, 1, 5])
	var state: EntityScriptState = EntityScriptState.create(1)
	var animation: EntityAnimationState = EntityAnimationState.create([3, 4])
	var result: EntityUpdateResult = _update(definition, state, null, animation)
	assert_string_contains(result.error, "Non-yielding")
	assert_null(result.script_state)
	assert_null(result.animation)
	assert_eq(state.colours, Vector3i.ZERO)
	assert_eq(animation.action, 0)

func test_static_matrix_motion_uses_authored_pose_without_accumulating() -> void:
	var definition: EntityScriptDefinition = _definition([35, 1, 17, 0, 0, 1024, 1, 8, 0, 0, 0, 256, 2, 38])
	var context: EntityUpdateContext = _context()
	assert_string_contains(_update(definition, EntityScriptState.create(1), context).error, "authored matrix payload")
	context.has_path = false
	context.authored_matrix = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 20, 30, 40])
	context.base_matrix = context.authored_matrix.duplicate()
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context)
	assert_eq(result.error, "")
	assert_eq(result.matrix12, PackedInt32Array([0, 0, 4096, 4096, 0, 0, 0, 4096, 0, 21, 30, 40]))
	context.base_matrix = result.matrix12.duplicate()
	result = _update(definition, result.script_state, context)
	assert_eq(result.matrix12, PackedInt32Array([0, 0, 4096, 4096, 0, 0, 0, 4096, 0, 22, 30, 40]))

func test_collision_flags_can_clear_authored_flags_and_survive_next_tick() -> void:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.flags = EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY
	definition.behavior = EntityBehaviorCatalog.resolve("STATIC")
	definition.script_definition = _definition([48, 38])
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	var updated: EntityUpdateResult = run.update_script(0, EntityUpdateContext.new(), SourceRandom.create(1))
	assert_eq(updated.error, "")
	assert_eq(updated.entity_flags, EntityDefinition.NO_DISPLAY)
	var pose: EntitySnapshot = run.snapshot().entities[0]
	assert_eq(pose.effective_flags(definition.flags), EntityDefinition.NO_DISPLAY)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].effective_flags(definition.flags), EntityDefinition.NO_DISPLAY)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().entities[0].effective_flags(0), definition.flags)
	var context: EntityUpdateContext = _context()
	context.entity_flags = EntityDefinition.NO_DISPLAY
	updated = _update(_definition([47, 24, 38]), EntityScriptState.create(1), context)
	assert_eq(updated.entity_flags, EntityDefinition.NO_COLLISION | EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY)
	assert_eq(context.entity_flags, EntityDefinition.NO_DISPLAY)

func test_appear_precedes_motion_and_clears_visibility_and_collision_flags() -> void:
	var definition: EntityScriptDefinition = _definition([23, 38])
	var context: EntityUpdateContext = _context()
	context.entity_flags = EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY
	var state: EntityScriptState = EntityScriptState.create(1)
	state.position = Vector3i(10, 20, 30)
	state.offsets = Vector3i(1, 2, 3)
	var result: EntityUpdateResult = _update(definition, state, context)
	assert_eq(result.error, "")
	assert_eq(result.entity_flags, EntityDefinition.NO_DISPLAY)
	assert_eq(result.matrix12.slice(9), PackedInt32Array([11, 22, 33]))
	state.entity_type = 1
	context.authored_matrix[9] = 100
	result = _update(definition, state, context)
	assert_eq(result.matrix12.slice(9), PackedInt32Array([101, 2, 3]))

func test_checkpoint_script_selection_and_collision_are_detached() -> void:
	var context: EntityUpdateContext = _context()
	context.environment = EntityEnvironmentState.new()
	for index: int in 5:
		context.environment.checkpoint_positions.append(Vector3i(index * 100, 20, 30))
	context.environment.collected = 30
	var definition: EntityScriptDefinition = _definition([22, 23, 38])
	var result: EntityUpdateResult = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([3, 4]), context, SourceRandom.create(5))
	assert_eq(result.error, "")
	assert_eq(result.random.draw_count, 2)
	assert_eq(result.script_state.position, Vector3i(0, 20, 30))
	assert_eq(result.environment.collision_disabled, 1)
	assert_eq(context.environment.collision_disabled, 0)
	context.environment.collected = 31
	result = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([3, 4]), context, SourceRandom.create(5))
	assert_eq(result.script_state.position, Vector3i(0, -20000, 0))
	assert_eq(result.environment.collision_disabled, 0)
	assert_eq(result.random.draw_count, 2)
	context.environment.collision_disabled = 31
	result = _update(_definition([41, 38]), EntityScriptState.create(1), context)
	assert_eq(result.environment.collision_disabled, 0)
	assert_true(result.checkpoint_collision_changed)
	assert_eq(context.environment.collision_disabled, 31)
	definition = _definition([22, 24, 5])
	result = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([3, 4]), context, SourceRandom.create(5))
	assert_string_contains(result.error, "Non-yielding")
	assert_null(result.environment)
	assert_null(result.random)

func test_script_and_callback_frog_effects_keep_source_notification_order() -> void:
	var definition: EntityScriptDefinition = _definition([4, 13, 42, 2, 14, 34, 0, 13, 7, 1, 34, 1, 1, 7, 1, 38])
	definition.callbacks[13] = EntityScriptDefinition.CallbackKind.VOL_MECHANISM
	var context: EntityUpdateContext = _context()
	context.previous_carry = true
	var result: EntityUpdateResult = _update(definition, EntityScriptState.create(1), context)
	assert_eq(result.error, "")
	assert_eq(result.effects.size(), 5)
	assert_eq(result.effects[0].notification.sound_id, 13)
	assert_eq(result.effects[1].death_animation, FrogAnimationCatalog.SQUISHED)
	assert_eq(result.effects[2].notification.sound_id, 14)
	assert_eq(result.effects[3].death_animation, FrogAnimationCatalog.SQUISHED)
	assert_eq(result.effects[4].notification.sound_id, 19)
	context.previous_carry = false
	result = _update(definition, EntityScriptState.create(1), context)
	assert_eq(result.effects.size(), 2)
	assert_eq(result.frog_deaths.size(), 0)
	assert_ne(_update(_definition([42, 99, 0, 38]), EntityScriptState.create(1)).error, "")

func test_ejection_preserves_operand_meaning_and_order_without_mutating_input() -> void:
	var definition: EntityScriptDefinition = _definition([4, 19, 21, 0, 2, 12, 42, FrogAnimationCatalog.DROWN, 0, 38])
	var context: EntityUpdateContext = _context()
	context.previous_carry = true
	var state: EntityScriptState = EntityScriptState.create(1)
	var result: EntityUpdateResult = _update(definition, state, context)
	assert_eq(result.error, "")
	assert_eq(result.effects.size(), 3)
	assert_true(result.effects[1].eject)
	assert_eq(result.effects[1].grid_delta, 2)
	assert_eq(result.effects[1].jump_duration, 12)
	assert_eq(result.effects[2].death_animation, FrogAnimationCatalog.DROWN)
	assert_eq(state.cursor, 0)
	context.previous_carry = false
	result = _update(definition, state, context)
	assert_eq(result.effects.size(), 1)

func test_pop_is_once_per_live_instance_and_failure_discards_effects() -> void:
	var definition: EntityScriptDefinition = _definition([46, 46, 38])
	var context: EntityUpdateContext = _context()
	var state: EntityScriptState = EntityScriptState.create(1)
	var result: EntityUpdateResult = _update(definition, state, context)
	assert_eq(result.error, "")
	assert_true(result.pop_started)
	assert_eq(result.requests.size(), 1)
	assert_eq(result.random.draw_count, 0)
	context.pop_allocated = true
	result = _update(definition, state, context)
	assert_false(result.pop_started)
	assert_eq(result.requests.size(), 0)
	context.pop_allocated = false
	definition.programs[1] = PackedInt32Array([46, 5])
	result = _update(definition, state, context)
	assert_string_contains(result.error, "Non-yielding")
	assert_false(result.pop_started)
	assert_eq(result.requests.size(), 0)
	assert_eq(state.cursor, 0)

func test_pitch_bend_requires_logical_sound_and_rejects_unsafe_shifts() -> void:
	var definition: EntityScriptDefinition = _definition([45, 0, 32, 96, 5, 7, 64, 38])
	var state: EntityScriptState = EntityScriptState.create(1)
	state.timer = 32
	var result: EntityUpdateResult = _update(definition, state)
	assert_eq(result.error, "")
	assert_eq(result.requests.size(), 0)
	state.moving_sound = PackedInt32Array([1, 0, 1024])
	result = _update(definition, state)
	assert_eq(result.error, "")
	assert_eq(result.requests[0].pitch, 32)
	assert_eq(result.requests[0].copy().pitch, 32)
	definition.programs[1][4] = 32
	result = _update(definition, state)
	assert_string_contains(result.error, "Unsafe pitch-bend")
	assert_null(result.script_state)
	assert_eq(result.requests.size(), 0)
	assert_eq(state.timer, 32)
