class_name EntityScriptSetup
extends RefCounted
## Resolves supplied executable programs and FrogLord callback names.

var error: String = ""
var definition: EntityScriptDefinition = null

## Copies only the reachable supported closure, with explicit turtle creation replacement.
static func from_tables(table: ScriptTable, names: NameBank, root_id: int, behavior: EntityBehavior, payload: PackedByteArray) -> EntityScriptSetup:
	var result := EntityScriptSetup.new()
	if table == null or names == null or not table.error.is_empty():
		result.error = "Script setup requires valid supplied tables and names"
		return result
	var decoded := EntityScriptDefinition.new()
	decoded.root_id = root_id
	var roots: Array[int] = [root_id]
	if behavior.payload_register_count > 0:
		if payload.size() < behavior.payload_offset + behavior.payload_register_count * 4:
			result.error = "Turtle payload requires PATH_INFO and three register words" if behavior.kind == EntityBehavior.Kind.TURTLE else "Static noise payload requires matrix and two register words"
			return result
		decoded.payload_offset = behavior.payload_offset
		for index: int in behavior.payload_register_count:
			decoded.payload_registers.append(payload.decode_s32(behavior.payload_offset + index * 4))
	if behavior.kind == EntityBehavior.Kind.TURTLE:
		if decoded.payload_registers[2] not in [0, 1]:
			result.error = "Unsupported turtle payload type"
			return result
		if decoded.payload_registers[2] == 1:
			decoded.root_id = names.index_of("SCRIPT_TURTLE_NO_DIVE")
			roots.append(decoded.root_id)
	var callback_names: NameBank = names.get_sub_bank("CallbackNames")
	while not roots.is_empty():
		var id: int = roots.pop_back()
		if decoded.programs.has(id):
			continue
		var program: EntityScript = table.get_script_by_id(id)
		if program == null or not EntityScriptDefinition.SUPPORTED_NAMES.has(program.name) or names.get_name(id) != program.name:
			result.error = "Unsupported supplied script id/name %d" % id
			return result
		decoded.programs[id] = program.words()
		decoded.names[id] = program.name
		for command: EntityScript.Command in program.commands:
			if not EntityScriptDefinition.WIDTHS.has(command.opcode):
				result.error = "Unsupported instruction %d in %s" % [command.opcode, program.name]
				return result
			if command.arguments.size() + 1 != EntityScriptDefinition.WIDTHS[command.opcode]:
				result.error = "Invalid instruction width in %s" % program.name
				return result
			if command.opcode == 13:
				roots.append(command.arguments[2])
			elif command.opcode == 34:
				var callback_id: int = command.arguments[1]
				if callback_names == null or not callback_names.has_name(callback_id) or not EntityScriptDefinition.CALLBACK_NAMES.has(callback_names.get_name(callback_id)):
					result.error = "Unsupported supplied callback name %d" % callback_id
					return result
				decoded.callbacks[callback_id] = callback_names.get_name(callback_id)
	result.definition = decoded
	return result
