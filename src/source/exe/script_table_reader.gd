class_name ScriptTableReader
extends RefCounted
## Reads the entity script table ([ScriptTable]) and every script it points at.


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
		var script_name: String = names.name_of(id)
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
		var decoded: EntityScript = read_script(script_reader, id, script_name, address)
		if script_reader.has_error():
			table.error = "script %s at 0x%X: %s" % [script_name, address, script_reader.error]
			return table
		table.scripts.append(decoded)
	return table


## Reads the script ([EntityScript]) at [param reader]'s cursor, command by
## command, until a final command or a word that is not a known opcode.
static func read_script(reader: ByteReader, script_id: int, script_name: String, address: int) -> EntityScript:
	var result := EntityScript.new()
	result.id = script_id
	result.name = script_name
	result.pointer = address
	while not reader.has_error() and reader.remaining() >= 4:
		var opcode: int = reader.s32_at(reader.get_position())
		if not ScriptOpcodes.is_valid(opcode):
			break
		var command := EntityScriptCommand.new()
		command.opcode = reader.read_s32()
		for _i: int in ScriptOpcodes.argument_count(opcode):
			command.arguments.append(reader.read_s32())
		result.commands.append(command)
		if ScriptOpcodes.is_final(opcode):
			break
	return result
