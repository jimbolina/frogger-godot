class_name EntityCustomState
extends RefCounted
## Owned custom continuation for the supported fly and pink frog.

var mode: int = 0
var timer: int = 60
var checkpoint_index: int = -1
var search_count: int = 0
var model_hidden: bool = false
var parent_entity_index: int = -1
var direction: int = 0
var delay: int = 0
var count: int = 0
var cell: Vector2i = Vector2i.ZERO
var offset_16: Vector3i = Vector3i.ZERO
var velocity_16: Vector3i = Vector3i.ZERO
var target: Vector3i = Vector3i.ZERO
var moving_sound: PackedInt32Array = PackedInt32Array()
var carrier_index: int = -1
var carried_jump_ticks: int = 0
var dead: bool = false

## Copies every custom continuation value.
func copy() -> EntityCustomState:
	var result := EntityCustomState.new()
	result.mode = mode
	result.timer = timer
	result.checkpoint_index = checkpoint_index
	result.search_count = search_count
	result.model_hidden = model_hidden
	result.parent_entity_index = parent_entity_index
	result.direction = direction
	result.delay = delay
	result.count = count
	result.cell = cell
	result.offset_16 = offset_16
	result.velocity_16 = velocity_16
	result.target = target
	result.moving_sound = moving_sound.duplicate()
	result.carrier_index = carrier_index
	result.carried_jump_ticks = carried_jump_ticks
	result.dead = dead
	return result
