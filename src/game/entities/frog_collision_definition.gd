class_name FrogCollisionDefinition
extends RefCounted
## Detached authored frog hilites and exact discrete part transforms.

## One vertex hilite, in source part/hilite order, always from partcel zero.
class Probe:
	extends RefCounted
	var part_index: int = 0
	var hilite_index: int = 0
	var vertex: Vector3i = Vector3i.ZERO

## Whole virtual cels, each containing part_count consecutive matrix12 values.
class Action:
	extends RefCounted
	var frames: Array[PackedInt32Array] = []
	## Actual cel identity controls the source stored-LW refresh cache.
	var actual_cels := PackedInt32Array()

var part_count: int = 0
var probes: Array[Probe] = []
var actions: Array[Action] = []

## Validates the complete detached dependency before a run retains it.
func validate() -> String:
	if part_count <= 0 or probes.is_empty() or actions.is_empty():
		return "Frog collision requires parts, hilites and discrete actions"
	var previous_part: int = -1
	var previous_hilite: int = -1
	for probe: Probe in probes:
		if probe == null or probe.part_index < 0 or probe.part_index >= part_count or probe.hilite_index < 0:
			return "Frog collision hilite identity is invalid"
		if probe.part_index < previous_part or (probe.part_index == previous_part and probe.hilite_index <= previous_hilite):
			return "Frog collision hilites are not in source order"
		previous_part = probe.part_index
		previous_hilite = probe.hilite_index
		for axis: int in 3:
			if probe.vertex[axis] < -32768 or probe.vertex[axis] > 32767:
				return "Frog collision vertex is outside signed16"
	for action: Action in actions:
		if action == null or action.frames.is_empty():
			return "Frog collision action has no virtual cels"
		if action.actual_cels.size() != action.frames.size():
			return "Frog collision action has no actual-cel identity table"
		for actual: int in action.actual_cels:
			if actual < 0 or actual > 65535:
				return "Frog collision actual cel is outside unsigned16"
		for frame: PackedInt32Array in action.frames:
			if frame.size() != part_count * 12:
				return "Frog collision frame has an invalid part matrix count"
			for part: int in part_count:
				for component: int in 12:
					var value: int = frame[part * 12 + component]
					if value < -32768 or value > 32767:
						return "Frog authored transform is outside signed16"
	return ""

## Copies nested arrays and source points without retaining setup objects.
func copy() -> FrogCollisionDefinition:
	var result := FrogCollisionDefinition.new()
	result.part_count = part_count
	for probe: Probe in probes:
		var detached := Probe.new()
		detached.part_index = probe.part_index
		detached.hilite_index = probe.hilite_index
		detached.vertex = probe.vertex
		result.probes.append(detached)
	for action: Action in actions:
		var detached := Action.new()
		detached.actual_cels = action.actual_cels.duplicate()
		for frame: PackedInt32Array in action.frames:
			detached.frames.append(frame.duplicate())
		result.actions.append(detached)
	return result
