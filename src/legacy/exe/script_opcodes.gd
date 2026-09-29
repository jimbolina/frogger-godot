class_name ScriptOpcodes
extends RefCounted
## The entity script instruction set: each opcode's name and argument count.
##
## Entity scripts (moving cars, sinking turtles, balloons...) are compiled into
## the executable as lists of 32-bit words: an opcode followed by its
## arguments. The list is FrogLord's [code]FroggerScriptCommandType[/code];
## the argument counts agree with [code]Script_command_lengths[/code] in the
## released original source ([code]scripter.c[/code], which counts the opcode
## word too). STOP, RESTART and END finish a script.

## Opcode names in opcode order.
const NAMES: PackedStringArray = [
	"WAIT_UNTIL_TIMER", "WAIT_UNTIL_ACTION_FINISHED", "WAIT_UNTIL_PATH_END", "SET_ACTION", "PLAY_SOUND",
	"RESTART", "END", "SET_TIMER", "DEVIATE", "WAIT_DEVIATED", "PLAY_RNDSOUND", "SETLOOP", "ENDLOOP",
	"SCRIPT_IF", "BREAKLOOP_IF_TIMER", "PAUSE_ENTITY_ON_PATH", "UNPAUSE_ENTITY_ON_PATH", "ROTATE",
	"WAIT_UNTIL_ROTATED", "HOME_IN_ON_FROG", "RETURN_GOSUB_IF", "EJECT_FROG", "CHOOSE_RND_CHECKPOINT",
	"APPEAR_ENTITY", "DISAPPEAR_ENTITY", "START_SCRIPT", "AWARD_FROG_POINTS", "AWARD_FROG_LIVES",
	"AWARD_FROG_TIME", "STOP_ROTATE", "STOP_DEVIATE", "PREPARE_REGISTERS", "CLEAR_DEVIATE", "RETURN_DEVIATE",
	"REGISTER_CALLBACK", "SET_ENTITY_TYPE", "PLAY_SOUND_DISTANCE", "PLAY_MOVING_SOUND", "STOP",
	"MUTATE_MESH_COLOR", "NO_COLL_CHECKPOINT", "COLL_CHECKPOINT", "KILL_SAFE_FROG", "CHANGE_ENTITY_ANIM",
	"CREATE_3D_SPRITE", "PITCH_BEND_MOVING_SOUND", "POP", "NO_COLLISION", "COLLISION",
]

## Argument count of each opcode (not counting the opcode word).
const ARGUMENT_COUNTS: PackedInt32Array = [
	2, 0, 0, 1, 1, 0, 0, 2, 5, 0, 2, 0, 0, 4, 2, 0, 0, 4, 0, 3, 1, 3, 0, 0, 0, 1, 1, 1, 1, 0, 0, 2, 0, 3,
	4, 1, 5, 4, 0, 0, 0, 0, 2, 1, 1, 6, 0, 0, 0,
]

## Opcode of RESTART.
const RESTART: int = 5
## Opcode of END.
const END: int = 6
## Opcode of STOP.
const STOP: int = 38


## Number of opcodes.
static func count() -> int:
	return NAMES.size()


## True if [param opcode] is a known opcode.
static func is_valid(opcode: int) -> bool:
	return opcode >= 0 and opcode < NAMES.size()


## The name of [param opcode], or "" if unknown.
static func name_of(opcode: int) -> String:
	return NAMES[opcode] if is_valid(opcode) else ""


## Argument count of [param opcode] (0 if unknown).
static func argument_count(opcode: int) -> int:
	return ARGUMENT_COUNTS[opcode] if is_valid(opcode) else 0


## True if [param opcode] ends a script.
static func is_final(opcode: int) -> bool:
	return opcode == STOP or opcode == RESTART or opcode == END
