class_name EntityVolcanoTarget
extends RefCounted
## Applies one ordered switch operation to a detached live target.

## Changes movement flags without resampling a path pose.
static func apply(effect: EntityTargetEffect, target: EntitySnapshot, definition: EntityDefinition) -> String:
	if effect.kind == EntityTargetEffect.Kind.REVERSE:
		if target.path == null:
			return "Colour-switch reverse requires a path target"
		target.path.flags ^= PathStart.BACKWARDS
		return ""
	var stopped: bool = not bool(target.entity_flags & EntityDefinition.NO_MOVEMENT)
	if effect.kind == EntityTargetEffect.Kind.INITIALIZE:
		if definition.volcano == null:
			return "Colour-switch initialization requires target movement operands"
		stopped = definition.volcano.initial_movement == 1
	target.entity_flags = target.entity_flags | EntityDefinition.NO_MOVEMENT if stopped else target.entity_flags & ~EntityDefinition.NO_MOVEMENT
	if target.path != null:
		target.path.flags = target.path.flags & ~PathStart.ACTIVE if stopped else target.path.flags | PathStart.ACTIVE
	return ""
