class_name TerrainStartup
extends RefCounted
## Exact single-start bounce/rest callbacks; HUD completion is supplied explicitly.

static func move(state: RunSnapshot) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	result.callback_flags = 9
	if state.mode == 265:
		if state.start_target_16 < (state.world_position.y << 16):
			@warning_ignore("integer_division")
			state.velocity_16.y = -(2 * state.velocity_16.y) / 3
			state.flags |= 32768
			if state.velocity_16.y > -(16 << 16):
				state.velocity_16 = Vector3i.ZERO
				state.mode = 266
				return result
	else:
		if state.start_target_16 <= (state.world_position.y << 16):
			state.position_16.y = state.start_target_16
			state.velocity_16 = Vector3i.ZERO
			return result
	state.velocity_16.y += 0x100000
	state.position_16 += state.velocity_16
	return result
