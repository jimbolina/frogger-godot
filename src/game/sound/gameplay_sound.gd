class_name GameplaySound
extends RefCounted
## Applies source sound allocation at the call site while keeping presentation optional.

## Allocates a logical voice before later gameplay RNG consumers; events remain caller-owned.
static func play(state: GameplayState, random: SourceRandom, sound_id: int, pitch_offset: int = 0) -> String:
	if state.sound == null:
		return ""
	state.sound.play(sound_id, random, pitch_offset)
	return state.sound.error
