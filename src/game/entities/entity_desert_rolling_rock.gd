class_name EntityDesertRollingRock
extends RefCounted
## Frozen Desert rolling rock: path-following roll that explodes and pauses on each path repeat.

## Source DES_ROLLING_ROCK_* order.
enum Mode { ROLLING, EXPLODING }

## Source rr_rotation step about the local X axis per ROLLING update.
const ROLL_STEP: int = 0x40

## Source ENTSTRDesCreateRollingRock: ROLLING with zero roll and collision on. The source leaves
## rr_matrix's translation uninitialized until the first rolling update; custom.target holds it
## and starts at the creation translation here.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	if entity.custom_state == null:
		entity.custom_state = EntityCustomState.new()
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.ROLLING
	custom.direction = 0
	custom.overlay_animation = null
	custom.model_hidden = false
	custom.target = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	entity.entity_flags &= ~EntityDefinition.NO_COLLISION

## Source ENTSTRDesUpdateRollingRock after this tick's path step. A JUST_REPEATED tick starts the
## explosion at the translation copied on the previous rolling update, pauses the path
## (path_active_request 0), turns collision off and hides the mesh. The update that sees the last
## explosion cel resumes the path (request 1) with zero roll. On error nothing is changed.
static func update(definition: EntityDefinition, result: EntityCustomResult, grid: GridDefinition = null) -> String:
	var entity: EntitySnapshot = result.entity
	if entity == null or entity.custom_state == null or entity.path == null:
		return "Rolling rock requires initialized custom state and a path"
	if definition.desert == null or not EntityDesertExplosion.valid(definition.desert.explosion_action_lengths):
		return "Rolling rock requires an explosion flipbook with a nonempty first action"
	var custom: EntityCustomState = entity.custom_state
	if custom.mode != Mode.ROLLING and custom.mode != Mode.EXPLODING:
		return "Rolling rock has an unknown mode %d" % custom.mode
	if custom.mode == Mode.EXPLODING and custom.overlay_animation == null:
		return "Exploding rolling rock has no explosion flipbook"
	var matrix: PackedInt32Array
	if entity.entity_flags & EntityDefinition.PROJECT_ON_LAND and not entity.entity_flags & EntityDefinition.ALIGN_TO_WORLD:
		matrix = EntityTransform.moving_on_land(entity.path, entity.entity_flags, grid)
		if matrix.is_empty():
			return "Rolling rock projected path requires a valid first terrain square"
	else:
		matrix = EntityTransform.moving(entity.path, entity.entity_flags)
	entity.matrix12 = matrix
	match custom.mode:
		Mode.ROLLING:
			custom.direction = (custom.direction - ROLL_STEP) & 4095
			entity.matrix12 = PlatformMath.rotate_x(entity.matrix12, custom.direction)
			if entity.path.flags & (PathStart.JUST_REPEATED_START | PathStart.JUST_REPEATED_END):
				custom.mode = Mode.EXPLODING
				EntityDesertExplosion.start(entity, definition.desert.explosion_action_lengths, custom.target)
				result.path_active_request = 0
				entity.entity_flags |= EntityDefinition.NO_COLLISION
			else:
				custom.target = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		Mode.EXPLODING:
			if EntityDesertExplosion.done(custom):
				custom.mode = Mode.ROLLING
				custom.direction = 0
				EntityDesertExplosion.finish(custom)
				result.path_active_request = 1
				entity.entity_flags &= ~EntityDefinition.NO_COLLISION
	return ""
