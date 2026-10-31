class_name ScriptTable
extends Resource
## The entity script table: an address per script id, and the decoded scripts.
##
## The table stores no length; as in FrogLord, it has as many entries as
## FrogLord's script name list (the main list, not its callback section). A
## zero address is the empty script (id 0, SCRIPT_NONE).

## Scripts in id order.
@export var scripts: Array[EntityScript] = []
## Why reading failed, or "".
@export var error: String = ""


## Number of scripts.
func size() -> int:
	return scripts.size()


## The script with id [param id], or null.
func get_script_by_id(id: int) -> EntityScript:
	return scripts[id] if id >= 0 and id < scripts.size() else null


## Total number of commands in all scripts.
func command_count() -> int:
	var n: int = 0
	for entity_script: EntityScript in scripts:
		n += entity_script.commands.size()
	return n
