class_name EntityFly
extends RefCounted
## Bonus-fly checkpoint selection, visibility and lifetime updates.

enum Mode { WAITING, APPEARED }

## Advances a privately owned fly and shared checkpoint state.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	var entity: EntitySnapshot = result.entity
	var environment: EntityEnvironmentState = result.environment
	var custom: EntityCustomState = entity.custom_state
	var expired: bool = custom.timer == 0
	custom.timer -= 1
	if expired:
		if custom.mode == Mode.WAITING:
			if result.environment.covered != 0:
				result.error = "Fly requires uncollected checkpoint state"
				return result.error
			custom.checkpoint_index = result.random.next_value("entity:%d:checkpoint" % definition.entity_index) % 5
			var point: Vector3i = environment.checkpoint_positions[custom.checkpoint_index]
			entity.matrix12[9] = point.x
			entity.matrix12[10] = _short(point.y - 256)
			entity.matrix12[11] = _short(point.z - 50)
			result.environment.covered |= 1 << custom.checkpoint_index
			entity.entity_flags &= ~(EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION)
			custom.model_hidden = false
			custom.mode = Mode.APPEARED
			custom.timer = 120
		else:
			result.environment.covered &= ~(1 << custom.checkpoint_index)
			custom.checkpoint_index = -1
			custom.mode = Mode.WAITING
			custom.timer = 60
			entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
	return ""

static func _short(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low
