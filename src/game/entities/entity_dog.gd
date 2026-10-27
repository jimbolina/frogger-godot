class_name EntityDog
extends RefCounted
## Suburbia dog's authored wait, random fall and frog-biting continuation.

enum Mode { WAITING, WALKING, FALLING, BITING }

## Advances a private candidate before updating its source moving transform.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool) -> String:
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	if entity.path == null or entity.animation == null or entity.animation.lengths.size() < 3:
		return "Dog requires a path and run, fall and bite animation actions"
	match custom.mode:
		Mode.WAITING:
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 4294967295
			if expired:
				custom.mode = Mode.WALKING
				result.path_active_request = 1
				if _near_frog(entity, frog):
					entity.requests.append(TickEvent.sound(153))
		Mode.WALKING:
			if entity.path.flags & (PathStart.JUST_BOUNCED_END | PathStart.JUST_BOUNCED_START):
				custom.mode = Mode.WAITING
				custom.timer = definition.authored_delay
				result.path_active_request = 0
			if result.random.next_value("entity:%d:dog_fall" % definition.entity_index) % 500 == 1:
				result.path_active_request = 0
				entity.animation.select(1)
				custom.timer = 50
				custom.mode = Mode.FALLING
			if hit:
				_bite(result)
		Mode.FALLING:
			custom.timer = (custom.timer - 1) & 4294967295
			if custom.timer == 0:
				_walk(result)
			if hit:
				_bite(result)
	if custom.mode == Mode.BITING:
		if hit:
			custom.count = 50
			var offset: Vector3i = PlatformMath.apply(entity.matrix12, Vector3i(0, 0, 192))
			result.frog_matrix12 = PlatformMath.multiply(entity.matrix12, PlatformMath.yaw(1024))
			for axis: int in 3:
				result.frog_matrix12[9 + axis] = PlatformMath.s32(entity.matrix12[9 + axis] + PlatformMath.s16(offset[axis]))
			entity.requests.append(TickEvent.sound(154))
		else:
			custom.count = (custom.count - 1) & 4294967295
			if custom.count == 0:
				_walk(result)
	entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	return ""

static func _bite(result: EntityCustomResult) -> void:
	result.path_active_request = 0
	result.entity.animation.select(2)
	result.entity.custom_state.mode = Mode.BITING

static func _walk(result: EntityCustomResult) -> void:
	result.path_active_request = 1
	result.entity.animation.select(0)
	result.entity.custom_state.mode = Mode.WALKING

static func _near_frog(entity: EntitySnapshot, frog: GameplayState) -> bool:
	if frog == null or not frog.frog.flags & FrogFlags.ACTIVE:
		return false
	var delta := Vector3i.ZERO
	for axis: int in 3:
		delta[axis] = PlatformMath.s16(frog.frog.matrix12[9 + axis] - PlatformMath.s16(entity.matrix12[9 + axis]))
	var squared: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	return int(sqrt(float(maxi(0, squared)))) < 1024
