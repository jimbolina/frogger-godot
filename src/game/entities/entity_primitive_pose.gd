class_name EntityPrimitivePose
extends RefCounted
## Owned stored-LW transform of an animated entity's primitive part.
## An empty transform means the environment has not been refreshed since creation.

var action: int = -1
var actual_cel: int = -1
var lw12: PackedInt32Array = PackedInt32Array()

## Refreshes at the aggregate pose phase, as MRAnimUpdateEnvironments does for
## MR_OBJ_STATIC models: an unchanged action and actual cel keep the stored
## transform and its old root, and a negative action or cel keeps the cache.
func refresh(part: EntityPrimitivePartDefinition, animation: EntityAnimationState, root_matrix12: PackedInt32Array) -> String:
	if part == null or animation == null:
		return "Animated primitive pose requires its part and entity animation"
	if animation.action < 0 or animation.cel < 0:
		return ""
	if animation.action >= part.actions.size() or part.actions[animation.action] == null:
		return "Animated primitive action is unavailable"
	var source: EntityPrimitivePartDefinition.Action = part.actions[animation.action]
	if animation.cel >= source.frames.size() or animation.cel >= source.actual_cels.size():
		return "Animated primitive virtual cel is unavailable"
	var next_actual: int = source.actual_cels[animation.cel]
	if action == animation.action and actual_cel == next_actual and not lw12.is_empty():
		return ""
	if not PlatformMath.valid(root_matrix12):
		return "Animated primitive root matrix is invalid"
	lw12 = FrogCollisionQuery.compose(root_matrix12, source.frames[animation.cel])
	action = animation.action
	actual_cel = next_actual
	return ""

## Detaches the stored transform for an unpublished candidate tick.
func copy() -> EntityPrimitivePose:
	var result := EntityPrimitivePose.new()
	result.action = action
	result.actual_cel = actual_cel
	result.lw12 = lw12.duplicate()
	return result
