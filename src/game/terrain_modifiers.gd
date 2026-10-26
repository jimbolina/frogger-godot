class_name TerrainModifiers
extends RefCounted
## Source UpdateFrogPowerUps local timers; global map timer-speed state is P10.

## Called after frog movement and before collision; zero clears on the next call.
static func update(state: GameplayState) -> void:
	if state.frog.powerup_flags & PowerupFlags.AUTO_HOP:
		if state.frog.auto_hop_timer != 0:
			state.frog.auto_hop_timer -= 1
		else:
			state.frog.powerup_flags &= ~PowerupFlags.AUTO_HOP
	if state.frog.powerup_flags & PowerupFlags.SUPER_TONGUE:
		if state.frog.super_tongue_timer != 0:
			state.frog.super_tongue_timer -= 1
		else:
			state.frog.powerup_flags &= ~PowerupFlags.SUPER_TONGUE
	if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP:
		if state.frog.quick_jump_timer != 0:
			state.frog.quick_jump_timer -= 1
		else:
			state.frog.powerup_flags &= ~PowerupFlags.QUICK_JUMP
