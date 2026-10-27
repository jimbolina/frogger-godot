class_name EntityHedgehog
extends RefCounted
## Forest hedgehog running and rolling timers, action boundaries and path speed.

enum Mode { RUNNING, ROLLING, PREPARE_TO_ROLL, PREPARE_TO_RUN }

## Applies the source transition macro to a private instance.
static func start(definition: EntityDefinition, entity: EntitySnapshot, rolling: bool) -> int:
	entity.custom_state.mode = Mode.ROLLING if rolling else Mode.RUNNING
	entity.custom_state.timer = definition.forest.roll_time if rolling else definition.forest.run_time
	entity.animation.select(1 if rolling else 0)
	return definition.forest.roll_speed if rolling else definition.forest.run_speed

## Advances source timers before the shared pose-animation phase.
static func update(definition: EntityDefinition, result: EntityCustomResult, grid: GridDefinition = null) -> String:
	var entity: EntitySnapshot = result.entity
	if definition.forest == null or entity.path == null or entity.animation == null or entity.animation.lengths.size() < 2:
		return "Hedgehog requires authored timing, path and running/rolling actions"
	if entity.entity_flags & EntityDefinition.PROJECT_ON_LAND and not entity.entity_flags & EntityDefinition.ALIGN_TO_WORLD:
		entity.matrix12 = EntityTransform.moving_on_land(entity.path, entity.entity_flags, grid)
		if entity.matrix12.is_empty():
			return "Hedgehog projected path requires a valid first terrain square"
	else:
		entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.RUNNING, Mode.ROLLING:
			var rolling: bool = custom.mode == Mode.ROLLING
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 65535
			if expired:
				custom.mode = Mode.PREPARE_TO_RUN if rolling else Mode.PREPARE_TO_ROLL
			if rolling and entity.path.flags & (PathStart.JUST_REPEATED_START | PathStart.JUST_REPEATED_END):
				result.path_speed_request = start(definition, entity, false)
		Mode.PREPARE_TO_ROLL, Mode.PREPARE_TO_RUN:
			if entity.animation.cel >= entity.animation.lengths[entity.animation.action] - 1:
				result.path_speed_request = start(definition, entity, custom.mode == Mode.PREPARE_TO_ROLL)
	return ""
