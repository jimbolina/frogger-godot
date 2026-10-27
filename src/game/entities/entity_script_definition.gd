class_name EntityScriptDefinition
extends RefCounted
## Detached, named instruction closure and immutable register payload.

const WIDTHS: Dictionary[int, int] = {0: 3, 1: 1, 2: 1, 3: 2, 4: 2, 5: 1, 6: 1, 7: 3, 8: 6, 9: 1, 10: 3, 11: 1, 12: 1, 13: 5, 14: 3, 15: 1, 16: 1, 17: 5, 18: 1, 19: 4, 20: 2, 21: 4, 22: 1, 23: 1, 24: 1, 25: 2, 26: 2, 27: 2, 28: 2, 29: 1, 30: 1, 31: 3, 32: 1, 33: 4, 34: 5, 35: 2, 36: 6, 37: 5, 38: 1, 39: 1, 40: 1, 41: 1, 42: 3, 43: 2, 44: 2, 45: 7, 46: 1, 47: 1, 48: 1}
enum CallbackKind {
	FROG_TRAFFIC_SPLAT,
	LOG_SPLASH,
	HIT_TURTLE,
	SWP_OIL_DRUM,
	SWP_PALLET,
	SWP_SUNKCAR,
	SWP_STAT_PIPE,
	SWP_STAT_PIPE_BIG_STR,
	SKY_BIRD1_CALL,
	SKY_BIRD2_CALL,
	SKY_BIRD3_CALL,
	SKY_BIRD4_CALL,
	SKY_FROG_HELICOPTER,
	SUB_LILLY_PAD,
	JUN_HIPPO_HIT,
	SWP_RACCOON,
	SWP_PELICAN_CALL,
	SKY_HOMING_BIRD,
	SKY_BALLOON,
	DIVE_COLOUR_CHANGE,
	JUN_PIRANAHA,
	SWP_MUTANT_FISH,
	JUN_HIPPO_DIVE,
	VOL_MECHANISM,
	SKY_HELIUM_BALLOON,
}

enum OperandMode { LITERAL, REGISTER }

var root_id: int = -1
var programs: Dictionary[int, PackedInt32Array] = {}
var names: Dictionary[int, String] = {}
var callbacks: Dictionary[int, CallbackKind] = {}
var callback_programs: Dictionary[int, int] = {}
var payload_offset: int = 0
var payload_registers: PackedInt32Array = PackedInt32Array()

## Copies all supplied facts; no decoded executable objects are retained.
func copy() -> EntityScriptDefinition:
	var result := EntityScriptDefinition.new()
	result.root_id = root_id
	result.names.assign(names)
	result.callbacks.assign(callbacks)
	result.callback_programs.assign(callback_programs)
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
		if not names.has(id) or names[id].is_empty():
			return "Missing script name at %d" % id
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
				21:
					if not _operand(a[0], a[1]) or not _operand(a[0], a[2]):
						return "Invalid ejection operands"
				45:
					for operand: int in range(1, 5 if a[0] == 1 else 6):
						if not _operand(a[0], a[operand]):
							return "Invalid pitch-bend operands"
				42:
					if a[0] < 0 or a[0] >= FrogAnimationCatalog.NAMES.size():
						return "Invalid script frog death animation"
				19:
					if not _operand(a[0], a[1]) or not _operand(a[0], a[2]):
						return "Invalid homing register operands"
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
				25:
					if not programs.has(a[0]):
						return "Missing START_SCRIPT restart target"
				43:
					var action: int = PlatformMath.s16(a[0])
					if not action_lengths.is_empty() and (action < 0 or action >= action_lengths.size() or action_lengths[action] <= 0):
						return "Invalid changed animation action"
				3:
					if a[0] < 0 or a[0] >= action_lengths.size() or action_lengths[a[0]] <= 0:
						return "Invalid entity animation action"
				8:
					if a[1] < 0 or a[1] > 5 or not _operand(a[0], a[2]) or not _operand(a[0], a[3]):
						return "Invalid deviation operands"
				17:
					if a[0] < 0 or a[0] > 2:
						return "Invalid rotation axis"
				33:
					if a[1] < 0 or a[1] > 5 or not _operand(a[0], a[2]) or (a[0] == 1 and a[1] == 3):
						return "Invalid or unsafe return deviation operands"
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
					if a[0] < 0 or a[0] > 1 or not callbacks.has(a[1]) or not CallbackKind.values().has(callbacks[a[1]]) or a[2] not in [0, 7] or a[3] not in [0, 1]:
						return "Unsupported named script callback"
					if callbacks[a[1]] == CallbackKind.SKY_HELIUM_BALLOON and (not callback_programs.has(a[1]) or not programs.has(callback_programs[a[1]])):
						return "Missing helium balloon callback program"
					if callbacks[a[1]] in [CallbackKind.JUN_PIRANAHA, CallbackKind.SWP_MUTANT_FISH, CallbackKind.JUN_HIPPO_DIVE] and not has_path:
						return "Path colour callback requires a path"
				35:
					if a[0] not in [0, 1]:
						return "Unsupported script entity type"
					if a[0] == 1 and has_path:
						return "Matrix script type requires an authored matrix payload"
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
