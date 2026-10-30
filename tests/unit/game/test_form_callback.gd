extends GutTest
## SwpCrusherCallback bounce-back over synthetic grids, Swamp candidate dispatch, the trigger callback and a whole collision tick.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]

func _grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(3, 3)
	grid.base = Vector2i(-384, -384)
	for index: int in 9:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = GridSquareFlags.USABLE | GridSquareFlags.SAFE
		var x: int = -384 + (index % 3) * 256
		@warning_ignore("integer_division")
		var z: int = -384 + (index / 3) * 256
		square.vertices.assign([Vector3i(x, -64, z + 256), Vector3i(x + 256, -64, z + 256), Vector3i(x, -64, z), Vector3i(x + 256, -64, z)])
		grid.squares.append(square)
	return grid

func _state(mode: int, direction: int) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = mode
	state.frog.direction = direction
	state.frog.cell = Vector2i(1, 1)
	state.frog.square_index = 4
	state.frog.position_16 = Vector3i(10, -20, 30) * 65536
	state.frog.matrix12[9] = 10
	state.frog.matrix12[10] = -20
	state.frog.matrix12[11] = 30
	state.frog.target_y = -50
	state.frog.old_y = 77
	state.frog.target_16 = Vector3i(1, 2, 3)
	return state

func test_retail_address_resolves_by_function_name() -> void:
	assert_eq(FormCallbackCatalog.NAMES[0x4241c0], "SwpCrusherCallback")
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x4241c0), FormCallback.Kind.CRUSHER_BOUNCE_BACK)
	assert_eq(FormCallbackCatalog.resolve("unknown", 0x4241c0), FormCallback.Kind.UNKNOWN)

func test_step_reverses_each_facing_and_keeps_an_unknown_one() -> void:
	assert_eq(FormCallback.crusher_step(0), Vector3i(0, -1, 2))
	assert_eq(FormCallback.crusher_step(1), Vector3i(-1, 0, 3))
	assert_eq(FormCallback.crusher_step(2), Vector3i(0, 1, 0))
	assert_eq(FormCallback.crusher_step(3), Vector3i(1, 0, 1))
	assert_eq(FormCallback.crusher_step(5), Vector3i(0, 0, 5))

func test_normal_mode_jumps_back_one_cell_from_the_collision_primitive() -> void:
	var state: GameplayState = _state(FrogMode.JUMPING, 0)
	state.frog.flags |= FrogFlags.JUMP_TO_ENTITY
	assert_eq(FormCallback.crusher_bounce_back(_grid(), state, 8), "")
	assert_eq(state.frog.cell, Vector2i(1, 0))
	assert_eq(state.frog.square_index, 1)
	assert_eq(state.frog.direction, 2)
	assert_eq(state.frog.mode, FrogMode.JUMPING)
	assert_eq(state.frog.flags, FrogFlags.ACTIVE | FrogFlags.CONTROL_ACTIVE | FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_FROM_COLLPRIM)
	assert_eq(state.attachment.forbidden_entity_index, 8)
	assert_eq(state.frog.remaining_ticks, 6)
	assert_eq(state.frog.old_y, -50)
	assert_eq(state.frog.target_y, -50)
	assert_eq(state.frog.target_16, Vector3i(0, 2, -256 * 65536))
	assert_eq(state.frog.velocity_16, Vector3i(-109226, -3950884, -3123882))
	assert_eq(state.frog.position_16, Vector3i(10, -20, 30) * 65536, "only the transform translation is pushed")
	assert_eq(state.frog.matrix12.slice(9, 12), PackedInt32Array([6, -20, -66]))

func test_user_mode_retargets_the_slide_without_changing_mode_or_facing() -> void:
	var state: GameplayState = _state(FrogMode.BOUNCE, 1)
	assert_eq(FormCallback.crusher_bounce_back(_grid(), state, 8), "")
	assert_eq(state.frog.cell, Vector2i(0, 1))
	assert_eq(state.frog.square_index, 3)
	assert_eq(state.frog.direction, 1)
	assert_eq(state.frog.mode, FrogMode.BOUNCE)
	assert_eq(state.frog.flags, FrogFlags.ACTIVE | FrogFlags.CONTROL_ACTIVE)
	assert_eq(state.attachment.forbidden_entity_index, -1)
	assert_eq(state.frog.remaining_ticks, 6)
	assert_eq(state.frog.old_y, 77)
	assert_eq(state.frog.target_16, Vector3i(-256, -64, 0) * 65536)
	assert_eq(state.frog.velocity_16, Vector3i(-2905429, -480597, -327680))
	assert_eq(state.frog.matrix12.slice(9, 12), PackedInt32Array([10, -20, 30]))

