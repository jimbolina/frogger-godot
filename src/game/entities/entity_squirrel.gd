class_name EntitySquirrel
extends RefCounted
## Forest squirrel path bounces pause until its source turning action finishes.

enum Mode { RUNNING, TURNING }

## Advances source action selection without applying the unused authored delay.
static func update(_definition: EntityDefinition, result: EntityCustomResult) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.path == null or entity.animation == null or entity.animation.lengths.size() < 2:
		return "Squirrel requires its path and running/turning animation actions"
	entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	if entity.custom_state.mode == Mode.RUNNING:
		if entity.path.flags & (PathStart.JUST_BOUNCED_START | PathStart.JUST_BOUNCED_END):
			entity.animation.select(1)
			entity.custom_state.mode = Mode.TURNING
			result.path_active_request = 0
	elif entity.animation.cel >= entity.animation.lengths[entity.animation.action] - 1:
		entity.animation.select(0)
		entity.custom_state.mode = Mode.RUNNING
		result.path_active_request = 1
	return ""
