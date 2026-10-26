extends GutTest
## Pink frog pickup continuation, source timing and detached ownership.

func _pink() -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.background = EntityCustomState.new()
	entity.background.mode = 1
	entity.background.parent_entity_index = 7
	entity.background.delay = 30
	entity.animation = EntityAnimationState.create(PackedInt32Array([6, 1]), true)
	return entity

func _parent() -> EntitySnapshot:
	var parent := EntitySnapshot.new()
	parent.entity_index = 7
	parent.matrix12[9] = 300
	return parent

func _form() -> FormContactDefinition:
	var form := FormContactDefinition.new()
	form.dimensions = Vector2i(1, 2)
	form.grid_flags = PackedInt32Array([3, 3])
	return form

func _frog() -> RunSnapshot:
	var frog := RunSnapshot.new()
	frog.matrix12[9] = 100
	frog.matrix12[10] = -256
	frog.matrix12[11] = 128
	return frog

func test_pickup_consumes_prior_hit_and_keeps_carrier_after_parent_loss() -> void:
	var entity: EntitySnapshot = _pink()
	var parent: EntitySnapshot = _parent()
	var frog: RunSnapshot = _frog()
	assert_eq(EntityBaby.update(entity, parent, _form(), frog), "")
	assert_eq(entity.background.carrier_index, -1)
	parent.live = false
	assert_eq(EntityBaby.update(entity, parent, _form(), frog, true), "")
	assert_eq(entity.background.mode, 3)
	assert_eq(entity.background.parent_entity_index, -1)
	assert_eq(entity.background.carrier_index, 0)
	assert_eq(entity.matrix12.slice(9), PackedInt32Array([100, -276, 108]))
	assert_false(entity.background.model_hidden)
	entity.animation.advance()
	assert_eq(EntityBaby.update(entity, parent, _form(), frog, true), "")
	assert_eq(entity.animation.cel, 0, "Repeated contact does not restart pickup")
	var detached: EntitySnapshot = entity.copy()
	entity.background.carrier_index = -1
	entity.background.dead = true
	assert_eq(detached.background.carrier_index, 0)
	assert_false(detached.background.dead)

func test_riding_turn_jump_and_death_are_source_ordered() -> void:
	var entity: EntitySnapshot = _pink()
	var parent: EntitySnapshot = _parent()
	var frog: RunSnapshot = _frog()
	assert_eq(EntityBaby.update(entity, parent, _form(), frog, true), "")
	frog.matrix12 = PlatformMath.yaw(1024)
	frog.matrix12[9] = 100
	frog.mode = 1
	assert_eq(EntityBaby.update(entity, parent, _form(), frog), "")
	assert_eq(entity.matrix12.slice(9), PackedInt32Array([80, -20, 0]))
	assert_eq(entity.background.carried_jump_ticks, 6)
	entity.animation.advance()
	assert_eq(EntityBaby.update(entity, parent, _form(), frog), "")
	assert_eq(entity.background.carried_jump_ticks, 5)
	assert_eq(entity.animation.cel, 0)
	frog.mode = 2
	assert_eq(EntityBaby.update(entity, parent, _form(), frog), "")
	assert_true(entity.background.dead)
	assert_true(entity.background.model_hidden)
	assert_eq(entity.background.mode, 4)
	assert_eq(TickEvent.trace_lines(entity.requests), ["death_pgen"])
	assert_eq(EntityBaby.update(entity, parent, _form(), frog), "")
	assert_true(entity.requests.is_empty())
	assert_true(entity.background.model_hidden)

func test_contact_requires_admitted_context_and_preserves_caller_state() -> void:
	var definition := EntityDefinition.new()
	definition.entity_name = "ORG_BABY_FROG"
	definition.behavior = EntityBehaviorCatalog.resolve(definition.entity_name)
	definition.behavior.execution = EntityBehavior.Execution.UPDATE
	var state: EntitySnapshot = _pink()
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i.ZERO)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, SourceRandom.create(1), Vector3i.ZERO, true, true, _parent(), _form(), _frog())
	assert_string_contains(result.error, "excluded")
	assert_null(result.entity)
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	result = EntityCustomUpdate.update(definition, state, environment, SourceRandom.create(1), Vector3i.ZERO, true, true, _parent(), _form())
	assert_string_contains(result.error, "carrier")
	assert_null(result.entity)
	assert_eq(state.background.mode, 1)
	assert_eq(state.background.delay, 30)

func test_usable_contact_keeps_strict_edges_and_does_not_mount() -> void:
	var form := FormContactDefinition.new()
	form.dimensions = Vector2i.ONE
	form.offsets = Vector2i(-128, -128)
	form.height = -100
	form.max_y = 20
	form.radius_squared = 1000000
	form.grid_flags = PackedInt32Array([1])
	var pose := EntitySnapshot.new()
	for point: Vector3i in [Vector3i(-127, -100, 0), Vector3i(127, 20, 0)]:
		var contact: FormContactResult = FormContactQuery.query(form, pose, point)
		var reaction: FormReactionResult = FormReaction.evaluate(form, contact, true)
		assert_eq(reaction.status, FormReactionResult.HIT)
		assert_true(reaction.hit)
	for point: Vector3i in [Vector3i(-128, 0, 0), Vector3i(128, 0, 0), Vector3i(0, -101, 0), Vector3i(0, 21, 0)]:
		assert_eq(FormContactQuery.query(form, pose, point).status, FormContactResult.MISS)
	form.radius_squared = 100
	assert_eq(FormContactQuery.query(form, pose, Vector3i(10, 0, 0)).status, FormContactResult.MISS)
	assert_eq(FormContactQuery.query(form, pose, Vector3i(9, 0, 0)).status, FormContactResult.CONTACT)
	pose.live = false
	assert_eq(FormContactQuery.query(form, pose, Vector3i.ZERO).status, FormContactResult.DISABLED)