func test_only_the_first_square_of_the_target_stack_is_considered() -> void:
	var grid: GridDefinition = _grid()
	var stack: GridStackDefinition = grid.stacks[1]
	stack.square_count = 2
	stack.first_square_index = grid.squares.size()
	var blocked := GridSquareDefinition.new()
	blocked.vertices.assign(grid.squares[1].vertices)
	grid.squares.append(blocked)
	grid.squares.append(grid.squares[1])
	var state: GameplayState = _state(FrogMode.JUMPING, 0)
	var before: String = JSON.stringify(TerrainTrace.facts(state, true))
	assert_eq(FormCallback.crusher_bounce_back(grid, state, 8), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(state, true)), before)
	assert_eq(state.attachment.forbidden_entity_index, -1)
	stack.square_count = 0
	assert_eq(FormCallback.crusher_bounce_back(grid, state, 8), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(state, true)), before)

func test_target_outside_the_grid_is_an_explicit_error() -> void:
	var state: GameplayState = _state(FrogMode.JUMPING, 0)
	state.frog.cell = Vector2i(1, 0)
	assert_string_contains(FormCallback.crusher_bounce_back(_grid(), state, 8), "outside authored storage")

func test_fly_score_callback_applies_the_reward_and_reports_it() -> void:
	var frog := Frog.new()
	frog.grid = _grid()
	while frog.rewards.size() < 9:
		frog.rewards.append(RewardDefinition.new())
	frog.rewards[8].flags = RewardDefinition.SCORE
	frog.rewards[8].value = 200
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	var events: Array[TickEvent] = []
	assert_eq(FormCallback.apply(FormCallback.Kind.ORG_FLY_SCORE, frog, state, 7, events), "")
	assert_eq(state.flow.score, 200)
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, TickEvent.Kind.REWARD)
	assert_eq(events[0].reward_id, 8)
	assert_eq(events[0].entity_index, 7)

func test_apply_dispatches_without_the_active_guard() -> void:
	var frog := Frog.new()
	frog.grid = _grid()
	frog.theme = 4
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	state.frog.flags &= ~FrogFlags.ACTIVE
	var events: Array[TickEvent] = []
	assert_eq(FormCallback.apply(FormCallback.Kind.CRUSHER_BOUNCE_BACK, frog, state, 3, events), "")
	assert_eq(state.frog.cell, Vector2i(1, 2))
	assert_eq(state.frog.direction, 0)
	assert_eq(state.attachment.forbidden_entity_index, 3)
	assert_true(events.is_empty())

func _swamp_frog() -> Frog:
	var crusher := EntityDefinition.new()
	crusher.entity_name = "SWP_CRUSHER"
	crusher.behavior = EntityBehaviorCatalog.resolve(crusher.entity_name)
	crusher.behavior.execution = EntityBehavior.Execution.UPDATE
	crusher.entity_index = 3
	crusher.swamp = EntitySwampDefinition.new()
	crusher.swamp.delay = 10
	var frog := Frog.new()
	frog.grid = _grid()
	frog.theme = FormCallback.SWAMP_THEME
	frog.candidate_entities = EntityRun.create([crusher])
	frog.entity_collision = EntityCollisionDefinition.new()
	var contact := FormContactDefinition.new()
	contact.entity_index = 3
	contact.has_form_data = false
	frog.entity_collision.contacts.append(contact)
	return frog

