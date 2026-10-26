class_name EntityEnvironmentState
extends RefCounted
## Shared logical checkpoint positions and collected bits.

var checkpoint_positions: Array[Vector3i] = []
var covered: int = 0

## Copies positions and mutable covered bits for the aggregate transaction.
func copy() -> EntityEnvironmentState:
	var result := EntityEnvironmentState.new()
	result.checkpoint_positions.assign(checkpoint_positions)
	result.covered = covered
	return result

## Validates five checkpoint positions and the corresponding collected-bit mask.
func validate() -> String:
	if checkpoint_positions.size() != 5 or covered & ~31:
		return "Entity environment requires five checkpoints and bounded covered bits"
	for position: Vector3i in checkpoint_positions:
		for coordinate: int in [position.x, position.y, position.z]:
			if coordinate < -32768 or coordinate > 32767:
				return "Checkpoint positions must fit signed16"
	return ""
