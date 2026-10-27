class_name LevelStartSequence
extends RefCounted
## Source start HUD clocks independent of bitmap and sprite rendering.

const GATHER_FINISH: int = 25 + 1 + 30 + 1
const SCATTER_FINISH: int = GATHER_FINISH + 25 + 1 + 20

## Waits for the first bounce, counts the HUD timer upward, then enables camera wait.
static func advance(state: GameplayState, random: SourceRandom, level_time: int, events: Array[TickEvent]) -> void:
	if not state.frog.flags & FrogFlags.JUST_BOUNCED:
		return
	if state.flow.start_hud_ticks == 0:
		state.flow.start_phrase = random.next_value("level:start_phrase") % 6
		state.flow.remaining_time = 180
	state.flow.start_hud_ticks += 1
	if state.flow.start_hud_ticks >= GATHER_FINISH and not state.flow.start_timer_finished:
		if state.flow.remaining_time > level_time:
			state.flow.remaining_time = level_time
			state.flow.start_timer_finished = true
		else:
			state.flow.remaining_time += 30
	if state.flow.start_hud_ticks >= SCATTER_FINISH and state.flow.start_timer_finished:
		state.flow.phase = LevelFlowState.Phase.PLAY
		state.frog.mode = FrogMode.WAIT_FOR_CAMERA
		events.append(TickEvent.transition(LevelFlowState.Phase.PLAY))