func test_swamp_apply_runs_the_candidate_crusher_callback_and_publishes_its_count() -> void:
	var frog: Frog = _swamp_frog()
	assert_eq(frog.candidate_entities.error, "")
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	state.frog.flags &= ~FrogFlags.ACTIVE
	var events: Array[TickEvent] = []
	assert_eq(FormCallback.apply(FormCallback.Kind.CRUSHER_BOUNCE_BACK, frog, state, 3, events), "")
	assert_eq(state.frog.cell, Vector2i(1, 2))
	assert_eq(state.frog.direction, 0)
	assert_eq(state.attachment.forbidden_entity_index, 3)
	assert_eq(state.entities.entities[0].custom_state.count, 5)
	assert_eq(frog.candidate_entities.snapshot().entities[0].custom_state.count, 5)
	var repeat: GameplayState = _state(FrogMode.JUMPING, 2)
	assert_eq(FormCallback.apply(FormCallback.Kind.CRUSHER_BOUNCE_BACK, frog, repeat, 3, events), "")
	assert_eq(repeat.frog.cell, Vector2i(1, 1), "the debounce count ignores the second hit")
	assert_eq(repeat.attachment.forbidden_entity_index, -1)
	assert_true(events.is_empty())

func test_swamp_apply_requires_candidate_entities_and_a_live_crusher() -> void:
	var frog: Frog = _swamp_frog()
	var events: Array[TickEvent] = []
	assert_string_contains(FormCallback.apply(FormCallback.Kind.CRUSHER_BOUNCE_BACK, frog, _state(FrogMode.JUMPING, 2), 4, events), "crusher")
	frog.candidate_entities = null
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	assert_string_contains(FormCallback.apply(FormCallback.Kind.CRUSHER_BOUNCE_BACK, frog, state, 3, events), "candidate")
	assert_eq(state.frog.cell, Vector2i(1, 1))
	assert_null(state.entities)

func _trigger_frog() -> Frog:
	var platform := EntityDefinition.new()
	platform.entity_index = 2
	platform.unique_id = 21
	platform.flags = EntityDefinition.NO_MOVEMENT
	platform.behavior = EntityBehaviorCatalog.resolve("MOVING_PLATFORM")
	platform.behavior.execution = EntityBehavior.Execution.UPDATE
	platform.volcano = EntityVolcanoDefinition.new()
	platform.path_definition = PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.end = Vector3i(100, 0, 0)
	platform.path_definition.segments.append(segment)
	platform.path_start = PathStart.new()
	var trigger := EntityDefinition.new()
	trigger.entity_index = 3
	trigger.behavior = EntityBehaviorCatalog.resolve("TRIGGER")
	trigger.behavior.execution = EntityBehavior.Execution.UPDATE
	trigger.trigger = EntityTriggerDefinition.new()
	trigger.trigger.trigger_type = EntityTrigger.Type.BEGIN
	trigger.trigger.target_ids = PackedInt32Array([21, -1, -1, -1, -1, -1, -1, -1, -1, -1])
	var frog := Frog.new()
	frog.grid = _grid()
	frog.candidate_entities = EntityRun.create([platform, trigger])
	return frog

func test_trigger_address_resolves_by_function_name() -> void:
	assert_eq(FormCallbackCatalog.NAMES[0x42ba00], "TriggerEntityCallback")
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x42ba00), FormCallback.Kind.TRIGGER)
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e-edited", 0x42ba00), FormCallback.Kind.UNKNOWN)

