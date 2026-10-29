class_name EntityDesertVulture
extends RefCounted
## Desert vulture swoop requests from the path tangent and its moving sound.

enum Action { NORMAL, SWOOP }

## Tangent Y separating swoop from normal flight; equality keeps the requested action.
const DIVE_TANGENT: int = -128
## Source SFX_DES_VULTURE and its PlayMovingSound radii.
const SOUND: int = 60
const SOUND_NEAR: int = 1024
const SOUND_FAR: int = 2048

## Switches on the requested action, kept in mode, and applies a pending request on the last cel.
static func update(_definition: EntityDefinition, result: EntityCustomResult) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.custom_state == null or entity.path == null or entity.animation == null or entity.animation.lengths.size() < 2:
		return "Desert vulture requires its path and normal and swoop animation actions"
	var custom: EntityCustomState = entity.custom_state
	entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	var tangent_y: int = entity.path.tangent.y
	match custom.mode:
		Action.NORMAL:
			if tangent_y > DIVE_TANGENT:
				custom.requested_action = Action.SWOOP
				custom.mode = Action.SWOOP
				if custom.moving_sound.is_empty():
					custom.moving_sound = PackedInt32Array([SOUND, SOUND_NEAR, SOUND_FAR])
					entity.requests.append(TickEvent.moving_sound(SOUND, SOUND_NEAR, SOUND_FAR))
		Action.SWOOP:
			if tangent_y < DIVE_TANGENT:
				custom.requested_action = Action.NORMAL
				custom.mode = Action.NORMAL
	if custom.requested_action >= 0 and entity.animation.finished():
		entity.animation.select(custom.requested_action)
		custom.requested_action = -1
	return ""
