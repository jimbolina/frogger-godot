class_name CheckpointCollection
extends RefCounted
## Single-player checkpoint and gold-frog rewards at the source FORM boundary.

## Applies one collection, sharing the authoritative mask with entity behavior.
static func collect(frog: Frog, state: GameplayState, definition: EntityDefinition, events: Array[TickEvent]) -> String:
	if state.frog.mode not in [FrogMode.STATIONARY, FrogMode.SLIPPING_LAND_GRID, FrogMode.SLIPPING_LAND_NONGRID, FrogMode.SIMPLE_SLIPPING_LAND_GRID] and not state.frog.flags & FrogFlags.JUMP_TO_LAND:
		return ""
	if state.attachment.current_entity_index >= 0 and state.attachment.current_entity_index != definition.entity_index and not state.frog.flags & FrogFlags.ON_ENTITY:
		if frog.camera != null:
			var pose: EntitySnapshot = frog.contacts.platform_pose(frog, state)
			if pose == null:
				return "Checkpoint collection requires the departing platform pose"
			var issue: String = frog.camera.transition_attachment(pose.matrix12, PackedInt32Array(), false)
			if not issue.is_empty():
				return issue
		state.attachment.current_entity_index = -1
	if definition.behavior.kind == EntityBehavior.Kind.GOLD_FROG:
		if state.flow.gold_collected:
			return ""
		var sound_issue: String = GameplaySound.play(state, frog.random, 22, frog.music_pitch_offset)
		if not sound_issue.is_empty():
			return sound_issue
		events.append(TickEvent.sound(22))
		var reward_issue: String = GameplayRewards.apply(frog.rewards[10], state, events, frog.random)
		if not reward_issue.is_empty():
			return reward_issue
		state.flow.gold_collected = true
		return ""
	var checkpoint: int = definition.form_id & 32767
	if checkpoint >= 5:
		checkpoint -= 11
	if checkpoint < 0 or checkpoint >= 5 or state.entity_environment == null:
		return "Checkpoint collection requires a valid single-player checkpoint identity and environment"
	if state.entity_environment.collected & (1 << checkpoint):
		return ""
	state.entity_environment.collected |= 1 << checkpoint
	state.flow.last_checkpoint = checkpoint
	state.flow.checkpoint_entity_index = definition.entity_index
	state.flow.checkpoint_times[checkpoint] = state.flow.elapsed_time
	var reward_issue: String = GameplayRewards.apply(frog.rewards[9], state, events, frog.random)
	if not reward_issue.is_empty():
		return reward_issue
	if state.flow.elapsed_time != 0:
		state.flow.elapsed_time = PlatformMath.divide(state.flow.elapsed_time + 29, 30) * 30
	var sound_issue: String = GameplaySound.play(state, frog.random, 9, frog.music_pitch_offset)
	if not sound_issue.is_empty():
		return sound_issue
	events.append(TickEvent.sound(9))
	frog.request_animation(FrogAnimationCatalog.COMPLETE, state)
	if state.frog.mode != FrogMode.JUMPING:
		state.frog.remaining_ticks = 0
	state.frog.mode = FrogMode.HIT_CHECKPOINT
	state.flow.phase = LevelFlowState.Phase.CHECKPOINT
	state.flow.transition_ticks = 0
	state.flow.bonus_stage = 0
	frog.request_animation(FrogAnimationCatalog.TRIGGER, state)
	if frog.camera != null:
		frog.camera.request_checkpoint()
	events.append(TickEvent.transition(LevelFlowState.Phase.CHECKPOINT, checkpoint))
	return ""
