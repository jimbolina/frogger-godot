class_name EntityCollisionDefinition
extends RefCounted
## Authored entity/contact pairs and source collision-group geometry.

var entities: Array[EntityDefinition] = []
var platforms_enabled: bool = false
var contacts: Array[FormContactDefinition] = []
var lifecycle: EntityLifecycleDefinition = null
var group_base: Vector3i = Vector3i.ZERO
var group_dimensions: Vector2i = Vector2i.ZERO
var group_size: Vector2i = Vector2i.ZERO

## Returns detached definitions and source group dimensions.
func copy() -> EntityCollisionDefinition:
	var result := EntityCollisionDefinition.new()
	result.platforms_enabled = platforms_enabled
	for entity: EntityDefinition in entities:
		result.entities.append(entity.copy() if entity != null else null)
	for contact: FormContactDefinition in contacts:
		result.contacts.append(contact.copy() if contact != null else null)
	result.lifecycle = lifecycle.copy() if lifecycle != null else null
	result.group_base = group_base
	result.group_dimensions = group_dimensions
	result.group_size = group_size
	return result

## Checks paired authored identities and positive group geometry.
func validate() -> String:
	if entities.size() != contacts.size():
		return "Entity collision requires one contact per entity"
	if group_dimensions.x <= 0 or group_dimensions.y <= 0 or group_size.x <= 0 or group_size.y <= 0:
		return "Entity collision requires positive group dimensions and size"
	if group_dimensions.x > 65535 or group_dimensions.y > 65535 or group_size.x > 65535 or group_size.y > 65535:
		return "Entity collision group dimensions and size must fit unsigned16"
	if lifecycle != null:
		var lifecycle_issue: String = lifecycle.validate()
		if not lifecycle_issue.is_empty():
			return lifecycle_issue
		if lifecycle.group_base != group_base or lifecycle.group_dimensions != group_dimensions or lifecycle.group_size != group_size:
			return "Entity lifecycle and collision group geometry must agree"
	for coordinate: int in [group_base.x, group_base.y, group_base.z]:
		if coordinate < -32768 or coordinate > 32767:
			return "Entity collision group base must fit signed16"
	var previous_index: int = -1
	for index: int in entities.size():
		var entity: EntityDefinition = entities[index]
		var contact: FormContactDefinition = contacts[index]
		if entity == null or contact == null:
			return "Entity collision pair %d is null" % index
		if entity.entity_index <= previous_index:
			return "Entity collision indices must be strictly increasing"
		previous_index = entity.entity_index
		if entity.entity_index != contact.entity_index or entity.unique_id != contact.unique_id or entity.form_grid_id != contact.form_grid_id or entity.form_id != contact.form_id or entity.form_name != contact.form_name or entity.flags != contact.entity_flags or entity.source_id != contact.source_id or entity.build_id != contact.build_id or entity.resource_id != contact.resource_id or entity.source_offset != contact.source_offset:
			return "Entity collision pair %d has mismatched identity" % index
	return ""
