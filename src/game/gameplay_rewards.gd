class_name GameplayRewards
extends RefCounted
## Frozen score, time, life and power-up application on a private candidate.

## Applies source flag precedence and emits logical sound requests immediately.
static func apply(reward: RewardDefinition, state: GameplayState, events: Array[TickEvent], random: SourceRandom = null) -> String:
	var value: int = reward.value
	var sound_offset: int = -1
	if reward.flags & RewardDefinition.SCORE:
		points(value, state)
	elif reward.flags & RewardDefinition.LIGHT:
		var light_issue: String = _light(value, state)
		if not light_issue.is_empty():
			return light_issue
	elif reward.flags & RewardDefinition.TIME:
		state.flow.remaining_time = mini(2250, PlatformMath.s32(state.flow.remaining_time + value))
	elif reward.flags & RewardDefinition.REDUCE:
		points(value, state)
		state.flow.score = maxi(0, state.flow.score)
	elif reward.flags & RewardDefinition.LIFE:
		if state.frog.lives < 10:
			state.frog.lives = mini(10, PlatformMath.s32(state.frog.lives + value))
			sound_offset = 0
	elif reward.flags & RewardDefinition.POWERUP:
		match value:
			PowerupFlags.TIMER_SPEED:
				sound_offset = 128
			PowerupFlags.AUTO_HOP:
				state.frog.auto_hop_timer = 300
				sound_offset = 128
			PowerupFlags.SUPER_TONGUE:
				state.frog.super_tongue_timer = 450
				sound_offset = 256
			PowerupFlags.QUICK_JUMP:
				state.frog.quick_jump_timer = 240
				sound_offset = 384
			PowerupFlags.SUPER_LIGHT:
				var light_issue: String = _light(value, state)
				if not light_issue.is_empty():
					return light_issue
		state.frog.powerup_flags |= value
	if sound_offset >= 0:
		events.append(TickEvent.sound(26))
		return GameplaySound.play(state, random, 26, sound_offset)
	return ""

## Adds signed points and awards at most one threshold life per source call.
static func points(value: int, state: GameplayState) -> void:
	state.flow.old_score = state.flow.score & 0xffffffff
	state.flow.score = PlatformMath.s32(state.flow.score + value)
	if state.flow.score > 99999999:
		state.flow.score -= 99999999
	if (state.flow.score & 0xffffffff) >= state.flow.life_bonus_score:
		state.frog.lives = mini(state.frog.lives + 1, 10)
		state.flow.life_bonus_score = (state.flow.life_bonus_score + 10000) & 0xffffffff

static func _light(value: int, state: GameplayState) -> String:
	if state.entity_environment == null:
		return "Light reward requires the shared entity environment"
	var increase: int = PlatformMath.s32(value << 16)
	state.entity_environment.light_min_squared = (state.entity_environment.light_min_squared + increase) & 0xffffffff
	state.entity_environment.light_max_squared = (state.entity_environment.light_max_squared + increase) & 0xffffffff
	return ""

## Source constants for asset-free component definitions; retail setup supplies SCORE_BOOK.
static func component_definitions() -> Array[RewardDefinition]:
	var values: PackedInt32Array = [5, 10, 25, 50, 75, 100, 150, 200, 250, 500, 1000, 5000, 5, 8, 16, 60, 150, 300, -500, 8, 1, 1, 2, 4]
	var flags: PackedInt32Array = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 32, 4, 4, 4, 8, 32, 16, 32, 32, 32]
	var result: Array[RewardDefinition] = []
	for index: int in values.size():
		var reward := RewardDefinition.new()
		reward.value = values[index]
		reward.flags = flags[index]
		result.append(reward)
	return result
