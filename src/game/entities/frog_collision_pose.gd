class_name FrogCollisionPose
extends RefCounted
## Owned source stored-LW cache for a frog created with MR_OBJ_STATIC.

var action: int = -1
var actual_cel: int = -1
var probes: FrogCollisionQuery.Sample = null

## Refreshes at the final animation phase, retaining the old root on equal cels.
## Reset explicitly primes an empty cache from the selected initial pose.
func refresh(definition: FrogCollisionDefinition, next_action: int, virtual_cel: int, root_matrix12: PackedInt32Array) -> String:
	if definition == null or next_action < 0 or next_action >= definition.actions.size() or definition.actions[next_action] == null:
		return "Stored frog collision action is unavailable"
	var identities: PackedInt32Array = definition.actions[next_action].actual_cels
	if virtual_cel < 0 or virtual_cel >= identities.size():
		return "Stored frog collision virtual cel is unavailable"
	var next_actual: int = identities[virtual_cel]
	if action == next_action and actual_cel == next_actual and probes != null:
		return ""
	var next: FrogCollisionQuery.Sample = FrogCollisionQuery.sample(definition, next_action, virtual_cel, root_matrix12)
	if not next.error.is_empty():
		return next.error
	action = next_action
	actual_cel = next_actual
	probes = next
	return ""

## Detaches cached points and identities for an unpublished candidate tick.
func copy() -> FrogCollisionPose:
	var result := FrogCollisionPose.new()
	result.action = action
	result.actual_cel = actual_cel
	result.probes = probes.copy() if probes != null else null
	return result
