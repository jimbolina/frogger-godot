class_name EntityJungleRopeBridge
extends RefCounted
## Jungle rope bridge that counts landings, waits, then collapses and drops its rider.

enum Mode { WAITING_FOR_HITS, WAITING_TO_FALL, FALLING }

## Holds the one-shot collapse animation on cel zero and enables collision for a fresh bridge.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.WAITING_FOR_HITS
	custom.timer = 0
	custom.count = 0
	if entity.animation != null:
		entity.animation.cel = 0
		entity.animation.stepping = false
		entity.animation.one_shot = true
	entity.entity_flags &= ~EntityDefinition.NO_COLLISION

## Advances one bridge step from the previous tick's HIT; custom.count is the 8-bit hit count and custom.timer the 16-bit wait.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool) -> String:
	var jungle: EntityJungleDefinition = definition.jungle
	if jungle == null:
		return "Jungle rope bridge requires its fall delay and hop count"
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.action < 0 or entity.animation.action >= entity.animation.lengths.size():
		return "Jungle rope bridge requires its collapse animation"
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.WAITING_FOR_HITS:
			if hit:
				custom.count = (custom.count + 1) & 255
				if custom.count >= jungle.hops_before:
					custom.timer = jungle.fall_delay
					custom.mode = Mode.WAITING_TO_FALL
		Mode.WAITING_TO_FALL:
			var previous: int = custom.timer
			custom.timer = (previous - 1) & 65535
			if previous == 0:
				custom.mode = Mode.FALLING
				entity.animation.stepping = true
				entity.entity_flags |= EntityDefinition.NO_COLLISION
				result.frog_fall_requested = frog != null and frog.attachment.current_entity_index == entity.entity_index
	return ""
