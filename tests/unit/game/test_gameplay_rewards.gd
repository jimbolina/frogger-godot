extends GutTest
## Source score narrowing, flag precedence and detached power-up application.

func test_negative_score_uses_unsigned_threshold_before_reduction_clamp() -> void:
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	assert_eq(GameplayRewards.apply(GameplayRewards.component_definitions()[18], state, events), "")
	assert_eq(state.flow.score, 0)
	assert_eq(state.frog.lives, 4)
	assert_eq(state.flow.life_bonus_score, 20000)

func test_points_award_only_one_life_per_call_and_clock_at_source_limit() -> void:
	var state := GameplayState.new()
	GameplayRewards.points(30000, state)
	assert_eq(state.frog.lives, 4)
	assert_eq(state.flow.life_bonus_score, 20000)
	GameplayRewards.points(0, state)
	assert_eq(state.frog.lives, 5)
	state.flow.score = 99999990
	GameplayRewards.points(25, state)
	assert_eq(state.flow.old_score, 99999990)
	assert_eq(state.flow.score, 16)

func test_time_caps_and_powerup_timers_copy_independently() -> void:
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	state.flow.remaining_time = 2200
	var rewards: Array[RewardDefinition] = GameplayRewards.component_definitions()
	GameplayRewards.apply(rewards[17], state, events)
	assert_eq(state.flow.remaining_time, 2250)
	GameplayRewards.apply(rewards[21], state, events)
	GameplayRewards.apply(rewards[22], state, events)
	GameplayRewards.apply(rewards[23], state, events)
	assert_eq(state.frog.super_tongue_timer, 450)
	assert_eq(state.frog.quick_jump_timer, 240)
	assert_eq(state.frog.auto_hop_timer, 300)
	assert_eq(state.frog.powerup_flags, 7)
	var detached: GameplayState = state.copy()
	detached.flow.remaining_time = 0
	detached.frog.quick_jump_timer = 0
	assert_eq(state.flow.remaining_time, 2250)
	assert_eq(state.frog.quick_jump_timer, 240)

func test_modified_reward_flag_precedence_and_life_cap() -> void:
	var reward := RewardDefinition.new()
	reward.value = 9
	reward.flags = RewardDefinition.LIFE | RewardDefinition.SCORE
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	GameplayRewards.apply(reward, state, events)
	assert_eq(state.flow.score, 9)
	assert_eq(state.frog.lives, 3)
	reward.flags = RewardDefinition.LIFE
	GameplayRewards.apply(reward, state, events)
	assert_eq(state.frog.lives, 10)
	assert_eq(events.size(), 1)
	GameplayRewards.apply(reward, state, events)
	assert_eq(events.size(), 1)

func test_checkpoint_mask_and_reward_are_shared_and_idempotent() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	state.entity_environment = EntityEnvironmentState.new()
	state.flow.elapsed_time = 31
	var entity := EntityDefinition.new()
	entity.entity_index = 12
	entity.form_id = 0x8002
	entity.behavior = EntityBehaviorCatalog.resolve("CHECKPOINT")
	var events: Array[TickEvent] = []
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_eq(state.entity_environment.collected, 4)
	assert_eq(state.flow.last_checkpoint, 2)
	assert_eq(state.flow.checkpoint_times[2], 31)
	assert_eq(state.flow.elapsed_time, 60)
	assert_eq(state.flow.score, 500)
	assert_eq(state.frog.mode, FrogMode.HIT_CHECKPOINT)
	assert_eq(state.flow.phase, LevelFlowState.Phase.CHECKPOINT)
	var count: int = events.size()
	state.frog.mode = FrogMode.STATIONARY
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_eq(events.size(), count)
	assert_eq(state.flow.score, 500)

func test_gold_collection_does_not_change_checkpoint_progress_or_frog_mode() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	state.entity_environment = EntityEnvironmentState.new()
	var entity := EntityDefinition.new()
	entity.behavior = EntityBehaviorCatalog.resolve("GEN_GOLD_FROG")
	var events: Array[TickEvent] = []
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_true(state.flow.gold_collected)
	assert_eq(state.flow.score, 1000)
	assert_eq(state.entity_environment.collected, 0)
	assert_eq(state.frog.mode, FrogMode.STATIONARY)
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_eq(state.flow.score, 1000)

func test_checkpoint_does_not_accept_an_unlanded_jump() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	state.entity_environment = EntityEnvironmentState.new()
	state.frog.mode = FrogMode.JUMPING
	var entity := EntityDefinition.new()
	entity.behavior = EntityBehaviorCatalog.resolve("CHECKPOINT")
	entity.form_id = 0x8000
	var events: Array[TickEvent] = []
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_eq(state.entity_environment.collected, 0)
	state.frog.flags |= FrogFlags.JUMP_TO_LAND
	state.frog.remaining_ticks = 3
	assert_eq(CheckpointCollection.collect(frog, state, entity, events), "")
	assert_eq(state.entity_environment.collected, 1)
	assert_eq(state.frog.remaining_ticks, 3)

func test_light_rewards_widen_shared_cave_radii_as_unsigned32() -> void:
	var reward := RewardDefinition.new()
	reward.flags = RewardDefinition.LIGHT
	reward.value = 2
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	assert_eq(GameplayRewards.apply(reward, state, events), "Light reward requires the shared entity environment")
	state.entity_environment = EntityEnvironmentState.new()
	state.entity_environment.light_min_squared = 0xFFFF0000
	state.entity_environment.light_max_squared = 0x7FFF0000
	assert_eq(GameplayRewards.apply(reward, state, events), "")
	assert_eq(state.entity_environment.light_min_squared, 0x10000)
	assert_eq(state.entity_environment.light_max_squared, 0x80010000)
	reward.value = -1
	assert_eq(GameplayRewards.apply(reward, state, events), "")
	assert_eq(state.entity_environment.light_min_squared, 0)
	assert_eq(state.entity_environment.light_max_squared, 0x80000000)
	reward.flags = RewardDefinition.POWERUP
	reward.value = PowerupFlags.SUPER_LIGHT
	assert_eq(GameplayRewards.apply(reward, state, events), "")
	assert_eq(state.entity_environment.light_min_squared, PowerupFlags.SUPER_LIGHT << 16)
	assert_eq(state.entity_environment.light_max_squared, 0x80000000 + (PowerupFlags.SUPER_LIGHT << 16))
	assert_eq(state.frog.powerup_flags, PowerupFlags.SUPER_LIGHT)
	assert_eq(state.copy().entity_environment.light_max_squared, state.entity_environment.light_max_squared)
	assert_eq(state.flow.score, 0)
	assert_true(events.is_empty())
