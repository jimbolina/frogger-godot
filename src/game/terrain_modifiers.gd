class_name TerrainModifiers
extends RefCounted
## Source UpdateFrogPowerUps local timers; global map timer-speed state is P10.

## Called after frog movement and before collision; zero clears on the next call.
static func update(state: RunSnapshot) -> void:
	if state.powerup_flags & 4:
		if state.auto_hop_timer != 0:
			state.auto_hop_timer -= 1
		else:
			state.powerup_flags &= ~4
	if state.powerup_flags & 1:
		if state.super_tongue_timer != 0:
			state.super_tongue_timer -= 1
		else:
			state.powerup_flags &= ~1
	if state.powerup_flags & 2:
		if state.quick_jump_timer != 0:
			state.quick_jump_timer -= 1
		else:
			state.powerup_flags &= ~2
