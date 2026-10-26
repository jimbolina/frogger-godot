class_name EntityScriptDefinition
extends RefCounted
## Detached, named instruction closure and immutable register payload.

const WIDTHS: Dictionary[int, int] = {0: 3, 1: 1, 2: 1, 3: 2, 4: 2, 5: 1, 6: 1, 7: 3, 8: 6, 9: 1, 10: 3, 11: 1, 12: 1, 13: 5, 14: 3, 15: 1, 16: 1, 20: 2, 30: 1, 31: 3, 32: 1, 34: 5, 35: 2, 36: 6, 37: 5, 38: 1, 44: 2}
const SUPPORTED_NAMES: PackedStringArray = ["SCRIPT_ORG_SNAKE", "SCRIPT_ORG_CROCODILE", "SCRIPT_TURTLE", "SCRIPT_TURTLE_NO_DIVE", "SCRIPT_LOG_SPLASH", "SCRIPT_ORG_CAR_BLUE", "SCRIPT_ORG_CAR_PURPLE", "SCRIPT_ORG_LORRY", "SCRIPT_ORG_TRUCK", "SCRIPT_ORG_BULL_DOZER", "SCRIPT_ORG_CAR_BLUE_SFX", "SCRIPT_ORG_CAR_PURPLE_SFX", "SCRIPT_ORG_LORRY_SFX", "SCRIPT_ORG_TRUCK_SFX", "SCRIPT_ORG_BULL_DOZER_SFX", "SCRIPT_ORG_ROAD_NOISE", "SCRIPT_ORG_WATER_NOISE"]
const CALLBACK_NAMES: PackedStringArray = ["SCRIPT_CB_FROG_TRAFFIC_SPLAT", "SCRIPT_CB_LOG_SPLASH", "SCRIPT_CB_DIVE_COLOUR_CHANGE", "SCRIPT_CB_HIT_TURTLE"]

enum OperandMode { LITERAL, REGISTER }

var root_id: int = -1
var programs: Dictionary[int, PackedInt32Array] = {}
var names: Dictionary[int, String] = {}
var callbacks: Dictionary[int, String] = {}
var payload_offset: int = 0
var payload_registers: PackedInt32Array = PackedInt32Array()

## Copies all supplied facts; no decoded executable objects are retained.
func copy() -> EntityScriptDefinition:
	var result := EntityScriptDefinition.new()
	result.root_id = root_id
	result.names.assign(names)
	result.callbacks.assign(callbacks)
	result.payload_offset = payload_offset
	result.payload_registers = payload_registers.duplicate()
	for id: int in programs:
		result.programs[id] = programs[id].duplicate()
	return result

## Validates the bounded opcode/operand closure before execution.
func validate(action_lengths: PackedInt32Array, form_id: int, has_path: bool) -> String:
	if not programs.has(root_id):
		return "Missing root script"
	if payload_registers.size() > 6:
		return "Script payload exceeds six registers"
	for id: int in programs:
		if not names.has(id) or not SUPPORTED_NAMES.has(names[id]):
			return "Unsupported script name at %d" % id
		var words: PackedInt32Array = programs[id]
		var cursor: int = 0
		var loop_open: bool = false
		var last_opcode: int = -1
		if words.is_empty():
			return "Empty script program"
		while cursor < words.size():
			var opcode: int = words[cursor]
			last_opcode = opcode
			if not WIDTHS.has(opcode) or cursor + WIDTHS[opcode] > words.size():
				return "Unsupported or truncated script instruction %d at %d" % [opcode, cursor]
			var a: PackedInt32Array = words.slice(cursor + 1, cursor + WIDTHS[opcode])
			match opcode:
				0, 7, 14:
					if not _operand(a[0], a[1]):
						return "Invalid timer register operand"
					if opcode == 14 and not loop_open:
						return "Timer break requires an enclosing loop"
				1:
					if action_lengths.is_empty():
						return "Animation wait requires an animated entity"
				2, 15, 16:
					if not has_path:
						return "Path instruction requires a path"
				10:
					if (a[1] & 65535) == 0:
						return "Random sound divisor narrows to zero"
				20:
					if a[0] not in [0, 1, 2, 3, 4, 5, 7, 8, 9]:
						return "Unsupported return condition"
				3:
					if a[0] < 0 or a[0] >= action_lengths.size() or action_lengths[a[0]] <= 0:
						return "Invalid entity animation action"
				8:
					if a[0] != 0 or a[1] != 1 or not has_path:
						return "Only immediate path Y deviation is supported"
				11:
					if loop_open:
						return "Nested script loop"
					loop_open = true
				12:
					if not loop_open:
						return "ENDLOOP without SETLOOP"
					loop_open = false
				13:
					if a[0] not in [0, 1] or a[1] < 0 or a[1] > 9 or not programs.has(a[2]) or (a[1] == 6 and a[3] <= 0) or (a[1] == 8 and not has_path):
						return "Unsupported script branch"
				31:
					if a[0] != payload_offset or a[1] != payload_registers.size() or not ((a[0] == 12 and a[1] == 3) or (a[0] == 32 and a[1] == 2)):
						return "Unsupported register payload"
				34:
					if a[0] < 0 or a[0] > 1 or not callbacks.has(a[1]) or not CALLBACK_NAMES.has(callbacks[a[1]]) or a[2] not in [0, 7] or a[3] not in [0, 1]:
						return "Unsupported named script callback"
					if callbacks[a[1]] == "SCRIPT_CB_DIVE_COLOUR_CHANGE" and not has_path:
						return "Static dive colour callback is unsupported"
				35:
					if a[0] != 0:
						return "Unsupported script entity type"
				36:
					if not _operand(a[0], a[1]) or not _operand(a[0], a[2]) or a[3] not in [0, 1, 2]:
						return "Invalid distance sound operands"
				37:
					if not _operand(a[1], a[2]) or not _operand(a[1], a[3]):
						return "Invalid moving sound operands"
				44:
					if form_id not in [19, 20, 21] or a[0] != 0:
						return "Unsupported splash sprite operands or form"
			cursor += WIDTHS[opcode]
		if loop_open:
			return "Unclosed script loop"
		if last_opcode not in [5, 6, 38]:
			return "Script requires a supported terminal instruction"
	return ""

func _operand(mode: int, value: int) -> bool:
	return mode == OperandMode.LITERAL or (mode == OperandMode.REGISTER and value >= 0 and value < payload_registers.size())
