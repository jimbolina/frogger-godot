class_name EntityPrimitivePartDefinition
extends RefCounted
## Detached discrete authored transforms of an animated model's primitive part.

## One action: a part matrix12 per virtual cel and the actual cel it shows.
class Action:
	extends RefCounted
	var frames: Array[PackedInt32Array] = []
	## Actual cel identity controls the source stored-LW refresh cache.
	var actual_cels := PackedInt32Array()

	## Returns independent frame and identity arrays.
	func copy() -> Action:
		var result := Action.new()
		for frame: PackedInt32Array in frames:
			result.frames.append(frame.duplicate())
		result.actual_cels = actual_cels.duplicate()
		return result

## The first model part that has collision primitives.
var part_index: int = -1
var actions: Array[Action] = []

## Validates part identity, cel tables and signed16 authored transforms.
func validate() -> String:
	if part_index < 0:
		return "Animated primitive part is unavailable"
	if actions.is_empty():
		return "Animated primitive part requires discrete actions"
	for action: Action in actions:
		if action == null or action.frames.is_empty():
			return "Animated primitive action has no virtual cels"
		if action.actual_cels.size() != action.frames.size():
			return "Animated primitive action has no actual-cel identity table"
		for actual: int in action.actual_cels:
			if actual < 0 or actual > 65535:
				return "Animated primitive actual cel is outside unsigned16"
		for frame: PackedInt32Array in action.frames:
			if frame.size() != 12:
				return "Animated primitive frame requires twelve source values"
			for value: int in frame:
				if value < -32768 or value > 32767:
					return "Animated primitive authored transform is outside signed16"
	return ""

## Copies nested frames without retaining setup objects.
func copy() -> EntityPrimitivePartDefinition:
	var result := EntityPrimitivePartDefinition.new()
	result.part_index = part_index
	for action: Action in actions:
		result.actions.append(action.copy() if action != null else null)
	return result