func test_trigger_apply_releases_targets_and_forbids_the_trigger_without_the_active_guard() -> void:
	var frog: Frog = _trigger_frog()
	assert_eq(frog.candidate_entities.error, "")
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	state.frog.flags &= ~FrogFlags.ACTIVE
	var events: Array[TickEvent] = []
	assert_eq(FormCallback.apply(FormCallback.Kind.TRIGGER, frog, state, 3, events), "")
	assert_eq(state.attachment.forbidden_entity_index, 3)
	assert_eq(state.frog.flags, FrogFlags.CONTROL_ACTIVE | FrogFlags.JUMP_FROM_COLLPRIM)
	assert_eq(state.entities.entities[0].entity_flags & EntityDefinition.NO_MOVEMENT, 0)
	assert_true(bool(state.entities.entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(state.frog.cell, Vector2i(1, 1))
	assert_eq(state.frog.mode, FrogMode.JUMPING)
	assert_true(events.is_empty())
	var repeat: GameplayState = _state(FrogMode.JUMPING, 2)
	assert_eq(FormCallback.apply(FormCallback.Kind.TRIGGER, frog, repeat, 3, events), "")
	assert_eq(repeat.attachment.forbidden_entity_index, 3, "the source callback has no debounce")

func test_trigger_apply_requires_candidate_entities_and_a_trigger() -> void:
	var frog: Frog = _trigger_frog()
	var events: Array[TickEvent] = []
	var wrong: GameplayState = _state(FrogMode.JUMPING, 2)
	assert_string_contains(FormCallback.apply(FormCallback.Kind.TRIGGER, frog, wrong, 2, events), "trigger")
	assert_eq(wrong.attachment.forbidden_entity_index, -1)
	frog.candidate_entities = null
	var state: GameplayState = _state(FrogMode.JUMPING, 2)
	assert_string_contains(FormCallback.apply(FormCallback.Kind.TRIGGER, frog, state, 3, events), "candidate")
	assert_eq(state.attachment.forbidden_entity_index, -1)
	assert_eq(state.frog.flags & FrogFlags.JUMP_FROM_COLLPRIM, 0)
	assert_null(state.entities)

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = _grid()
	level.spawn_cell = Vector2i(1, 1)
	level.spawn_direction = 2
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i(3, 3)
	collision.group_size = Vector2i(256, 256)
	collision.frog_collision = FrogCollisionDefinition.new()
	collision.frog_collision.part_count = 1
	collision.frog_collision.probes.append(FrogCollisionDefinition.Probe.new())
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(1)
		var action := FrogCollisionDefinition.Action.new()
		action.frames.append(IDENTITY.duplicate())
		action.actual_cels.append(0)
		collision.frog_collision.actions.append(action)
	var entity := EntityDefinition.new()
	entity.entity_name = "STATIC"
	entity.behavior = EntityBehaviorCatalog.resolve(entity.entity_name)
	entity.entity_index = 2
	entity.unique_id = 9
	entity.form_grid_id = 2
	entity.form_id = 3
	entity.form_name = "TEST_DOOR"
	entity.matrix12[9] = 0
	entity.matrix12[10] = -64
	entity.matrix12[11] = 0
	collision.entities.append(entity)
	var contact := FormContactDefinition.new()
	contact.entity_index = entity.entity_index
	contact.unique_id = entity.unique_id
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.form_name = entity.form_name
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-128, -128)
	contact.height = -10
	contact.max_y = 10
	contact.radius_squared = 1000000
	contact.grid_flags = PackedInt32Array([GridSquareFlags.USABLE | GridSquareFlags.POPDEATH])
	contact.callback_kind = FormCallback.Kind.CRUSHER_BOUNCE_BACK
	var primitive := EntityPrimitiveDefinition.new()
	primitive.half_size = Vector3i(50, 50, 50)
	primitive.reaction = 3
	contact.primitives.append(primitive)
	collision.contacts.append(contact)
	level.entity_collision = collision
	return level

func test_primitive_hit_bounces_the_frog_back_instead_of_reacting_to_the_form() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.primitive_contacts.size(), 1)
	assert_eq(result.primitive_contacts[0].status, EntityPrimitiveQuery.CONTACT)
	assert_true(result.entity_contacts.is_empty())
	var snapshot: GameplayState = result.collision_snapshot
	assert_eq(snapshot.frog.mode, FrogMode.JUMPING)
	assert_eq(snapshot.frog.cell, Vector2i(1, 2))
	assert_eq(snapshot.frog.direction, 0)
	assert_eq(snapshot.frog.remaining_ticks, 6)
	assert_eq(snapshot.frog.flags & (FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_FROM_COLLPRIM), FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_FROM_COLLPRIM)
	assert_eq(snapshot.attachment.forbidden_entity_index, 2)
	assert_eq(snapshot.attachment.entity_hit_indices, PackedInt32Array([2]))
	assert_eq(snapshot.attachment.death_entity_index, -1)
	assert_eq(snapshot.frog.death_equate, 0)
	var landed: GameplayState = null
	for tick: int in range(1, 8):
		var command := TickCommand.new()
		command.tick_index = tick
		var step: TickResult = run.step(command)
		assert_eq(step.error, "", "tick %d" % tick)
		if not step.error.is_empty():
			return
		landed = step.final_snapshot
	assert_eq(landed.frog.mode, FrogMode.STATIONARY)
	assert_eq(landed.frog.cell, Vector2i(1, 2))
	assert_eq(landed.frog.world_position, Vector3i(0, -64, 256))
	assert_eq(landed.attachment.forbidden_entity_index, -1)
	assert_eq(landed.frog.flags & FrogFlags.JUMP_FROM_COLLPRIM, 0)
