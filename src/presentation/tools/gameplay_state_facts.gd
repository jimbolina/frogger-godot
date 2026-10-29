class_name GameplayStateFacts
extends RefCounted
## Debug overlay text describing a committed frog, camera and outcome state, shared by inspection screens.

## Returns the frog tick, cell, motion, layer, camera, death and outcome lines, each ending in a newline.
static func frog_lines(state: GameplayState, outcomes: PackedStringArray) -> String:
	var camera_facts: String = "none" if state.camera == null else "%d source %s" % [state.camera.mode, state.camera.source_world]
	var text: String = "tick %d | mode %d | cell %s | square %d\n" % [state.tick_index, state.frog.mode, state.frog.cell, state.frog.square_index]
	text += "position16 %s | velocity16 %s\ncount %d | flags 0x%x | buffered %d / %d\n" % [state.frog.position_16, state.frog.velocity_16, state.frog.remaining_ticks, state.frog.flags, state.frog.buffered_keys, state.frog.buffered_input_count]
	text += "destination %s | layer flags 0x%x | source %s\ncamera %s | death %d/%d | completed %s\noutcomes %s\n" % [state.frog.destination_cell, state.frog.square_flags, state.diagnostics.source_id, camera_facts, state.frog.death_equate, state.frog.death_count, str(state.completed), "; ".join(outcomes)]
	return text
