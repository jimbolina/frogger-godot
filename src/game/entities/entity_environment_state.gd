class_name EntityEnvironmentState
extends RefCounted
## Shared logical checkpoint positions and collected bits.

var checkpoint_positions: Array[Vector3i] = []
var active_swarms: int = 0
var covered: int = 0
var collected: int = 0
var collision_disabled: int = 0
var croak_modes: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Unsigned 32-bit cave light squared radii shared by terrain, entities and rewards.
var light_min_squared: int = 0
var light_max_squared: int = 0

## Copies positions and mutable covered bits for the aggregate transaction.
func copy() -> EntityEnvironmentState:
	var result := EntityEnvironmentState.new()
	result.checkpoint_positions.assign(checkpoint_positions)
	result.active_swarms = active_swarms
	result.covered = covered
	result.collected = collected
	result.collision_disabled = collision_disabled
	result.croak_modes = croak_modes.duplicate()
	result.light_min_squared = light_min_squared
	result.light_max_squared = light_max_squared
	return result

## Validates five checkpoint positions and the corresponding collected-bit mask.
func validate() -> String:
	if checkpoint_positions.size() != 5 or (covered | collected | collision_disabled) & ~31:
		return "Entity environment requires five checkpoints and bounded covered bits"
	if croak_modes.size() != 5:
		return "Entity environment requires five checkpoint animation modes"
	for radius: int in [light_min_squared, light_max_squared]:
		if radius < 0 or radius > 0xffffffff:
			return "Cave light radii must fit unsigned32"
	for mode: int in croak_modes:
		if mode < 0 or mode > 3:
			return "Invalid checkpoint animation mode"
	for position: Vector3i in checkpoint_positions:
		for coordinate: int in [position.x, position.y, position.z]:
			if coordinate < -32768 or coordinate > 32767:
				return "Checkpoint positions must fit signed16"
	return ""
