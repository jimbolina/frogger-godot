class_name EntityDesertExplosion
extends RefCounted
## Map WAD slot-1 explosion flipbook that a Desert rock plays in place of its hidden mesh.
##
## The flipbook lives in custom.overlay_animation. EntityRun.advance_animations advances it once
## per tick after the entity update, as the source MRAnimUpdateEnvironments step does, so the
## creating update leaves cel -1 and the first drawn cel is 0.

## Whether lengths describe a playable explosion: a nonempty first action.
static func valid(lengths: PackedInt32Array) -> bool:
	return not lengths.is_empty() and lengths[0] > 0

## Creates the one-shot flipbook on action 0 at a fixed world position and hides the rock mesh.
static func start(entity: EntitySnapshot, lengths: PackedInt32Array, position: Vector3i) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.overlay_animation = EntityAnimationState.create(lengths, true)
	custom.overlay_animation.select(0)
	custom.overlay_position = position
	custom.model_hidden = true

## Whether the update sees the flipbook's last cel, the source total_cels - 1 test.
static func done(custom: EntityCustomState) -> bool:
	return custom.overlay_animation != null and custom.overlay_animation.finished()

## Destroys the flipbook; the rock mesh is shown again unless show_model is false.
static func finish(custom: EntityCustomState, show_model: bool = true) -> void:
	custom.overlay_animation = null
	custom.model_hidden = not show_model
