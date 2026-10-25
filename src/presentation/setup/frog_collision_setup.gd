class_name FrogCollisionSetup
extends RefCounted
## Detaches exact high-detail discrete frog poses and collision hilites.

var definition: FrogCollisionDefinition = null
var error: String = ""

## Accepts one complete single-model XAR with exact, noninterpolated cels.
## THROAT's imported croak matrix is unsupported if that part has hilites.
static func from_model(model: MofFile) -> FrogCollisionSetup:
	var result := FrogCollisionSetup.new()
	if model == null or not model.error.is_empty() or model.is_incomplete or model.kind != MofFile.Kind.ANIMATED or model.animated == null or model.static_models.size() != 1:
		result.error = "Frog collision requires one complete animated model"
		return result
	var animation: MofAnimated = model.animated
	if not animation.error.is_empty() or animation.transform_code != 2 or animation.model_sets.size() != 1 or animation.model_sets[0].models.size() != 1:
		result.error = "Frog collision requires discrete byte-quaternion single-model animation"
		return result
	var parts: Array[MofPart] = model.static_models[0].parts
	var info: MofAnimated.ModelInfo = animation.model_sets[0].models[0]
	if info.static_model_index != 0 or info.animation_type != 1 or info.part_count != parts.size() or info.flags != 1:
		result.error = "Frog collision animation model mapping is unsupported"
		return result
	var detached := FrogCollisionDefinition.new()
	detached.part_count = parts.size()
	for part_index: int in parts.size():
		var part: MofPart = parts[part_index]
		if part.borrows or part.hilite_count != part.hilites.size():
			result.error = "Frog collision has borrowed or unavailable hilites"
			return result
		if part_index == 15 and not part.hilites.is_empty():
			result.error = "Frog collision hilite uses the imported throat transform"
			return result
		if not part.hilites.is_empty() and part.partcels.is_empty():
			result.error = "Frog collision hilite has no partcel zero"
			return result
		for hilite_index: int in part.hilites.size():
			var hilite: MofPart.Hilite = part.hilites[hilite_index]
			if hilite.attach != MofPart.ATTACH_VERTEX or hilite.index < 0 or hilite.index * 3 + 2 >= part.partcels[0].vertices.size():
				result.error = "Frog collision hilite is not an available partcel-zero vertex"
				return result
			var probe := FrogCollisionDefinition.Probe.new()
			probe.part_index = part_index
			probe.hilite_index = hilite_index
			var vertices: PackedInt32Array = part.partcels[0].vertices
			probe.vertex = Vector3i(vertices[hilite.index * 3], vertices[hilite.index * 3 + 1], vertices[hilite.index * 3 + 2])
			detached.probes.append(probe)
	var actions: Array[MofAnimated.Action] = animation.actions_for(0)
	for action_index: int in actions.size():
		var action: MofAnimated.Action = actions[action_index]
		if not action.error.is_empty() or action.flags != 1 or action.part_count != parts.size():
			result.error = "Frog collision action is interpolated, invalid or has incompatible parts"
			return result
		var poses := FrogCollisionDefinition.Action.new()
		for cel: int in action.frame_count:
			poses.actual_cels.append(action.cel_numbers[cel] - (0 if animation.starts_at_frame_zero else 1))
			var frame := PackedInt32Array()
			for part_index: int in parts.size():
				var matrix: PackedInt32Array = animation.sample_matrix(0, action_index, cel, part_index)
				if matrix.size() != 12:
					result.error = "Frog collision authored part transform is unavailable"
					return result
				frame.append_array(matrix)
			poses.frames.append(frame)
		detached.actions.append(poses)
	result.error = detached.validate()
	if result.error.is_empty():
		result.definition = detached
	return result
