class_name TerrainModifiers
extends RefCounted
## Source UpdateFrogPowerUps timers and global timer-speed ramp.

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

	if state.frog.powerup_flags & PowerupFlags.TIMER_SPEED:
		if state.flow.timer_count_up:
			if state.flow.timer_fraction <= 65536:
				state.flow.timer_fraction += 3276
			else:
				state.flow.timer_count_up = false
				state.flow.timer_fraction = 0
		elif state.flow.timer_fraction >= -65536:
			state.flow.timer_fraction -= 3276
		else:
			state.flow.timer_count_up = true
		state.flow.timer_speed = PlatformMath.s32(state.flow.timer_speed + state.flow.timer_fraction)
		if state.flow.timer_speed < 65536:
			state.flow.timer_speed = 65536
			state.frog.powerup_flags &= ~PowerupFlags.TIMER_SPEED
