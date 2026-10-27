extends GutTest
## Independently derived signed score and unsigned threshold comparisons.

func test_score_operations_match_frozen_facts() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/rewards.json"))
	for row: Dictionary in rows:
		var state := GameplayState.new()
		state.flow.score = row.score
		state.flow.life_bonus_score = row.threshold
		state.frog.lives = row.lives
		var reward := RewardDefinition.new()
		reward.value = row.amount
		reward.flags = RewardDefinition.REDUCE if row.clamp else RewardDefinition.SCORE
		var events: Array[TickEvent] = []
		assert_eq(GameplayRewards.apply(reward, state, events), "")
		var score: int = row.expected_score
		var threshold: int = row.expected_threshold
		var lives: int = row.expected_lives
		assert_eq(state.flow.score, score)
		assert_eq(state.flow.life_bonus_score, threshold)
		assert_eq(state.frog.lives, lives)
