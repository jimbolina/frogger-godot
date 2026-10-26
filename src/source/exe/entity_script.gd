class_name EntityScript
extends RefCounted
## One entity script from the executable: a list of commands.
##
## A script is read command by command from its address until a STOP,
## RESTART or END command, or until a word that is not a known opcode
## (FrogLord's [code]FroggerScript.load[/code]; the second case means the
## script is damaged or the build differs, and ends reading without an error).


## One command: an opcode and its arguments.
class Command:
	extends RefCounted
	## The opcode, see [ScriptOpcodes].
	var opcode: int = 0
	## The arguments, as signed 32-bit values.
	var arguments: PackedInt32Array = PackedInt32Array()

	## The opcode's name, e.g. "SET_TIMER".
	func name() -> String:
		return ScriptOpcodes.name_of(opcode)


## Position in the script table (the script id forms use).
var id: int = 0
## FrogLord's name for the script, e.g. "SCRIPT_ORG_CROCODILE".
var name: String = ""
## Address of the script in the program (0 = the empty script).
var pointer: int = 0
## Commands in order.
var commands: Array[Command] = []


## Reads the script at [param reader]'s cursor.
static func read(reader: ByteReader, script_id: int, script_name: String, address: int) -> EntityScript:
	var result := EntityScript.new()
	result.id = script_id
	result.name = script_name
	result.pointer = address
	while not reader.has_error() and reader.remaining() >= 4:
		var opcode: int = reader.s32_at(reader.get_position())
		if not ScriptOpcodes.is_valid(opcode):
			break
		var command := Command.new()
		command.opcode = reader.read_s32()
		for _i: int in ScriptOpcodes.argument_count(opcode):
			command.arguments.append(reader.read_s32())
		result.commands.append(command)
		if ScriptOpcodes.is_final(opcode):
			break
	return result


## The script as the flat word list it is stored as (opcodes and arguments).
func words() -> PackedInt32Array:
	var out := PackedInt32Array()
	for command: Command in commands:
		out.append(command.opcode)
		out.append_array(command.arguments)
	return out


## True for the empty script (a null entry in the table).
func is_empty() -> bool:
	return commands.is_empty()
