class_name EntityScriptRuntime
extends RefCounted
## Private transaction bridge for source-ordered script effects that consume shared RNG.

var state: GameplayState = null
var frog: Frog = null
var events: Array[TickEvent] = []
var entity_index: int = -1
var generation: int = 0

## Applies a sound effect at its original position among script RNG consumers.
func sound(request: TickEvent, random: SourceRandom, position: Vector3i) -> String:
	if state.sound == null:
		return ""
	match request.kind:
		TickEvent.Kind.SOUND:
			return GameplaySound.play(state, random, request.sound_id)
		TickEvent.Kind.MOVING:
			if state.frog.mode in [FrogMode.HIT_CHECKPOINT, FrogMode.CHECKPOINT_COLLECTED] or state.flow.phase == LevelFlowState.Phase.GAME_OVER:
				return ""
			if state.sound.moving_for(entity_index) == null:
				var issue: String = state.sound.create_moving(entity_index, request.sound_id, request.minimum_distance, request.maximum_distance, position)
				if issue.is_empty():
					state.sound.moving_for(entity_index).generation = generation
				return issue
		TickEvent.Kind.PITCH_BEND:
			var moving: LogicalMovingSound = state.sound.moving_for(entity_index)
			if moving != null:
				state.sound.bend(moving.voice_tag, request.pitch)
	return ""
