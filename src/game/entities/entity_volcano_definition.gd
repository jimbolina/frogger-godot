class_name EntityVolcanoDefinition
extends RefCounted
## Detached Volcano trigger, path and falling-platform operands.

var play_chain_sound: bool = false
var trigger_type: int = 0
var colour: int = 0
var target_ids: PackedInt32Array = PackedInt32Array()
var initial_movement: int = 0
var hops_before: int = 0

## Copies authored operands without sharing the target list.
func copy() -> EntityVolcanoDefinition:
	var result := EntityVolcanoDefinition.new()
	result.play_chain_sound = play_chain_sound
	result.trigger_type = trigger_type
	result.colour = colour
	result.target_ids = target_ids.duplicate()
	result.initial_movement = initial_movement
	result.hops_before = hops_before
	return result
