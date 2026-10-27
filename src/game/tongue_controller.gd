class_name TongueController
extends RefCounted
## Transactional tongue input and effect completion, independent of presentation.

## Acquires a target at the source control boundary before frog movement.
static func start(frog: Frog, state: GameplayState, events: Array[TickEvent]) -> String:
	if state.tongue.mode != TongueState.Mode.IDLE:
		return ""
	var target: TongueTarget = TongueTarget.find(frog.grid, frog.entity_collision, state)
	if not target.error.is_empty():
		return target.error
	state.frog.no_input_timer = 0
	state.tongue.start(target.entity_index)
	events.append(TickEvent.sound(20))
	state.requests.sound_requests += 1
	return GameplaySound.play(state, frog.random, 20)

## Advances after animations, mutating only the private entity and gameplay candidates.
static func advance(frog: Frog, state: GameplayState, entities: EntityRun, events: Array[TickEvent]) -> String:
	if state.tongue.mode == TongueState.Mode.IDLE:
		return ""
	var target_index: int = state.tongue.target_index
	var target: EntitySnapshot = null
	var definition: EntityDefinition = null
	if target_index >= 0:
		var slot: int = entities._slot_for_id(target_index) if entities != null else -1
		if slot < 0:
			return "Tongue target identity is absent from the candidate"
		target = entities.entity_snapshot(slot)
		definition = frog.entity_collision.entities[slot]
	var collected: int = state.tongue.advance()
	var target_position := Vector3i.ZERO
	var target_live: bool = target != null and target.live
	if target_live:
		target_position = Vector3i(target.matrix12[9], target.matrix12[10], target.matrix12[11])
	state.tongue.curve_target = target_position
	state.tongue.curve_has_target = target_live
	state.tongue.tip = TongueCurve.tip(state.frog.matrix12, state.tongue.section, target_position, target_live)
	if target != null:
		target.live_flags |= EntityLiveFlags.TARGETTED if target.live else 0
		if state.tongue.mode == TongueState.Mode.GRAB or state.tongue.mode == TongueState.Mode.IN or collected >= 0:
			target.entity_flags |= EntityDefinition.NO_MOVEMENT
			if target.live:
				target.live_flags |= EntityLiveFlags.TONGUED
		if target_live and (state.tongue.mode == TongueState.Mode.IN or collected >= 0):
			for axis: int in 3:
				target.matrix12[9 + axis] = state.tongue.tip[axis]
		if collected >= 0:
			target.entity_flags |= EntityDefinition.HIDDEN
			var issue: String = ""
			if definition.bonus_kind != FormCallback.Kind.NONE:
				issue = FormCallback.apply(definition.bonus_kind, frog, state, target_index, events)
			elif definition.pickup_reward != null:
				issue = GameplayRewards.apply(definition.pickup_reward, state, events, frog.random)
			else:
				issue = "Tongue collection requires a verified bonus callback or pickup reward"
			if not issue.is_empty():
				return issue
			issue = GameplaySound.play(state, frog.random, 5)
			if not issue.is_empty():
				return issue
			events.append(TickEvent.sound(5))
			state.requests.sound_requests += 1
			state.frog.scale_timer = 0
			state.frog.flags |= FrogFlags.SCALING_UP
		entities.apply_tongue_target(target)
		state.entities = entities.snapshot()
	return ""
