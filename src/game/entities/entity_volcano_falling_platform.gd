class_name EntityVolcanoFallingPlatform
extends RefCounted
## Frozen prior-HIT counter and delayed one-shot collapse with rider release.

enum Mode { WAITING_FOR_HITS, WAITING_TO_FALL, FALLING }

## Advances one falling platform without translating its authored matrix.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool) -> String:
	if definition.volcano == null:
		return "Falling platform requires authored crack operands"
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.WAITING_FOR_HITS:
			if hit:
				custom.count = (custom.count + 1) & 255
				if custom.count >= definition.volcano.hops_before:
					custom.timer = definition.authored_delay
					custom.mode = Mode.WAITING_TO_FALL
			else:
				custom.texture_animation_paused = true
		Mode.WAITING_TO_FALL:
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 65535
			if expired:
				custom.mode = Mode.FALLING
				entity.requests.append(TickEvent.sound(171))
				entity.animation.stepping = true
				entity.animation.one_shot = true
				entity.entity_flags |= EntityDefinition.NO_COLLISION
				result.frog_fall_requested = frog != null and frog.attachment.current_entity_index == entity.entity_index
	return ""
