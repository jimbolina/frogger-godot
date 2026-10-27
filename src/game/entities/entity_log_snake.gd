class_name EntityLogSnake
extends RefCounted
## Source log-relative snake motion, including invisible-parent continuation.

## Advances the detached snake against its authored parent's live pose.
static func update(definition: EntityDefinition, entity: EntitySnapshot, parent: EntitySnapshot, form: FormContactDefinition) -> String:
	var custom: EntityCustomState = entity.custom_state
	if parent == null or parent.path == null or form == null:
		return "Log snake requires its parent path and FORM dependencies"
	if custom.parent_entity_index < 0:
		custom.parent_entity_index = parent.entity_index
		custom.direction = 1
		custom.count = PlatformMath.s16(absi(int(sqrt(maxi(0, definition.radius_squared))) - int(sqrt(maxi(0, form.radius_squared)))))
		custom.target = Vector3i(0, PlatformMath.s16(form.height), 0)
		for axis: int in 3:
			entity.matrix12[9 + axis] = parent.path.position[axis]
	if custom.direction == 1:
		if custom.target.z >= custom.count:
			custom.direction = 0
	elif custom.target.z <= -custom.count:
		custom.direction = 1
	custom.target.z = PlatformMath.s16(custom.target.z + (definition.movement_speed >> 8) * (1 if custom.direction == 1 else -1))
	var rotation: PackedInt32Array = PlatformMath.yaw(0 if custom.direction == 1 else 2048)
	for index: int in 9:
		entity.matrix12[index] = rotation[index]
	custom.model_hidden = not parent.live
	if parent.live:
		var point: Vector3i = PlatformMath.apply(parent.matrix12, custom.target)
		entity.matrix12 = PlatformMath.multiply(parent.matrix12, rotation)
		for axis: int in 3:
			entity.matrix12[9 + axis] = parent.matrix12[9 + axis] + point[axis]
	if custom.moving_sound.is_empty():
		custom.moving_sound = PackedInt32Array([101, 512, 1024])
		entity.requests.append(TickEvent.moving_sound(101, 512, 1024))
	return ""
