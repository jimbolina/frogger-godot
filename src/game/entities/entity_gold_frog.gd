class_name EntityGoldFrog
extends RefCounted
## Golden frog collection visual lifetime driven by committed simulation ticks.

enum Mode { WAITING, JUMPING, FINISHED }

## Starts a pop on the prior collision and retires it after its source clock.
static func update(entity: EntitySnapshot, hit: bool) -> void:
	match entity.custom_state.mode:
		Mode.WAITING:
			if hit:
				entity.pop_allocated = true
				entity.pop_remaining = 32
				entity.custom_state.model_hidden = true
				entity.custom_state.mode = Mode.JUMPING
				entity.requests.append(TickEvent.make(TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST))
		Mode.JUMPING:
			if entity.pop_allocated and entity.pop_remaining == 0:
				entity.pop_allocated = false
				entity.custom_state.mode = Mode.FINISHED
