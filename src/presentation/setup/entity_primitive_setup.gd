class_name EntityPrimitiveSetup
extends RefCounted
## Copies the audited static vehicle model cuboid into gameplay facts.

var primitives: Array[EntityPrimitiveDefinition] = []
var error: String = ""

## Rejects all geometry outside the single first-part static cuboid contract.
static func from_model(model: MofFile) -> EntityPrimitiveSetup:
	var result := EntityPrimitiveSetup.new()
	if model == null or not model.error.is_empty() or model.is_incomplete or model.kind != MofFile.Kind.STATIC or model.static_models.size() != 1:
		result.error = "Vehicle collision requires one complete static model"
		return result
	var parts: Array[MofPart] = model.static_models[0].parts
	if parts.is_empty() or parts[0].collprims.size() != 1:
		result.error = "Vehicle collision requires one first-part primitive"
		return result
	for part_index: int in parts.size():
		if parts[part_index].borrows or (part_index > 0 and not parts[part_index].collprims.is_empty()):
			result.error = "Vehicle collision has borrowed or additional primitive parts"
			return result
	var source: MofPart.Collprim = parts[0].collprims[0]
	var definition := EntityPrimitiveDefinition.new()
	definition.shape = source.type
	definition.flags = source.flags
	definition.offset = source.offset
	definition.half_size = source.size
	definition.reaction = source.user
	definition.matrix_index = source.matrix_index
	result.error = definition.validate()
	if result.error.is_empty():
		result.primitives.append(definition)
	return result
