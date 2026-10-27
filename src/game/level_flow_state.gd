class_name LevelFlowState
extends RefCounted
## Detached single-player progress; frog lives and entity checkpoint mask remain authoritative.

enum Phase { START, PLAY, DEATH, CHECKPOINT, COMPLETE, GAME_OVER }
var start_hud_ticks: int = 0
var start_timer_finished: bool = false
var start_phrase: int = -1
var bonus_stage: int = 0
var bonus_score: int = 0
var timeout_ticks: int = 60
var elapsed_time: int = 0
var last_checkpoint: int = -1
var checkpoint_entity_index: int = -1
var checkpoint_times: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
var phase: Phase = Phase.PLAY
var score: int = 0
var old_score: int = 0
var life_bonus_score: int = 10000
var remaining_time: int = 2250
var timer_speed: int = 65536
var timer_fraction: int = 0
var timer_count_up: bool = true
var timer_accumulator: int = 0
var last_timer_sound: int = 0
var light_min_squared: int = 0
var light_max_squared: int = 0
var transition_ticks: int = 0
var gold_collected: bool = false

## Copies every mutable level value for atomic gameplay advancement.
func copy() -> LevelFlowState:
	var result := LevelFlowState.new()
	result.start_hud_ticks = start_hud_ticks
	result.start_timer_finished = start_timer_finished
	result.start_phrase = start_phrase
	result.bonus_stage = bonus_stage
	result.bonus_score = bonus_score
	result.timeout_ticks = timeout_ticks
	result.elapsed_time = elapsed_time
	result.last_checkpoint = last_checkpoint
	result.checkpoint_entity_index = checkpoint_entity_index
	result.checkpoint_times = checkpoint_times.duplicate()
	result.phase = phase
	result.score = score
	result.old_score = old_score
	result.life_bonus_score = life_bonus_score
	result.remaining_time = remaining_time
	result.timer_speed = timer_speed
	result.timer_fraction = timer_fraction
	result.timer_count_up = timer_count_up
	result.timer_accumulator = timer_accumulator
	result.last_timer_sound = last_timer_sound
	result.light_min_squared = light_min_squared
	result.light_max_squared = light_max_squared
	result.transition_ticks = transition_ticks
	result.gold_collected = gold_collected
	return result
