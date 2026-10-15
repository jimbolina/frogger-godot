class_name EntityEnvironmentState
extends RefCounted
## Shared logical checkpoint state for an admitted all-attached inspection.

var checkpoint_positions: Array[Vector3i] = []
var covered: int = 0

## Copies positions and mutable covered bits for the aggregate transaction.
func copy() -> EntityEnvironmentState:
	var result := EntityEnvironmentState.new()
	result.checkpoint_positions.assign(checkpoint_positions)
	result.covered = covered
	return result

## The bounded background closure requires five uncollected checkpoints.
func validate() -> String:
	if checkpoint_positions.size() != 5 or covered & ~31:
		return "Entity background requires five checkpoints and bounded covered bits"
	for position: Vector3i in checkpoint_positions:
		for coordinate: int in [position.x, position.y, position.z]:
			if coordinate < -32768 or coordinate > 32767:
				return "Checkpoint positions must fit signed16"
	return ""
