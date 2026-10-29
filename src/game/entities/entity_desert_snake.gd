class_name EntityDesertSnake
extends RefCounted
## Desert snake range requests, rattle sounds and path-end turn hold.

enum Action { NORMAL, BITE, TURNING, RATTLE }

## Source DES_SNAKE_BITE_RANGE and DES_SNAKE_RATTLE_RANGE.
const BITE_RANGE: int = 256
const RATTLE_RANGE: int = 512
## Source SFX_DES_SNAKE_RATTLE.
const RATTLE_SOUND: int = 59
## Updates counted down after the turning action is set before the snake resumes.
const TURN_HOLD: int = 19
const LANE_HALF_WIDTH: int = 64
## DistanceToFrogger probe on local Z.
const PROBE: Vector3i = Vector3i(0, 0, 512)

## Clears the request, hold count and NO_MOVEMENT; the caller also forces the path runner active.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.custom_state.mode = Action.NORMAL
	entity.custom_state.requested_action = -1
	entity.custom_state.count = 0
	entity.entity_flags &= ~EntityDefinition.NO_MOVEMENT

## Whether frog 0 lies strictly within 64 units of the snake on the lane axis its rotation selects.
static func in_lane(entity_matrix: PackedInt32Array, frog: GameplayState) -> bool:
	if frog == null:
		return false
	var axis: int = 2 if absi(entity_matrix[2]) > absi(entity_matrix[8]) else 0
	var frog_value: int = frog.frog.matrix12[9 + axis]
	var centre: int = entity_matrix[9 + axis]
	return frog_value > centre - LANE_HALF_WIDTH and frog_value < centre + LANE_HALF_WIDTH

## Applies the source action switch, path-end turn and deferred action change for frog 0.
static func update(_definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.custom_state == null or entity.path == null or entity.animation == null or entity.animation.lengths.size() < 4:
		return "Desert snake requires its path and normal, bite, turning and rattle animation actions"
	var custom: EntityCustomState = entity.custom_state
	var animation: EntityAnimationState = entity.animation
	entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	var distance: int = EntityFrogDistance.distance(entity.matrix12, PROBE, frog)
	match animation.action:
		Action.NORMAL:
			if distance < BITE_RANGE and in_lane(entity.matrix12, frog):
				_request(custom, Action.BITE)
			if distance > BITE_RANGE and distance < RATTLE_RANGE:
				_request(custom, Action.RATTLE)
		Action.RATTLE:
			if distance < BITE_RANGE:
				entity.requests.append(TickEvent.sound(RATTLE_SOUND))
				if in_lane(entity.matrix12, frog):
					_request(custom, Action.BITE)
			if distance > RATTLE_RANGE:
				_request(custom, Action.NORMAL)
			elif animation.finished():
				entity.requests.append(TickEvent.sound(RATTLE_SOUND))
		Action.BITE:
			if distance > BITE_RANGE:
				_request(custom, Action.NORMAL)
		Action.TURNING:
			if custom.count == 0:
				_request(custom, Action.NORMAL)
				entity.entity_flags &= ~EntityDefinition.NO_MOVEMENT
				result.path_active_request = 1
			else:
				custom.count -= 1
	if entity.path.flags & (PathStart.JUST_BOUNCED_START | PathStart.JUST_BOUNCED_END):
		animation.select(Action.TURNING)
		custom.count = TURN_HOLD
		entity.entity_flags |= EntityDefinition.NO_MOVEMENT
		result.path_active_request = 0
	if custom.requested_action >= 0 and animation.finished():
		animation.select(custom.requested_action)
		custom.requested_action = -1
	return ""

static func _request(custom: EntityCustomState, action: int) -> void:
	custom.requested_action = action
	custom.mode = action
