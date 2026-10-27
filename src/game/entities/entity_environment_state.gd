class_name EntityEnvironmentState
extends RefCounted
## Shared logical checkpoint positions and collected bits.

var checkpoint_positions: Array[Vector3i] = []
var covered: int = 0
var collected: int = 0
var collision_disabled: int = 0
var croak_modes: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])

## Copies positions and mutable covered bits for the aggregate transaction.
func copy() -> EntityEnvironmentState:
	var result := EntityEnvironmentState.new()
	result.checkpoint_positions.assign(checkpoint_positions)
	result.covered = covered
	result.collected = collected
	result.collision_disabled = collision_disabled
	result.croak_modes = croak_modes.duplicate()
	return result

## Validates five checkpoint positions and the corresponding collected-bit mask.
func validate() -> String:
	if checkpoint_positions.size() != 5 or (covered | collected | collision_disabled) & ~31:
		return "Entity environment requires five checkpoints and bounded covered bits"
	if croak_modes.size() != 5:
		return "Entity environment requires five checkpoint animation modes"
	for mode: int in croak_modes:
		if mode < 0 or mode > 3:
			return "Invalid checkpoint animation mode"
	for position: Vector3i in checkpoint_positions:
		for coordinate: int in [position.x, position.y, position.z]:
			if coordinate < -32768 or coordinate > 32767:
				return "Checkpoint positions must fit signed16"
	return ""
