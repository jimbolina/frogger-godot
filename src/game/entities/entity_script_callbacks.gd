class_name EntityScriptCallbacks
extends RefCounted
## Named script callbacks; executable FORM callback addresses are unrelated.

## Applies slots in source order using the previous tick's HIT/CARRY flags.
static func apply(definition: EntityScriptDefinition, context: EntityUpdateContext, result: EntityUpdateResult) -> void:
	var state: EntityScriptState = result.script_state
	for slot: PackedInt32Array in state.callbacks:
		if slot[0] < 0 or (slot[2] != 1 and slot[3] == 3):
			continue
		if slot[1] == 0 and not context.previous_hit:
			continue
		match definition.callbacks[slot[0]]:
			"SCRIPT_CB_FROG_TRAFFIC_SPLAT":
				result.requests.append("sound:13:0:0:0")
			"SCRIPT_CB_LOG_SPLASH":
				result.requests.append("sound:19:0:0:0")
			"SCRIPT_CB_HIT_TURTLE":
				result.requests.append("sound:14:0:0:0")
				result.requests.append("sound:15:0:0:0")
			"SCRIPT_CB_DIVE_COLOUR_CHANGE":
				if context.no_display:
					continue
				var fade: PackedInt32Array = context.fade_bounds
				state.no_screen_fade = fade.is_empty() or (result.matrix12[9] >= fade[0] and result.matrix12[9] <= fade[1] and result.matrix12[11] >= fade[2] and result.matrix12[11] <= fade[3])
				if state.no_screen_fade:
					var packed: int = ((127 + state.deviation) << 16) + ((128 + (-state.deviation >> 1)) << 8) + 128 - state.deviation
					state.colours = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
					state.ambient = Vector3i(64, 64, 192)
				result.drown = context.previous_carry and state.deviation >= 128
