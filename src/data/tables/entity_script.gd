class_name EntityScript
extends Resource
## One entity script from the executable: a list of commands.
##
## A script is read command by command from its address until a STOP,
## RESTART or END command, or until a word that is not a known opcode
## (FrogLord's [code]FroggerScript.load[/code]; the second case means the
## script is damaged or the build differs, and ends reading without an error).


## One command ([EntityScriptCommand]); kept so existing references still resolve.
const Command := preload("res://src/data/tables/entity_script_command.gd")

## Position in the script table (the script id forms use).
@export var id: int = 0
## FrogLord's name for the script, e.g. "SCRIPT_ORG_CROCODILE".
@export var name: String = ""
## Address of the script in the program (0 = the empty script).
@export var pointer: int = 0
## Commands in order.
@export var commands: Array[EntityScriptCommand] = []


## The script as the flat word list it is stored as (opcodes and arguments).
func words() -> PackedInt32Array:
	var out := PackedInt32Array()
	for command: EntityScriptCommand in commands:
		out.append(command.opcode)
		out.append_array(command.arguments)
	return out


## True for the empty script (a null entry in the table).
func is_empty() -> bool:
	return commands.is_empty()
