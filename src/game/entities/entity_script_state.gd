class_name EntityScriptState
extends RefCounted
## Owned script cursors, source-width timer/deviation and callback slots.

var active: bool = true
var entity_type: int = 0
var position: Vector3i = Vector3i.ZERO
var user_data: int = 0
var return_program: int = -1
var return_cursor: int = -1
var return_loop_start: int = -1
var return_loop_end: int = -1
var root_id: int = -1
var program_id: int = -1
var cursor: int = 0
var loop_start: int = -1
var loop_end: int = -1
var timer: int = 0
var registers: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var offsets: Vector3i = Vector3i.ZERO
var deltas: Vector3i = Vector3i.ZERO
var destinations: Vector3i = Vector3i.ZERO
var counts: Vector3i = Vector3i.ZERO
var angles: Vector3i = Vector3i.ZERO
var angular_deltas: Vector3i = Vector3i.ZERO
var angular_destinations: Vector3i = Vector3i.ZERO
var angular_counts: Vector3i = Vector3i.ZERO
## Historical Y-only trace fields project the complete source vectors.
var deviation: int:
	get:
		return offsets.y
	set(value):
		offsets.y = value
var delta: int:
	get:
		return deltas.y
	set(value):
		deltas.y = value
var destination: int:
	get:
		return destinations.y
	set(value):
		destinations.y = value
var remaining: int:
	get:
		return counts.y
	set(value):
		counts.y = value
## Callback id, condition, kind, called; empty slots have id -1.
var callbacks: Array[PackedInt32Array] = [PackedInt32Array([-1, 0, 0, 0]), PackedInt32Array([-1, 0, 0, 0])]
var moving_sound: PackedInt32Array = PackedInt32Array()
var colours: Vector3i = Vector3i.ZERO
var ambient: Vector3i = Vector3i.ZERO
var no_screen_fade: bool = false

## Source StartScript resets the script state before installing its root.
static func create(root: int) -> EntityScriptState:
	var result := EntityScriptState.new()
	result.root_id = root
	result.program_id = root
	return result

## Copies all state for an unpublished candidate update.
func copy() -> EntityScriptState:
	var result: EntityScriptState = EntityScriptState.create(root_id)
	result.active = active
	result.entity_type = entity_type
	result.position = position
	result.user_data = user_data
	result.return_program = return_program
	result.return_cursor = return_cursor
	result.return_loop_start = return_loop_start
	result.return_loop_end = return_loop_end
	result.program_id = program_id
	result.cursor = cursor
	result.loop_start = loop_start
	result.loop_end = loop_end
	result.timer = timer
	result.registers = registers.duplicate()
	result.offsets = offsets
	result.deltas = deltas
	result.destinations = destinations
	result.counts = counts
	result.angles = angles
	result.angular_deltas = angular_deltas
	result.angular_destinations = angular_destinations
	result.angular_counts = angular_counts
	for slot: int in 2:
		result.callbacks[slot] = callbacks[slot].duplicate()
	result.moving_sound = moving_sound.duplicate()
	result.colours = colours
	result.ambient = ambient
	result.no_screen_fade = no_screen_fade
	return result
