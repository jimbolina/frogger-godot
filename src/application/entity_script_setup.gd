class_name EntityScriptSetup
extends RefCounted
## Resolves supplied executable programs and FrogLord callback names.

const CALLBACK_KINDS: Dictionary[String, EntityScriptDefinition.CallbackKind] = {
	"SCRIPT_CB_FROG_TRAFFIC_SPLAT": EntityScriptDefinition.CallbackKind.FROG_TRAFFIC_SPLAT,
	"SCRIPT_CB_LOG_SPLASH": EntityScriptDefinition.CallbackKind.LOG_SPLASH,
	"SCRIPT_CB_HIT_TURTLE": EntityScriptDefinition.CallbackKind.HIT_TURTLE,
	"SCRIPT_CB_SWP_OIL_DRUM": EntityScriptDefinition.CallbackKind.SWP_OIL_DRUM,
	"SCRIPT_CB_SWP_PALLET": EntityScriptDefinition.CallbackKind.SWP_PALLET,
	"SCRIPT_CB_SWP_SUNKCAR": EntityScriptDefinition.CallbackKind.SWP_SUNKCAR,
	"SCRIPT_CB_SWP_STAT_PIPE": EntityScriptDefinition.CallbackKind.SWP_STAT_PIPE,
	"SCRIPT_CB_SWP_STAT_PIPE_BIG_STR": EntityScriptDefinition.CallbackKind.SWP_STAT_PIPE_BIG_STR,
	"SCRIPT_CB_SKY_BIRD1_CALL": EntityScriptDefinition.CallbackKind.SKY_BIRD1_CALL,
	"SCRIPT_CB_SKY_BIRD2_CALL": EntityScriptDefinition.CallbackKind.SKY_BIRD2_CALL,
	"SCRIPT_CB_SKY_BIRD3_CALL": EntityScriptDefinition.CallbackKind.SKY_BIRD3_CALL,
	"SCRIPT_CB_SKY_BIRD4_CALL": EntityScriptDefinition.CallbackKind.SKY_BIRD4_CALL,
	"SCRIPT_CB_SKY_FROG_HELICOPTER": EntityScriptDefinition.CallbackKind.SKY_FROG_HELICOPTER,
	"SCRIPT_CB_SUB_LILLY_PAD": EntityScriptDefinition.CallbackKind.SUB_LILLY_PAD,
	"SCRIPT_CB_JUN_HIPPO_HIT": EntityScriptDefinition.CallbackKind.JUN_HIPPO_HIT,
	"SCRIPT_CB_SWP_RACCOON": EntityScriptDefinition.CallbackKind.SWP_RACCOON,
	"SCRIPT_CB_SWP_PELICAN_CALL": EntityScriptDefinition.CallbackKind.SWP_PELICAN_CALL,
	"SCRIPT_CB_SKY_HOMING_BIRD": EntityScriptDefinition.CallbackKind.SKY_HOMING_BIRD,
	"SCRIPT_CB_SKY_BALLOON": EntityScriptDefinition.CallbackKind.SKY_BALLOON,
	"SCRIPT_CB_DIVE_COLOUR_CHANGE": EntityScriptDefinition.CallbackKind.DIVE_COLOUR_CHANGE,
	"SCRIPT_CB_JUN_PIRANAHA": EntityScriptDefinition.CallbackKind.JUN_PIRANAHA,
	"SCRIPT_CB_SWP_MUTANT_FISH": EntityScriptDefinition.CallbackKind.SWP_MUTANT_FISH,
	"SCRIPT_CB_JUN_HIPPO_DIVE": EntityScriptDefinition.CallbackKind.JUN_HIPPO_DIVE,
	"SCRIPT_CB_VOL_MECHANISM": EntityScriptDefinition.CallbackKind.VOL_MECHANISM,
	"SCRIPT_CB_SKY_HELIUM_BALLOON": EntityScriptDefinition.CallbackKind.SKY_HELIUM_BALLOON,
}

var error: String = ""
var definition: EntityScriptDefinition = null

## Copies the reachable closure, turtle creation replacement and frozen MOVING turtle zero-fill.
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
	var register_payload: PackedByteArray = payload
	if behavior.kind == EntityBehavior.Kind.PATH_FOLLOWER and not behavior.tongueable and names.get_name(root_id) == "SCRIPT_TURTLE" and payload.size() >= 12:
		register_payload = payload.slice(0, 12)
		register_payload.resize(24)
	var callback_names: NameBank = names.get_sub_bank("CallbackNames")
	while not roots.is_empty():
		var id: int = roots.pop_back()
		if decoded.programs.has(id):
			continue
		var program: EntityScript = table.get_script_by_id(id)
		if program == null or program.name.is_empty() or not names.has_name(id) or names.get_name(id) != program.name:
			result.error = "Unsupported supplied script id/name %d" % id
			return result
		decoded.programs[id] = program.words()
		decoded.names[id] = program.name
		var word_offset: int = 0
		for command: EntityScript.Command in program.commands:
			var source_address: int = program.pointer + word_offset * 4
			word_offset += command.arguments.size() + 1
			if not EntityScriptDefinition.WIDTHS.has(command.opcode):
				result.error = "Unsupported instruction %d in %s" % [command.opcode, program.name]
				return result
			if command.arguments.size() + 1 != EntityScriptDefinition.WIDTHS[command.opcode]:
				result.error = "Invalid instruction width in %s" % program.name
				return result
			if command.opcode == 31:
				var offset: int = command.arguments[0]
				var count: int = command.arguments[1]
				if not ((offset == 12 and count == 3) or (offset == 32 and count in [2, 6])) or register_payload.size() < offset + count * 4:
					result.error = "Unsupported or truncated register payload in %s at 0x%08x" % [program.name, source_address]
					return result
				if not decoded.payload_registers.is_empty() and (decoded.payload_offset != offset or decoded.payload_registers.size() != count):
					result.error = "Conflicting register payloads in %s at 0x%08x" % [program.name, source_address]
					return result
				if decoded.payload_registers.is_empty():
					decoded.payload_offset = offset
					for index: int in count:
						decoded.payload_registers.append(register_payload.decode_s32(offset + index * 4))
			if command.opcode == 13:
				roots.append(command.arguments[2])
			elif command.opcode == 25:
				roots.append(command.arguments[0])
			elif command.opcode == 34:
				var callback_id: int = command.arguments[1]
				if callback_names == null or not callback_names.has_name(callback_id) or not CALLBACK_KINDS.has(callback_names.get_name(callback_id)):
					result.error = "Unsupported supplied callback name %d in %s at 0x%08x" % [callback_id, program.name, source_address]
					return result
				decoded.callbacks[callback_id] = CALLBACK_KINDS[callback_names.get_name(callback_id)]
				if decoded.callbacks[callback_id] == EntityScriptDefinition.CallbackKind.SKY_HELIUM_BALLOON:
					var target: int = names.index_of("SCRIPT_SKY_HELIUM_BALLOON_RISING")
					decoded.callback_programs[callback_id] = target
					roots.append(target)
	result.definition = decoded
	return result
