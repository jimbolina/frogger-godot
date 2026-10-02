class_name FrogAnimationState
extends RefCounted
## Detached authoritative animation-control and virtual-cel state; no renderer objects.

var script_type: int = FrogAnimationCatalog.PANT
var flags: int = 18
var program_id: int = FrogAnimationCatalog.PANT
var word_offset: int = 0
var queued_type: int = -1
var queued_flags: int = 0
var previous_type: int = -1
var previous_flags: int = 0
var script_timer: int = 0
var delay_timer: int = 0
var action: int = 0
var cel: int = 0
var total_cels: int = 0
var environment_flags: int = 7168
var update_count: int = 0
var no_input_timer: int = 0
var loop_start_program: int = -1
var loop_start_offset: int = -1
var loop_end_program: int = -1
var loop_end_offset: int = -1
var queue_program: int = -1
var queue_offset: int = -1
var previous_program: int = -1
var previous_offset: int = -1

## True when the source environment holds the last virtual cel instead of looping.
func is_one_shot() -> bool:
	return (environment_flags & 256) != 0

## Returns an independent snapshot with no shared mutable animation state.
func copy() -> FrogAnimationState:
	var result := FrogAnimationState.new()
	result.script_type = script_type
	result.flags = flags
	result.program_id = program_id
	result.word_offset = word_offset
	result.queued_type = queued_type
	result.queued_flags = queued_flags
	result.previous_type = previous_type
	result.previous_flags = previous_flags
	result.script_timer = script_timer
	result.delay_timer = delay_timer
	result.action = action
	result.cel = cel
	result.total_cels = total_cels
	result.environment_flags = environment_flags
	result.update_count = update_count
	result.no_input_timer = no_input_timer
	result.loop_start_program = loop_start_program
	result.loop_start_offset = loop_start_offset
	result.loop_end_program = loop_end_program
	result.loop_end_offset = loop_end_offset
	result.queue_program = queue_program
	result.queue_offset = queue_offset
	result.previous_program = previous_program
	result.previous_offset = previous_offset
	return result

## Ordered component facts corresponding to the independent C trace after phase labels.
func facts(context: FrogAnimationContext) -> PackedInt64Array:
	return PackedInt64Array([script_type, flags, program_id, word_offset, queued_type,
		queued_flags, previous_type, previous_flags, script_timer, delay_timer, action,
		cel, total_cels, environment_flags, update_count, no_input_timer,
		context.if_counter, context.random.state, loop_start_program, loop_start_offset,
		loop_end_program, loop_end_offset, queue_program, queue_offset, previous_program, previous_offset])
