class_name LevelFlow
extends RefCounted
## Detached single-player main-loop decisions after world effects and visibility.
##
## The last-life kill clears FROG_ACTIVE and enters [constant LevelFlowState.Phase.GAME_OVER] on
## that tick (FrogKill, gamesys.C:1898-1903) without completing the run: retail's game-over page
## keeps updating the level under it (OptUpdateGame, tempopt.c:4112), so the dying frog, entities
## and effects go on while the timer, collection and timeout stop. The frog's DEATH_COMPLETE
## completion is cleared in that phase so the run keeps stepping. COMPLETE still completes the run.

enum Reset { NONE, DEATH, CHECKPOINT }
var error: String = ""
var reset: Reset = Reset.NONE

## Advances source timer and checkpoint bonus clocks without presentation callbacks.
## Retail PC's Cheat_no_death_on_timeout skips the whole timeout block (gamesys.C:1822-1879),
## so the frog keeps control and survives; the timer sounds and game-over checks still run.
## The start timer stays unchanged while FrogState.start_timer_hold is positive, so the
## first three logic ticks after a death or checkpoint reset all read 30, as frozen C's
## catch-up frame does; control can therefore return no earlier than the 33rd tick.
static func advance(frog: Frog, state: GameplayState, entities: EntityRun, events: Array[TickEvent], demo: bool, random: SourceRandom = null, level_time: int = 2250, checkpoint_skip: bool = false) -> LevelFlow:
	var result := LevelFlow.new()
	if not demo and state.flow.phase in [LevelFlowState.Phase.PLAY, LevelFlowState.Phase.DEATH]:
		result.error = _timer_sounds(state, random, events)
		if not result.error.is_empty():
			return result
	if state.frog.start_timer_hold > 0:
		state.frog.start_timer_hold -= 1
	elif state.frog.start_timer > 0:
		state.frog.start_timer -= 1
	if state.flow.phase == LevelFlowState.Phase.START:
		if random == null:
			result.error = "Single-start sequence requires the transaction RNG"
		else:
			LevelStartSequence.advance(state, random, level_time, events)
		return result
	if state.flow.phase == LevelFlowState.Phase.COMPLETE:
		return result
	if state.flow.phase == LevelFlowState.Phase.GAME_OVER:
		state.completed = false
		return result
	if state.flow.phase == LevelFlowState.Phase.CHECKPOINT:
		result.error = _checkpoint(state, entities, events, result, checkpoint_skip, random)
		return result
	var death_complete: bool = false
	for event: TickEvent in events:
		death_complete = death_complete or event.kind == TickEvent.Kind.DEATH_COMPLETE
	if death_complete:
		state.completed = false
		if state.frog.lives == 0:
			state.flow.phase = LevelFlowState.Phase.GAME_OVER
			events.append(TickEvent.transition(LevelFlowState.Phase.GAME_OVER))
		else:
			result.reset = Reset.DEATH
		return result
	if state.flow.remaining_time > 0:
		state.flow.remaining_time = maxi(0, state.flow.remaining_time - (state.flow.timer_speed >> 16))
	if state.flow.remaining_time > 0:
		state.flow.elapsed_time += state.flow.timer_speed >> 16
	if demo:
		return result
	if state.entity_environment != null and state.entity_environment.collected == 31:
		state.flow.phase = LevelFlowState.Phase.COMPLETE
		state.completed = true
		events.append(TickEvent.transition(LevelFlowState.Phase.COMPLETE))
		return result
	if state.flow.remaining_time == 0 and not state.cheats.no_death_on_timeout:
		state.frog.flags &= ~FrogFlags.CONTROL_ACTIVE
		if state.frog.mode != FrogMode.JUMPING:
			if state.flow.timeout_ticks > 0:
				if state.flow.timeout_ticks == 59:
					state.frog.death_count = 70
					frog.kill(state, FrogAnimationCatalog.TIMEOUT, false, events)
				state.flow.timeout_ticks -= 1
			else:
				state.flow.timeout_ticks = 60
				result.reset = Reset.DEATH
	if not state.frog.flags & FrogFlags.ACTIVE:
		state.flow.phase = LevelFlowState.Phase.GAME_OVER
		events.append(TickEvent.transition(LevelFlowState.Phase.GAME_OVER))
	elif state.frog.mode == FrogMode.DYING or state.frog.flags & FrogFlags.MUST_DIE:
		if state.flow.phase != LevelFlowState.Phase.DEATH:
			state.flow.phase = LevelFlowState.Phase.DEATH
			events.append(TickEvent.transition(LevelFlowState.Phase.DEATH))
	return result

