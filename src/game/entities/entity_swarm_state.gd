class_name EntitySwarmState
extends RefCounted
## Committed Forest swarm motion and the three source sprite positions.

var matrix12: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
var positions: Array[Vector3i] = [Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO]
var angles: PackedInt32Array = PackedInt32Array([0, 0, 0])
var speed: int = 0
var delay: int = 0
var visible: bool = false

## Detaches every continuation and presentation field.
func copy() -> EntitySwarmState:
	var result := EntitySwarmState.new()
	result.matrix12 = matrix12.duplicate()
	result.positions.assign(positions)
	result.angles = angles.duplicate()
	result.speed = speed
	result.delay = delay
	result.visible = visible
	return result
