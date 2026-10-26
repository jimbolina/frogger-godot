class_name TerrainStartup
extends RefCounted
## Exact single-start bounce/rest callbacks; HUD completion is supplied explicitly.

static func move(state: RunSnapshot) -> TerrainCallbackResult:
	var result := TerrainCallbackResult.new()
	result.callback_flags = (TerrainCallbackResult.UPDATE_POS | TerrainCallbackResult.UPDATE_MATRIX)
	if state.frog.mode == FrogMode.LEVEL_START_BOUNCE:
		if state.frog.start_target_16 < (state.frog.world_position.y << 16):
			@warning_ignore("integer_division")
			state.frog.velocity_16.y = -(2 * state.frog.velocity_16.y) / 3
			state.frog.flags |= FrogFlags.JUST_BOUNCED
			if state.frog.velocity_16.y > -(16 << 16):
				state.frog.velocity_16 = Vector3i.ZERO
				state.frog.mode = FrogMode.LEVEL_START_COME_TO_REST
				return result
	else:
		if state.frog.start_target_16 <= (state.frog.world_position.y << 16):
			state.frog.position_16.y = state.frog.start_target_16
			state.frog.velocity_16 = Vector3i.ZERO
			return result
	state.frog.velocity_16.y += 0x100000
	state.frog.position_16 += state.frog.velocity_16
	return result
