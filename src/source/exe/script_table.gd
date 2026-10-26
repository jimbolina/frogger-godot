class_name ScriptTable
extends RefCounted
## The entity script table: an address per script id, and the decoded scripts.
##
## The table stores no length; as in FrogLord, it has as many entries as
## FrogLord's script name list (the main list, not its callback section). A
## zero address is the empty script (id 0, SCRIPT_NONE).

## Scripts in id order.
var scripts: Array[EntityScript] = []
## Why reading failed, or "".
var error: String = ""


## Reads the script table of [param exe], sized and named by [param names].
static func read(exe: ExeImage, names: NameBank) -> ScriptTable:
	var table := ScriptTable.new()
	var start: int = exe.version.scripts
	if start <= 0:
		table.error = "this build has no script table address"
		return table
	var reader: ByteReader = exe.reader_at(start)
	for id: int in names.size():
		var address: int = reader.read_u32()
		var script_name: String = names.get_name(id)
		if reader.has_error():
			table.error = "script table: %s" % reader.error
			return table
		if address == 0:
			var empty := EntityScript.new()
			empty.id = id
			empty.name = script_name
			table.scripts.append(empty)
			continue
		var script_reader: ByteReader = exe.reader_at_pointer(address)
		var decoded: EntityScript = EntityScript.read(script_reader, id, script_name, address)
		if script_reader.has_error():
			table.error = "script %s at 0x%X: %s" % [script_name, address, script_reader.error]
			return table
		table.scripts.append(decoded)
	return table


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
