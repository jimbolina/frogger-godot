class_name EntityPrimitiveSetup
extends RefCounted
## Copies a supported entity model cuboid, and an animated model's primitive
## part transforms, into gameplay facts.

var primitives: Array[EntityPrimitiveDefinition] = []
## Discrete transforms of the animated primitive part; null for static models.
var part: EntityPrimitivePartDefinition = null
var error: String = ""

## A static model must carry one first-part cuboid. An animated model must be a
## discrete byte-quaternion single model, as the frog is, whose first part with
## primitives carries one cuboid. [param model_resource_id] identifies the
## shared primitive matrix, or -1 when the caller has none.
static func from_model(model: MofFile, model_resource_id: int = -1) -> EntityPrimitiveSetup:
	var result := EntityPrimitiveSetup.new()
	if model == null or not model.error.is_empty() or model.is_incomplete or model.kind not in [MofFile.Kind.STATIC, MofFile.Kind.ANIMATED] or model.static_models.size() != 1:
		result.error = "Entity collision requires one complete static or animated model"
		return result
	var parts: Array[MofPart] = model.static_models[0].parts
	var primitive_part: int = -1
	for part_index: int in parts.size():
		if parts[part_index].borrows:
			result.error = "Entity collision has borrowed primitive parts"
			return result
		if parts[part_index].collprims.is_empty():
			continue
		if primitive_part >= 0:
			result.error = "Vehicle collision has borrowed or additional primitive parts" if model.kind == MofFile.Kind.STATIC else "Animated collision has multiple primitive parts"
			return result
		primitive_part = part_index
	if primitive_part < 0 or parts[primitive_part].collprims.size() != 1 or (model.kind == MofFile.Kind.STATIC and primitive_part != 0):
		result.error = "Entity collision requires one primitive"
		return result
	var owner: MofPart = parts[primitive_part]
	var source: MofPart.Collprim = owner.collprims[0]
	var definition := EntityPrimitiveDefinition.new()
	definition.part_index = primitive_part
	definition.shape = source.type
	definition.flags = source.flags
	definition.offset = source.offset
	definition.half_size = source.size
	definition.reaction = source.user
	definition.matrix_index = source.matrix_index
	definition.model_resource_id = model_resource_id
	if source.matrix_index >= 0:
		if source.matrix_index >= owner.matrices.size():
			result.error = "Primitive matrix index is outside the part's matrices"
			return result
		definition.rotation = owner.matrices[source.matrix_index].slice(0, 9)
	result.error = definition.validate()
	if not result.error.is_empty():
		return result
	if model.kind == MofFile.Kind.ANIMATED:
		result.part = _animated_part(model, primitive_part)
		if result.part == null:
			result.error = "Animated collision requires discrete byte-quaternion single-model animation"
			return result
		result.error = result.part.validate()
		if not result.error.is_empty():
			result.part = null
			return result
	result.primitives.append(definition)
	return result

static func _animated_part(model: MofFile, part_index: int) -> EntityPrimitivePartDefinition:
	var animation: MofAnimated = model.animated
	if animation == null or not animation.error.is_empty() or animation.transform_code != 2 or animation.model_sets.size() != 1 or animation.model_sets[0].models.size() != 1:
		return null
	var info: MofAnimated.ModelInfo = animation.model_sets[0].models[0]
	if info.static_model_index != 0 or info.animation_type != 1 or info.part_count != model.static_models[0].parts.size() or info.flags != 1:
		return null
	var result := EntityPrimitivePartDefinition.new()
	result.part_index = part_index
	var actions: Array[MofAnimated.Action] = animation.actions_for(0)
	for action_index: int in actions.size():
		var action: MofAnimated.Action = actions[action_index]
		if not action.error.is_empty() or action.flags != 1 or action.part_count != info.part_count:
			return null
		var poses := EntityPrimitivePartDefinition.Action.new()
		for cel: int in action.frame_count:
			var matrix: PackedInt32Array = animation.sample_matrix(0, action_index, cel, part_index)
			if matrix.size() != 12:
				return null
			poses.frames.append(matrix)
			poses.actual_cels.append(action.cel_numbers[cel] - (0 if animation.starts_at_frame_zero else 1))
		result.actions.append(poses)
	return result
