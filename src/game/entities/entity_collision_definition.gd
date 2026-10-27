class_name EntityCollisionDefinition
extends RefCounted
## Authored entity/contact pairs and source collision-group geometry.

var entities: Array[EntityDefinition] = []
var platforms_enabled: bool = false
var contacts: Array[FormContactDefinition] = []
var lifecycle: EntityLifecycleDefinition = null
var environment: EntityEnvironmentState = null
## Detached animated frog probes required by supported primitive contacts.
var frog_collision: FrogCollisionDefinition = null
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
	result.environment = environment.copy() if environment != null else null
	result.frog_collision = frog_collision.copy() if frog_collision != null else null
	result.group_base = group_base
	result.group_dimensions = group_dimensions
	result.group_size = group_size
	return result

## Checks paired authored identities and positive group geometry.
func validate() -> String:
	if frog_collision != null:
		var probe_issue: String = frog_collision.validate()
		if not probe_issue.is_empty():
			return probe_issue
	if environment != null:
		var issue: String = environment.validate()
		if not issue.is_empty():
			return issue
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
		if not contact.primitives.is_empty():
			if contact.primitives.size() != 1:
				return "Entity primitive collision requires exactly one cuboid"
			if contact.radius_squared < -2147483648 or contact.radius_squared > 2147483647:
				return "Entity primitive squared radius must fit signed32"
			if frog_collision == null:
				return "Entity primitives require detached animated frog probes"
			if not contact.unsupported_reason.is_empty() and contact.disabled_reason.is_empty():
				return "Entity primitives require supported contact and FORM fallback"
			for primitive: EntityPrimitiveDefinition in contact.primitives:
				if primitive == null:
					return "Entity primitive definition is null"
				var primitive_issue: String = primitive.validate()
				if not primitive_issue.is_empty():
					return primitive_issue
				if primitive.reaction not in [0, 1, 3]:
					return "Entity primitive reaction is unsupported"
		if contact.callback_kind == FormCallback.Kind.UNKNOWN:
			return "Entity has an unverified FORM collision callback"
		if entity.behavior == null:
			return "Entity collision requires a resolved behavior"
		if entity.behavior.has_custom_update() and environment == null:
			return "Admitted custom background requires its shared environment"
		if entity.behavior.execution == EntityBehavior.Execution.CONTACT and entity.behavior.kind == EntityBehavior.Kind.BABY_FROG:
			if entity.behavior.kind != EntityBehavior.Kind.BABY_FROG or not entity.behavior.has_custom_update() or lifecycle == null or entity.collision_callback != 0 or entity.bonus_callback != 0:
				return "Pink frog pickup requires scripted visibility and callback-free behavior"
			if not contact.unsupported_reason.is_empty() or not contact.disabled_reason.is_empty() or not contact.primitives.is_empty() or contact.grid_flags != PackedInt32Array([1]):
				return "Pink frog pickup requires its primitive-free usable FORM"
		if entity.entity_index <= previous_index:
			return "Entity collision indices must be strictly increasing"
		previous_index = entity.entity_index
		if entity.entity_index != contact.entity_index or entity.unique_id != contact.unique_id or entity.form_grid_id != contact.form_grid_id or entity.form_id != contact.form_id or entity.form_name != contact.form_name or entity.flags != contact.entity_flags or entity.source_id != contact.source_id or entity.build_id != contact.build_id or entity.resource_id != contact.resource_id or entity.source_offset != contact.source_offset:
			return "Entity collision pair %d has mismatched identity" % index
	return ""
