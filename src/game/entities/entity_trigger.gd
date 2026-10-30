class_name EntityTrigger
extends RefCounted
## Frozen ENTSTRUpdateTrigger and TriggerEntityCallback as ordered target effects.

enum Type { FREEZE, REVERSE, START, BEGIN }

## Pauses every listed target once, on the first update after creation; absent targets are skipped.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	if definition.trigger == null:
		return "Trigger requires its type and target IDs"
	var custom: EntityCustomState = result.entity.custom_state
	if not custom.initialized:
		_targets(definition, result, EntityTargetEffect.Kind.PAUSE)
		custom.initialized = true
	return ""

## Requests the callback's per-type target change; the caller applies the frog side effects.
## The source REVERSE case only clears PATH_RUNNER_BACKWARDS, so it maps to FORWARD.
static func contact(definition: EntityDefinition, result: EntityCustomResult) -> String:
	if definition.trigger == null or result.entity.custom_state == null:
		return "Trigger callback requires its initialized behavior"
	match definition.trigger.trigger_type:
		Type.FREEZE, Type.START:
			_targets(definition, result, EntityTargetEffect.Kind.TOGGLE)
		Type.REVERSE:
			_targets(definition, result, EntityTargetEffect.Kind.FORWARD)
		Type.BEGIN:
			_targets(definition, result, EntityTargetEffect.Kind.RESUME)
		_:
			return "Trigger type is outside the supported source range"
	return ""

static func _targets(definition: EntityDefinition, result: EntityCustomResult, operation: EntityTargetEffect.Kind) -> void:
	for identity: int in definition.trigger.target_ids:
		if identity != -1:
			result.target_effects.append(EntityTargetEffect.create(identity, operation))
