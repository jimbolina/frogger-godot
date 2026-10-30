class_name KeyScancodes
extends RefCounted
## Retail PC key identities: DirectInput scancodes, the bindable set and Godot physical keys.
##
## Retail page 25 and its saved controller records name keys by DirectInput scancode.
## A scancode is bindable when retail's key-name table has a row for it; 83 of the 256
## rows are filled. The port keeps scancodes in its bindings and translates a Godot
## physical keycode and key location to a scancode at the input edge. Modifier keys need
## the location to tell left from right; an unspecified location reads as the left key.
## Keys this table does not list translate to [constant UNKNOWN], which is not bindable.
## English names are the retail spellings; other languages belong to the executable's
## localised key-name rows.

## The scancode given to keys with no retail identity.
const UNKNOWN: int = 0
## DIK_ESCAPE.
const ESCAPE: int = 0x01
## DIK_RETURN.
const RETURN: int = 0x1C
## DIK_F1.
const F1: int = 0x3B
## DIK_F2.
const F2: int = 0x3C
## DIK_F3.
const F3: int = 0x3D
## DIK_LEFT.
const LEFT: int = 0xCB
## DIK_RIGHT.
const RIGHT: int = 0xCD
## Number of scancodes retail can bind.
const BINDABLE_COUNT: int = 83

const _U: int = KEY_LOCATION_UNSPECIFIED
const _L: int = KEY_LOCATION_LEFT
const _R: int = KEY_LOCATION_RIGHT
const _TABLE: Dictionary = {
	0x01: [KEY_ESCAPE, _U, ""],
	0x02: [KEY_1, _U, "1"], 0x03: [KEY_2, _U, "2"], 0x04: [KEY_3, _U, "3"], 0x05: [KEY_4, _U, "4"],
	0x06: [KEY_5, _U, "5"], 0x07: [KEY_6, _U, "6"], 0x08: [KEY_7, _U, "7"], 0x09: [KEY_8, _U, "8"],
	0x0A: [KEY_9, _U, "9"], 0x0B: [KEY_0, _U, "0"], 0x0C: [KEY_MINUS, _U, "-"], 0x0D: [KEY_EQUAL, _U, "="],
	0x0E: [KEY_BACKSPACE, _U, "BkSpc"], 0x0F: [KEY_TAB, _U, "Tab"],
	0x10: [KEY_Q, _U, "Q"], 0x11: [KEY_W, _U, "W"], 0x12: [KEY_E, _U, "E"], 0x13: [KEY_R, _U, "R"],
	0x14: [KEY_T, _U, "T"], 0x15: [KEY_Y, _U, "Y"], 0x16: [KEY_U, _U, "U"], 0x17: [KEY_I, _U, "I"],
	0x18: [KEY_O, _U, "O"], 0x19: [KEY_P, _U, "P"], 0x1A: [KEY_BRACKETLEFT, _U, "["],
	0x1B: [KEY_BRACKETRIGHT, _U, "]"], 0x1C: [KEY_ENTER, _U, "Return"], 0x1D: [KEY_CTRL, _L, "L-Ctrl"],
	0x1E: [KEY_A, _U, "A"], 0x1F: [KEY_S, _U, "S"], 0x20: [KEY_D, _U, "D"], 0x21: [KEY_F, _U, "F"],
	0x22: [KEY_G, _U, "G"], 0x23: [KEY_H, _U, "H"], 0x24: [KEY_J, _U, "J"], 0x25: [KEY_K, _U, "K"],
	0x26: [KEY_L, _U, "L"], 0x27: [KEY_SEMICOLON, _U, ";"], 0x28: [KEY_APOSTROPHE, _U, "'"],
	0x29: [KEY_QUOTELEFT, _U, "#"], 0x2A: [KEY_SHIFT, _L, "L-Shift"], 0x2B: [KEY_BACKSLASH, _U, "\\"],
	0x2C: [KEY_Z, _U, "Z"], 0x2D: [KEY_X, _U, "X"], 0x2E: [KEY_C, _U, "C"], 0x2F: [KEY_V, _U, "V"],
	0x30: [KEY_B, _U, "B"], 0x31: [KEY_N, _U, "N"], 0x32: [KEY_M, _U, "M"], 0x33: [KEY_COMMA, _U, ","],
	0x34: [KEY_PERIOD, _U, "."], 0x35: [KEY_SLASH, _U, "/"], 0x36: [KEY_SHIFT, _R, "R-Shift"],
	0x37: [KEY_KP_MULTIPLY, _U, "*"], 0x38: [KEY_ALT, _L, "L-Alt"], 0x39: [KEY_SPACE, _U, "Space"],
	0x3A: [KEY_CAPSLOCK, _U, ""],
	0x3B: [KEY_F1, _U, ""], 0x3C: [KEY_F2, _U, ""], 0x3D: [KEY_F3, _U, ""], 0x3E: [KEY_F4, _U, ""],
	0x3F: [KEY_F5, _U, ""], 0x40: [KEY_F6, _U, ""], 0x41: [KEY_F7, _U, ""], 0x42: [KEY_F8, _U, ""],
	0x43: [KEY_F9, _U, ""], 0x44: [KEY_F10, _U, ""], 0x45: [KEY_NUMLOCK, _U, ""], 0x46: [KEY_SCROLLLOCK, _U, ""],
	0x47: [KEY_KP_7, _U, "Numpad 7"], 0x48: [KEY_KP_8, _U, "Numpad 8"], 0x49: [KEY_KP_9, _U, "Numpad 9"],
	0x4A: [KEY_KP_SUBTRACT, _U, "Numpad -"], 0x4B: [KEY_KP_4, _U, "Numpad 4"], 0x4C: [KEY_KP_5, _U, "Numpad 5"],
	0x4D: [KEY_KP_6, _U, "Numpad 6"], 0x4E: [KEY_KP_ADD, _U, "Numpad +"], 0x4F: [KEY_KP_1, _U, "Numpad 1"],
	0x50: [KEY_KP_2, _U, "Numpad 2"], 0x51: [KEY_KP_3, _U, "Numpad 3"], 0x52: [KEY_KP_0, _U, "Numpad 0"],
	0x53: [KEY_KP_PERIOD, _U, "Numpad ."], 0x57: [KEY_F11, _U, ""], 0x58: [KEY_F12, _U, ""],
	0x9C: [KEY_KP_ENTER, _U, "Enter"], 0x9D: [KEY_CTRL, _R, "R-Ctrl"], 0xB5: [KEY_KP_DIVIDE, _U, "Numpad /"],
	0xB7: [KEY_PRINT, _U, ""], 0xB8: [KEY_ALT, _R, "R-Alt"], 0xC5: [KEY_PAUSE, _U, ""],
	0xC7: [KEY_HOME, _U, "Home"], 0xC8: [KEY_UP, _U, "Up"], 0xC9: [KEY_PAGEUP, _U, "PgUp"],
	0xCB: [KEY_LEFT, _U, "Left"], 0xCD: [KEY_RIGHT, _U, "Right"], 0xCF: [KEY_END, _U, "End"],
	0xD0: [KEY_DOWN, _U, "Down"], 0xD1: [KEY_PAGEDOWN, _U, "PgDown"], 0xD2: [KEY_INSERT, _U, "Ins"],
	0xD3: [KEY_DELETE, _U, "Del"], 0xDB: [KEY_META, _L, ""], 0xDC: [KEY_META, _R, ""], 0xDD: [KEY_MENU, _U, ""],
}
const _SIDED: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

