class_name EntityMovementTarget
extends RefCounted
## Applies one ordered switch or trigger operation to a detached live target.

## Changes movement flags without resampling a path pose.
## FORWARD is frozen TriggerEntityCallback's REVERSE case: both of its branches clear
## PATH_RUNNER_BACKWARDS, so the source never reverses a target despite the trigger's name.
static func apply(effect: EntityTargetEffect, target: EntitySnapshot, definition: EntityDefinition) -> String:
	if effect.kind == EntityTargetEffect.Kind.REVERSE:
		if target.path == null:
			return "Colour-switch reverse requires a path target"
		target.path.flags ^= PathStart.BACKWARDS
		return ""
	if effect.kind == EntityTargetEffect.Kind.FORWARD:
		if target.path == null:
			return "Trigger reverse requires a path target"
		target.path.flags &= ~PathStart.BACKWARDS
		return ""
	if effect.kind == EntityTargetEffect.Kind.RESUME and not target.entity_flags & EntityDefinition.NO_MOVEMENT:
		return ""
	var stopped: bool = not bool(target.entity_flags & EntityDefinition.NO_MOVEMENT)
	if effect.kind == EntityTargetEffect.Kind.INITIALIZE:
		if definition.volcano == null:
			return "Colour-switch initialization requires target movement operands"
		stopped = definition.volcano.initial_movement == 1
	elif effect.kind == EntityTargetEffect.Kind.PAUSE:
		stopped = true
	elif effect.kind == EntityTargetEffect.Kind.RESUME:
		stopped = false
	target.entity_flags = target.entity_flags | EntityDefinition.NO_MOVEMENT if stopped else target.entity_flags & ~EntityDefinition.NO_MOVEMENT
	if target.path != null:
		target.path.flags = target.path.flags & ~PathStart.ACTIVE if stopped else target.path.flags | PathStart.ACTIVE
	return ""
