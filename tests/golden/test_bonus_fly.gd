extends GutTest
## Independent generic pickup facts including unsigned frame narrowing and voice RNG.

func test_bonus_fly_matches_independent_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/bonus_fly.json"))
	var reward_values: Array = facts.reward_ids
	assert_eq(EntityBonusFly.REWARD_IDS, PackedInt32Array(reward_values))
	for fixture: Dictionary in facts.cases:
		var definition := EntityDefinition.new()
		definition.behavior = EntityBehaviorCatalog.resolve("BONUS_FLY")
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		definition.unique_id = fixture.uid
		definition.matrix12[10] = 32760
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		EntityBonusFly.initialize(definition, entity)
		entity.custom_state.moving_voice_active = fixture.active
		entity.entity_flags = EntityDefinition.NO_MOVEMENT if fixture.stopped else 0
		var random: SourceRandom = SourceRandom.create(1)
		for row: Dictionary in fixture.rows:
			var result := EntityCustomResult.new()
			result.entity = entity.copy()
			result.entity.requests.clear()
			result.random = random.copy()
			var frame_number: int = row.frame
			EntityBonusFly.update(definition, result, frame_number)
			var y: int = row.y
			var pitch: int = row.pitch
			var expected_rng: int = row.rng
			var draws: int = row.draws
			assert_eq(result.entity.matrix12[10], y)
			assert_eq(result.random.state, expected_rng)
			assert_eq(result.random.draw_count, draws)
			assert_eq(result.entity.requests.size(), 0 if pitch == -1 else 1)
			if pitch != -1:
				assert_eq(result.entity.requests[0].pitch, pitch)
			entity = result.entity
			random = result.random

func test_creation_resolves_static_identity_and_logical_sound() -> void:
	for pickup_type: int in 19:
		var definition := EntityDefinition.new()
		definition.behavior = EntityBehaviorCatalog.resolve("BONUS_FLY")
		definition.pickup_type = pickup_type
		definition.matrix12 = PackedInt32Array([0, 4096, 0, -4096, 0, 0, 0, 0, 4096, -123, 32760, 456])
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		entity.live_flags = EntityLiveFlags.TARGETTED
		EntityBonusFly.initialize(definition, entity)
		assert_eq(entity.matrix12, PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -123, 32760, 456]))
		assert_eq(entity.live_flags, EntityLiveFlags.NO_COLOUR_FADE)
		assert_false(entity.custom_state.moving_voice_active)
		assert_false(definition.behavior.immortal)
		assert_false(definition.behavior.group_moving)
		assert_true(definition.behavior.tongueable)
		assert_eq(entity.requests[0].sound_id, 44 if pickup_type == 8 else 21)

func test_voice_pitch_candidate_does_not_mutate_prior_state() -> void:
	var definition := EntityDefinition.new()
	definition.behavior = EntityBehaviorCatalog.resolve("BONUS_FLY")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	EntityBonusFly.initialize(definition, entity)
	entity.custom_state.moving_voice_active = true
	entity.requests.clear()
	var random: SourceRandom = SourceRandom.create(1)
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i.ZERO)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, random, Vector3i.ZERO, false, false, null, null, null, [], [], 7)
	assert_eq(result.error, "")
	assert_eq(random.draw_count, 0)
	assert_eq(entity.matrix12[10], 0)
	assert_eq(entity.requests.size(), 0)
	assert_eq(result.random.draw_count, 2)
	assert_eq(result.entity.requests.size(), 1)
	result.entity.custom_state.moving_voice_active = false
	assert_true(entity.custom_state.moving_voice_active)
