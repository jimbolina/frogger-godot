class_name EntityVolcanoMovingPlatform
extends RefCounted
## Volcano chain-sound ownership after the ordinary path transform update.

## Requests movement sound creation or retirement from authored movement state.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	if definition.volcano == null:
		return "Moving platform requires authored movement operands"
	if result.entity.path == null:
		return "Moving platform requires its path cursor"
	result.entity.matrix12 = EntityTransform.moving(result.entity.path, result.entity.entity_flags)
	if not definition.volcano.play_chain_sound:
		return ""
	if result.entity.entity_flags & EntityDefinition.NO_MOVEMENT:
		result.stop_moving_sound = true
		result.entity.custom_state.moving_sound.clear()
	else:
		result.entity.custom_state.moving_sound = PackedInt32Array([166, 1024, 2048])
		result.entity.requests.append(TickEvent.moving_sound(166, 1024, 2048))
	return ""
