class_name EntityScriptCommand
extends Resource
## One entity script command: an opcode and its arguments.

## The opcode, see [ScriptOpcodes].
@export var opcode: int = 0
## The arguments, as signed 32-bit values.
@export var arguments: PackedInt32Array = PackedInt32Array()


## The opcode's name, e.g. "SET_TIMER".
func name() -> String:
	return ScriptOpcodes.name_of(opcode)
