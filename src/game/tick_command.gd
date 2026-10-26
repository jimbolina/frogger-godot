class_name TickCommand
extends RefCounted
## One ordered tick's logical directional edges and held state, supplied by presentation.

const NORTH: int = 1
const EAST: int = 2
const SOUTH: int = 4
const WEST: int = 8
const SUPER_HOP: int = 16
const CAMERA_CLOCKWISE: int = 32
const CAMERA_ANTICLOCKWISE: int = 64
## Raw C demo action byte; -1 selects live controller input.
var recorded_input_byte: int = -1
## Signals an exhausted stream; only a consuming control boundary rejects it.
var recorded_input_exhausted: bool = false
var tick_index: int = 0
var pressed_mask: int = 0
var held_mask: int = 0
## External game-loop context; -1 retains the explicitly authored component value.
var start_timer_context: int = -1
## Explicit host/HUD completion, accepted only while single-start bounce/rest is active.
var start_sequence_complete: bool = false

## Detaches input before transferring it to an ordered worker transaction.
func copy() -> TickCommand:
	var result := TickCommand.new()
	result.recorded_input_byte = recorded_input_byte
	result.recorded_input_exhausted = recorded_input_exhausted
	result.tick_index = tick_index
	result.pressed_mask = pressed_mask
	result.held_mask = held_mask
	result.start_timer_context = start_timer_context
	result.start_sequence_complete = start_sequence_complete
	return result
