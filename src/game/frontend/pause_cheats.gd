class_name PauseCheats
extends RefCounted
## The retail PC pause-menu cheat dispatcher (exe 0x0042fda0, the twin of pause.c:843
## GameCheatModeCheck): four typed phrases, each with its own cursor, checked every MENU tick.
##
## The vendored pause.c:843-882 walks one joypad Sequence[] with -2/-3/-4 markers; that code is
## dead on the PC, where PSX_MASTER is off (PC/winsys.h:33) and the executable carries four
## DirectInput scancode lists (../froggy/engine/asset_pipeline/include/frogger_cheat_sequences.h,
## file offsets 0x77378, 0x773C8, 0x77430 and 0x774B8, terminator 0xFFFFFFFF). The port follows
## the executable (../froggy/engine/docs/evidence/m50_v3_exe_probe.txt leg H3): a gate records
## that a letter or Space went down since the last check, at any time and auto-repeat included;
## with the gate set, each sequence in [constant SEQUENCES] order tests only the key its cursor
## names against the keys down (held or pressed): down advances the cursor, and reaching the end
## fires the cheat and resets it; not down resets the cursor without re-testing the key as the
## first element. The gate clears only when the dispatcher runs, so a stale gate reaches the
## first menu tick, and the cursors persist across pauses and levels as process globals.
##
## Infinite lives and no-death-on-timeout are toggles; all zones (pause.c:933-965) and all levels
## (:983-998) rewrite the level-select flags through LevelProgress.

## The four cheats in retail's dispatch order.
enum Cheat { INFINITE_LIVES, ALL_ZONES, ALL_LEVELS, TIMEOUT_DEATHS }

## DIK_SPACE.
const SPACE: int = 0x39
## DIK_Q to DIK_P, the top letter row.
const LETTERS_TOP: PackedInt32Array = [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19]
## DIK_A to DIK_L, the home letter row.
const LETTERS_HOME: PackedInt32Array = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26]
## DIK_Z to DIK_M, the bottom letter row.
const LETTERS_BOTTOM: PackedInt32Array = [0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32]
## "NO MORE ROAD SPLATS": GameCheatModeToggleInfiniteLives (pause.c:900-915).
const SEQUENCE_INFINITE_LIVES: PackedInt32Array = [
	0x31, 0x18, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x13, 0x18, 0x1E, 0x20, 0x39, 0x1F, 0x19, 0x26,
	0x1E, 0x14, 0x1F,
]
## "SHOW ME MORE ZONES PLEASE": GameCheatModeUnlockAllZones (pause.c:933-965).
const SEQUENCE_ALL_ZONES: PackedInt32Array = [
	0x1F, 0x23, 0x18, 0x11, 0x39, 0x32, 0x12, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x2C, 0x18, 0x31,
	0x12, 0x1F, 0x39, 0x19, 0x26, 0x12, 0x1E, 0x1F, 0x12,
]
## "WAY TOO HARD FOR THE LIKES OF ME": GameCheatModeUnlockAllLevels (pause.c:983-998).
const SEQUENCE_ALL_LEVELS: PackedInt32Array = [
	0x11, 0x1E, 0x15, 0x39, 0x14, 0x18, 0x18, 0x39, 0x23, 0x1E, 0x13, 0x20, 0x39, 0x21, 0x18, 0x13,
	0x39, 0x14, 0x23, 0x12, 0x39, 0x26, 0x17, 0x25, 0x12, 0x1F, 0x39, 0x18, 0x21, 0x39, 0x32, 0x12,
]
## "NO MORE TIMEOUT DEATHS PLEASE": the PC-only death-on-timeout toggle (exe 0x00430040).
const SEQUENCE_TIMEOUT_DEATHS: PackedInt32Array = [
	0x31, 0x18, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x14, 0x17, 0x32, 0x12, 0x18, 0x16, 0x14, 0x39,
	0x20, 0x12, 0x1E, 0x14, 0x23, 0x1F, 0x39, 0x19, 0x26, 0x12, 0x1E, 0x1F, 0x12,
]
## The sequences by [enum Cheat]; each list's length stands for retail's terminator.
const SEQUENCES: Array[PackedInt32Array] = [
	SEQUENCE_INFINITE_LIVES, SEQUENCE_ALL_ZONES, SEQUENCE_ALL_LEVELS, SEQUENCE_TIMEOUT_DEATHS,
]

## The next element each sequence waits for (ds:0x478530-0x47853C).
var cursors: PackedInt32Array = [0, 0, 0, 0]
## True when a letter or Space went down since the last [method check] (ds:0x478370).
var gate: bool = false


## True for the keys whose WM_KEYDOWN sets the gate: the letters A-Z and Space.
static func gates(scancode: int) -> bool:
	return (scancode == SPACE or LETTERS_TOP.has(scancode) or LETTERS_HOME.has(scancode)
		or LETTERS_BOTTOM.has(scancode))


## Records a gating key-down (the window procedure's WM_KEYDOWN for a letter or Space).
func note_key_down() -> void:
	gate = true


## One dispatcher run with the scancodes [param down] held or pressed this tick: without the
## gate nothing happens; otherwise the gate clears and each sequence advances or resets. Returns
## the cheats fired, in dispatch order.
func check(down: PackedInt32Array) -> Array[int]:
	var fired: Array[int] = []
	if not gate:
		return fired
	gate = false
	for cheat: int in SEQUENCES.size():
		var sequence: PackedInt32Array = SEQUENCES[cheat]
		if not down.has(sequence[cursors[cheat]]):
			cursors[cheat] = 0
			continue
		cursors[cheat] += 1
		if cursors[cheat] == sequence.size():
			fired.append(cheat)
			cursors[cheat] = 0
	return fired


## Clears the gate and every cursor, as a fresh process starts.
func reset() -> void:
	gate = false
	cursors.fill(0)
