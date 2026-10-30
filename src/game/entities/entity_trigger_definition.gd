class_name EntityTriggerDefinition
extends RefCounted
## Detached ENTSTR_TRIGGER type and ten target unique IDs, -1 where unused.

var trigger_type: int = 0
var target_ids: PackedInt32Array = PackedInt32Array()

## Copies authored operands without sharing the target list.
func copy() -> EntityTriggerDefinition:
	var result := EntityTriggerDefinition.new()
	result.trigger_type = trigger_type
	result.target_ids = target_ids.duplicate()
	return result
