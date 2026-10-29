class_name EntityJungleGoldFrog
extends RefCounted
## Jungle outro plinth gold frog: only the statue frog is shown, celebrating; plinth frogs stay hidden until the outro.

enum Mode { SITTING, JUMPING }
## Source GEN_GOLD_FROG action order shared by the general gold frog model.
enum Action { HOP, CROAK, LOOKAROUND, EXCITED, BACKFLIP, SIT }

## Source actions the model must supply because creation selects BACKFLIP before EXCITED.
const REQUIRED_ACTIONS: int = Action.BACKFLIP + 1

## Selects BACKFLIP, then hides and stops every frog except the statue frog, which selects EXCITED.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.entity_flags &= ~EntityDefinition.NO_DISPLAY
	var custom: EntityCustomState = entity.custom_state
	custom.mode = Mode.SITTING
	custom.count = 0
	if entity.animation != null:
		entity.animation.select(Action.BACKFLIP)
	if definition.jungle == null or definition.jungle.op_id != EntityJungleDefinition.GOLD_FROG_STATUE_ID:
		entity.entity_flags |= EntityDefinition.NO_DISPLAY
		if entity.animation != null:
			entity.animation.stepping = false
	elif entity.animation != null:
		entity.animation.select(Action.EXCITED)
