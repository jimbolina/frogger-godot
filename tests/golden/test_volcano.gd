extends GutTest
## Independent frozen Volcano state transitions and source-width boundaries.

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/volcano.json"))

func _result() -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = EntitySnapshot.new()
	result.entity.entity_index = 0
	result.entity.custom_state = EntityCustomState.new()
	result.entity.animation = EntityAnimationState.create(PackedInt32Array([4, 4]))
	result.entity.path = PathSnapshot.new()
	result.environment = EntityEnvironmentState.new()
	result.random = SourceRandom.create(1)
	return result

func _definition(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve(name)
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.action_lengths = PackedInt32Array([4, 4])
	definition.volcano = EntityVolcanoDefinition.new()
	return definition

func _assert_row(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key: String in actual:
		if actual[key] is bool:
			var got: bool = actual[key]
			var want: bool = expected[key]
			assert_eq(got, want, label + " " + key)
		else:
			var got: int = actual[key]
			var want: int = expected[key]
			assert_eq(got, want, label + " " + key)

func test_falling_platform_unsigned_clocks_and_rider_release_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().falling:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		var state: EntityCustomState = result.entity.custom_state
		state.mode = initial.mode
		state.count = initial.hits
		state.timer = initial.timer
		state.texture_animation_paused = initial.paused
		result.entity.animation.stepping = initial.enabled
		result.entity.animation.one_shot = initial.one_shot
		result.entity.entity_flags = EntityDefinition.NO_COLLISION if initial.disabled else 0
		var definition: EntityDefinition = _definition("VOL_FALLING_PLATFORM")
		definition.volcano.hops_before = initial.hops
		definition.authored_delay = initial.delay
		var frog := GameplayState.new()
		frog.attachment.current_entity_index = 0 if initial.attached else -1
		var hit: bool = initial.hit
		assert_eq(EntityVolcanoFallingPlatform.update(definition, result, frog, hit), "")
		_assert_row({"mode": state.mode, "hits": state.count, "timer": state.timer,
			"paused": state.texture_animation_paused, "enabled": result.entity.animation.stepping,
			"one_shot": result.entity.animation.one_shot,
			"disabled": bool(result.entity.entity_flags & EntityDefinition.NO_COLLISION),
			"detach": result.frog_fall_requested, "sound": not result.entity.requests.is_empty()}, expected, str(initial))

func test_switch_debounce_release_and_first_visit_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().switch_updates:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		var state: EntityCustomState = result.entity.custom_state
		state.mode = initial.mode
		state.timer = initial.timer
		var flags: int = initial.flags
		state.initialized = not bool(flags & 1)
		state.no_frog_contact = bool(flags & 2)
		result.entity.animation.action = initial.action
		var definition: EntityDefinition = _definition("VOL_COLOUR_SWITCH")
		definition.volcano.target_ids = PackedInt32Array([27])
		assert_eq(EntityVolcanoSwitch.update(definition, result), "")
		var actual_flags: int = (0 if state.initialized else 1) | (2 if state.no_frog_contact else 0)
		_assert_row({"mode": state.mode, "timer": state.timer, "flags": actual_flags,
			"action": result.entity.animation.action, "initialize": not result.target_effects.is_empty(),
			"sound": not result.entity.requests.is_empty()}, expected, str(initial))

func test_switch_contact_states_and_ordered_requests_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().switch_contacts:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var result: EntityCustomResult = _result()
		var state: EntityCustomState = result.entity.custom_state
		state.mode = initial.mode
		state.timer = initial.timer
		state.initialized = true
		state.no_frog_contact = true
		state.texture_animation_cel = initial.cell
		result.entity.animation.action = initial.action
		result.entity.animation.stepping = initial.enabled
		var definition: EntityDefinition = _definition("VOL_COLOUR_SWITCH")
		definition.volcano.trigger_type = initial.type
		definition.volcano.target_ids = PackedInt32Array([27, -1, 13, 27])
		var frog := GameplayState.new()
		frog.frog.matrix12[10] = initial.matrix_y
		frog.frog.world_position.y = initial.world_y
		frog.frog.target_y = initial.target_y
		assert_eq(EntityVolcanoSwitch.contact(definition, result, frog), "")
		_assert_row({"mode": state.mode, "timer": state.timer,
			"flags": (0 if state.initialized else 1) | (2 if state.no_frog_contact else 0),
			"action": result.entity.animation.action, "cell": state.texture_animation_cel,
			"enabled": result.entity.animation.stepping, "activate": not result.target_effects.is_empty(),
			"nudge": not result.frog_matrix12.is_empty()}, expected, str(initial))
		if expected.activate:
			assert_eq(result.target_effects.size(), 3)
			var ids := PackedInt32Array()
			for effect: EntityTargetEffect in result.target_effects:
				ids.append(effect.unique_id)
				assert_eq(effect.kind, EntityTargetEffect.Kind.REVERSE if initial.type == 1 else EntityTargetEffect.Kind.TOGGLE)
			assert_eq(ids, PackedInt32Array([27, 13, 27]))
		var target := EntitySnapshot.new()
		target.entity_flags = EntityDefinition.NO_MOVEMENT if initial.stopped else 0
		target.path = PathSnapshot.new()
		target.path.flags = (PathStart.ACTIVE if initial.active else 0) | (PathStart.BACKWARDS if initial.backwards else 0)
		if not result.target_effects.is_empty():
			assert_eq(EntityVolcanoTarget.apply(result.target_effects[0], target, definition), "")
		_assert_row({"stopped": bool(target.entity_flags & EntityDefinition.NO_MOVEMENT),
			"active": bool(target.path.flags & PathStart.ACTIVE),
			"backwards": bool(target.path.flags & PathStart.BACKWARDS)}, expected, str(initial))
		var matrix_y: int = frog.frog.matrix12[10] if result.frog_matrix12.is_empty() else result.frog_matrix12[10]
		var expected_y: int = expected.matrix_y
		assert_eq(matrix_y, expected_y)

func test_initial_target_movement_matches_independent_facts() -> void:
	for fixture: Dictionary in _facts().initial_targets:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _definition("MOVING_PLATFORM")
		definition.volcano.initial_movement = initial.initial
		var target := EntitySnapshot.new()
		target.path = PathSnapshot.new() if initial.path else null
		assert_eq(EntityVolcanoTarget.apply(EntityTargetEffect.create(27, EntityTargetEffect.Kind.INITIALIZE), target, definition), "")
		_assert_row({"stopped": bool(target.entity_flags & EntityDefinition.NO_MOVEMENT),
			"active": target.path != null and bool(target.path.flags & PathStart.ACTIVE)}, expected, str(initial))

func test_moving_platform_sound_commands_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().moving:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _definition("MOVING_PLATFORM")
		definition.volcano.play_chain_sound = initial.volcano
		var result: EntityCustomResult = _result()
		result.entity.entity_flags = EntityDefinition.NO_MOVEMENT if initial.stopped else 0
		assert_eq(EntityVolcanoMovingPlatform.update(definition, result), "")
		_assert_row({"play": not result.entity.requests.is_empty(), "stop": result.stop_moving_sound}, expected, str(initial))
		if expected.play:
			assert_eq(result.entity.custom_state.moving_sound, PackedInt32Array([166, 1024, 2048]))

func test_group_allocation_history_matches_independent_facts() -> void:
	for fixture: Dictionary in _facts().allocation:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition := EntityLifecycleDefinition.new()
		var counts: Array = initial.counts
		var selected: Array = initial.selected
		var timers: Array = initial.timers
		var wanted_groups: Array = expected.groups
		var wanted_timers: Array = expected.timers
		definition.polygon_counts = PackedInt32Array(counts)
		var result: MapGroupVisibilityResult = MapGroupAllocation.expand(definition,
			PackedInt32Array(selected), PackedInt32Array(timers))
		assert_eq(result.error, "")
		assert_eq(result.groups, PackedInt32Array(wanted_groups), str(initial))
		assert_eq(result.group_timers, PackedInt32Array(wanted_timers), str(initial))

func test_static_primitive_radius_expansion_matches_independent_facts() -> void:
	for fixture: Dictionary in _facts().radius:
		var initial: Dictionary = fixture.input
		var model := MofFile.new()
		model.kind = MofFile.Kind.STATIC
		var static_model := MofStatic.new()
		var part := MofPart.new()
		var cel := MofPart.Partcel.new()
		cel.bounding_box.resize(24)
		for axis: int in 3:
			cel.bounding_box[axis] = initial.corner[axis]
		part.partcels.append(cel)
		for entry: Dictionary in initial.primitives:
			var primitive := MofPart.Collprim.new()
			primitive.type = entry.shape
			primitive.radius_squared = entry.radius2
			for axis: int in 3:
				primitive.offset[axis] = entry.offset[axis]
				primitive.size[axis] = entry.size[axis]
			part.collprims.append(primitive)
		static_model.parts.append(part)
		model.static_models.append(static_model)
		var form := FormBookEntry.new()
		form.radius_squared = initial.explicit
		var expected: int = fixture.expected
		assert_eq(FormContactSetup._radius_squared(form, model), [expected], str(initial))
