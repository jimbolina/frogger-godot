class_name BindingInput
extends RefCounted
## Turns Godot key events into player actions through one [KeyBindings] record.
##
## A key event becomes a DirectInput scancode by its physical key and location
## ([method KeyScancodes.from_godot]); an event without a physical key uses its key code.
## The record's nine actions map to the gameplay [TickCommand] bits. Menu keys (Enter,
## Space, Escape) are fixed and never go through this class.

## [TickCommand] bit of each [enum KeyBindings.Action], in action order.
const COMMANDS: PackedInt32Array = [
	TickCommand.WEST, TickCommand.EAST, TickCommand.NORTH, TickCommand.SOUTH, TickCommand.SUPER_HOP,
	TickCommand.TONGUE, TickCommand.CROAK, TickCommand.CAMERA_CLOCKWISE, TickCommand.CAMERA_ANTICLOCKWISE,
]

## The bindings read.
var bindings: KeyBindings
## The record (player index) read.
var record: int = 0


func _init(source: KeyBindings = null, player: int = 0) -> void:
	bindings = source if source != null else KeyBindings.create_default()
	record = player


## Player 1 of the saved [param key_bindings] array, or of the shipped defaults when it is
## empty or malformed.
static func from_array(key_bindings: PackedInt32Array) -> BindingInput:
	return BindingInput.new(KeyBindings.from_array(key_bindings))


## The scancode of [param event], or [constant KeyScancodes.UNKNOWN].
static func scancode(event: InputEventKey) -> int:
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return KeyScancodes.from_godot(key, event.location)


## The [enum KeyBindings.Action] [param event]'s key is bound to, or -1.
func action(event: InputEventKey) -> int:
	var code: int = scancode(event)
	if code == KeyScancodes.UNKNOWN:
		return -1
	return bindings.action_for(record, code)


## The [TickCommand] bit [param event]'s key is bound to, or 0.
func command(event: InputEventKey) -> int:
	var bound: int = action(event)
	return COMMANDS[bound] if bound >= 0 else 0