static func _checkpoint(state: GameplayState, entities: EntityRun, events: Array[TickEvent], result: LevelFlow, skip: bool = false, random: SourceRandom = null) -> String:
	var slot: int = entities._slot_for_id(state.flow.checkpoint_entity_index) if entities != null else -1
	if slot < 0:
		return "Checkpoint transition requires its live authored entity"
	var target: EntitySnapshot = entities.entity_snapshot(slot)
	if not target.live:
		return "Checkpoint transition lost its source live instance"
	if not target.pop_allocated:
		target.pop_allocated = true
		target.pop_remaining = 32
		entities.apply_tongue_target(target)
		events.append(TickEvent.make(TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST).for_entity(target.entity_index))
	if target.pop_remaining > 0 or (state.camera != null and (state.camera.move_timer != 0 or state.camera.twist_counter != 0)):
		return ""
	if state.flow.bonus_stage == 0:
		state.flow.remaining_time = PlatformMath.divide(state.flow.remaining_time, 30) * 30
		state.flow.bonus_score = 0
		state.flow.bonus_stage = 1
		state.flow.transition_ticks = 31
	if state.flow.bonus_stage == 1:
		if skip:
			state.flow.transition_ticks = 1
			skip = false
		state.flow.transition_ticks -= 1
		if state.flow.transition_ticks == 0:
			state.flow.bonus_stage = 2
	if state.flow.bonus_stage in [2, 3] and skip:
		state.flow.bonus_score += PlatformMath.divide(state.flow.remaining_time, 30) * 100
		state.flow.remaining_time = 0
		state.flow.bonus_stage = 3
		skip = false
		var sound_issue: String = GameplaySound.play(state, random, 3)
		if not sound_issue.is_empty():
			return sound_issue
		events.append(TickEvent.sound(3))
	if state.flow.bonus_stage == 2:
		if state.flow.remaining_time > 0:
			if state.flow.remaining_time % 30 == 0:
				state.flow.bonus_score += 100
				var sound_issue: String = GameplaySound.play(state, random, 24)
				if not sound_issue.is_empty():
					return sound_issue
				events.append(TickEvent.sound(24))
			state.flow.remaining_time = maxi(0, state.flow.remaining_time - 10)
		else:
			state.flow.bonus_stage = 3
		return ""
	if state.flow.bonus_stage == 3:
		GameplayRewards.points(state.flow.bonus_score, state)
		state.flow.bonus_stage = 4
		state.flow.transition_ticks = 31
	if state.flow.bonus_stage == 4:
		if skip:
			state.flow.transition_ticks = 1
		state.flow.transition_ticks -= 1
		if state.flow.transition_ticks == 0:
			target.pop_allocated = false
			entities.apply_tongue_target(target)
			if state.entity_environment.collected == 31:
				state.flow.phase = LevelFlowState.Phase.COMPLETE
				state.completed = true
				events.append(TickEvent.transition(LevelFlowState.Phase.COMPLETE))
			else:
				result.reset = Reset.CHECKPOINT
	return ""

static func _timer_sounds(state: GameplayState, random: SourceRandom, events: Array[TickEvent]) -> String:
	if state.frog.start_timer > 0 or state.flow.remaining_time > 300:
		return ""
	if state.flow.remaining_time == 55:
		var issue: String = GameplaySound.play(state, random, 10)
		if not issue.is_empty():
			return issue
		events.append(TickEvent.sound(10))
	var half_seconds: int = PlatformMath.divide(state.flow.remaining_time, 15)
	if half_seconds != state.flow.last_timer_sound:
		if half_seconds > 0:
			var sound_id: int = 24 if half_seconds & 1 else 25
			var issue: String = GameplaySound.play(state, random, sound_id)
			if not issue.is_empty():
				return issue
			events.append(TickEvent.sound(sound_id))
		state.flow.last_timer_sound = half_seconds
	return ""
