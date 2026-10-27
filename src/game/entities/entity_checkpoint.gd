class_name EntityCheckpoint
extends RefCounted
## Persistent checkpoint croak modes and source animation transitions.

## Advances one private checkpoint and shared mode using pre-control frog position.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog_position: Vector3i) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.animation == null or entity.animation.action < 0:
		return ""
	var index: int = definition.form_id & 32767
	if index >= 5:
		return "Checkpoint animation requires a valid checkpoint identity"
	var animation: EntityAnimationState = entity.animation
	var selected: int = -1
	var next_mode: int = result.environment.croak_modes[index]
	match next_mode:
		0:
			if animation.cel == 0:
				var squared: int = 0
				for axis: int in 3:
					var delta: int = PlatformMath.s32(frog_position[axis] - entity.matrix12[9 + axis])
					squared = (squared + delta * delta) & 0xffffffff
				if squared < 512 * 512 and result.random.next_value("entity:%d:checkpoint_croak" % definition.entity_index) % 10 == 1:
					selected = 2
					next_mode = 3
		1:
			if animation.cel == 0:
				selected = 1
				next_mode = 2
		2, 3:
			if animation.cel >= animation.lengths[animation.action] - 1:
				selected = 0
				next_mode = 0
	if selected >= 0:
		if selected >= animation.lengths.size() or animation.lengths[selected] <= 0:
			return "Checkpoint model lacks its requested source action"
		animation.select(selected)
		result.environment.croak_modes[index] = next_mode
	return ""