static var _by_godot: Dictionary = {}


## True when retail can bind [param scancode] (its key-name row is filled).
static func is_bindable(scancode: int) -> bool:
	return not english_name(scancode).is_empty()


## Retail's English key name for [param scancode], or "" when it has none.
static func english_name(scancode: int) -> String:
	if not _TABLE.has(scancode):
		return ""
	var entry: Array = _TABLE[scancode]
	var name: String = entry[2]
	return name


## The Godot physical keycode for [param scancode], or KEY_NONE when it is not listed.
static func godot_key(scancode: int) -> int:
	if not _TABLE.has(scancode):
		return KEY_NONE
	var entry: Array = _TABLE[scancode]
	var key: int = entry[0]
	return key


## The Godot key location for [param scancode] (left/right for modifiers, else unspecified).
static func godot_location(scancode: int) -> int:
	if not _TABLE.has(scancode):
		return KEY_LOCATION_UNSPECIFIED
	var entry: Array = _TABLE[scancode]
	var location: int = entry[1]
	return location


## The scancode of a Godot physical [param key] at [param location], or [constant UNKNOWN].
static func from_godot(key: int, location: int = KEY_LOCATION_UNSPECIFIED) -> int:
	if _by_godot.is_empty():
		for scancode: int in _TABLE:
			_by_godot[Vector2i(godot_key(scancode), godot_location(scancode))] = scancode
	var side: int = KEY_LOCATION_UNSPECIFIED
	if _SIDED.has(key):
		side = KEY_LOCATION_RIGHT if location == KEY_LOCATION_RIGHT else KEY_LOCATION_LEFT
	var lookup := Vector2i(key, side)
	if not _by_godot.has(lookup):
		return UNKNOWN
	var scancode: int = _by_godot[lookup]
	return scancode


## Every scancode this table lists, ascending.
static func listed_scancodes() -> PackedInt32Array:
	var codes := PackedInt32Array()
	for scancode: int in _TABLE:
		codes.append(scancode)
	codes.sort()
	return codes


## The bindable scancodes, ascending.
static func bindable_scancodes() -> PackedInt32Array:
	var codes := PackedInt32Array()
	for scancode: int in listed_scancodes():
		if is_bindable(scancode):
			codes.append(scancode)
	return codes
