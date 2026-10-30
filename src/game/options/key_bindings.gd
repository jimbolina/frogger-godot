class_name KeyBindings
extends RefCounted
## Retail page 25's four controller records: a device, a valid flag and nine key scancodes each.
##
## Records are players 1 to 4. Keys are DirectInput scancodes (see [KeyScancodes]) in
## [enum Action] order, which is retail's slot order. The device is 0 for none, 1 for the
## keyboard and 2 upwards for joysticks. The valid flag is retail's own stored flag: the
## controller page sets it from whether a record's nine keys are distinct, and leaves the
## page only when every record is valid.
##
## Serialised layout ([method to_array], [member ProgressStore.key_bindings]): 44 integers,
## four records of [constant RECORD_STRIDE] values in record order, each
## [code]device, valid, key0 .. key8[/code]. An empty array means the shipped defaults.

enum Action { LEFT, RIGHT, UP, DOWN, SUPERJUMP, TONGUE, CROAK, CAMERA_CLOCKWISE, CAMERA_ANTICLOCKWISE }

## Number of controller records.
const RECORD_COUNT: int = 4
## Keys per record, one per [enum Action].
const ACTION_COUNT: int = 9
## Integers per serialised record: device, valid and the nine keys.
const RECORD_STRIDE: int = 2 + ACTION_COUNT
## Length of a serialised set of records.
const SERIALISED_LENGTH: int = RECORD_COUNT * RECORD_STRIDE
## No device.
const DEVICE_NONE: int = 0
## The keyboard.
const DEVICE_KEYBOARD: int = 1
## The first joystick; joystick n is this plus n.
const DEVICE_FIRST_JOYSTICK: int = 2
## Retail action names in slot order (the FrogLord/C input names).
const ACTION_NAMES: PackedStringArray = [
	"LEFT", "RIGHT", "UP", "DOWN", "SUPERJUMP", "TONGUE", "CROAK", "CAMERA_CLOCKWISE", "CAMERA_ANTICLOCKWISE",
]
## The shipped records' keys, nine per record in record order (retail .data at VA 0x0047D070).
## Every shipped record is a valid keyboard.
const DEFAULT_KEYS: PackedInt32Array = [
	0xCB, 0xCD, 0xC8, 0xD0, 0x1C, 0x9D, 0x36, 0x28, 0x27,
	0x12, 0x13, 0x03, 0x11, 0x02, 0x14, 0x0F, 0x04, 0x05,
	0x31, 0x32, 0x22, 0x30, 0x21, 0x33, 0x39, 0x23, 0x24,
	0x18, 0x19, 0x09, 0x17, 0x08, 0x1A, 0x15, 0x0A, 0x0B,
]

## Why [method from_array] fell back to the defaults, or "".
var error: String = ""

var _values: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_values.resize(SERIALISED_LENGTH)
	for record: int in RECORD_COUNT:
		_values[record * RECORD_STRIDE] = DEVICE_KEYBOARD
		_values[record * RECORD_STRIDE + 1] = 1
		for action: int in ACTION_COUNT:
			_values[record * RECORD_STRIDE + 2 + action] = DEFAULT_KEYS[record * ACTION_COUNT + action]


## The shipped defaults.
static func create_default() -> KeyBindings:
	return KeyBindings.new()


## Records from [param values]; an empty array gives the defaults. A malformed array gives
## the defaults and sets [member error] (see [method validate_array]).
static func from_array(values: PackedInt32Array) -> KeyBindings:
	var bindings := KeyBindings.new()
	if values.is_empty():
		return bindings
	var problem: String = validate_array(values)
	if not problem.is_empty():
		bindings.error = "key bindings %s; using defaults" % problem
		return bindings
	bindings._values = values.duplicate()
	return bindings


## "" when [param values] is a well-formed serialised set, otherwise the first problem: the
## length, a negative device, a valid flag other than 0 or 1, an unbindable key, a key bound
## in two records, or a repeated key in a record marked valid. A repeated key in an invalid
## record is a state the controller page itself handles.
static func validate_array(values: PackedInt32Array) -> String:
	if values.size() != SERIALISED_LENGTH:
		return "have %d values, expected %d" % [values.size(), SERIALISED_LENGTH]
	var owner: Dictionary = {}
	for record: int in RECORD_COUNT:
		var base: int = record * RECORD_STRIDE
		if values[base] < DEVICE_NONE:
			return "give record %d the negative device %d" % [record, values[base]]
		if values[base + 1] != 0 and values[base + 1] != 1:
			return "give record %d the valid flag %d" % [record, values[base + 1]]
		for action: int in ACTION_COUNT:
			var scancode: int = values[base + 2 + action]
			if not KeyScancodes.is_bindable(scancode):
				return "bind record %d %s to the unnamed scancode %d" % [record, ACTION_NAMES[action], scancode]
			if owner.has(scancode):
				var first: int = owner[scancode]
				if first != record:
					return "bind scancode %d in records %d and %d" % [scancode, first, record]
				if values[base + 1] == 1:
					return "repeat scancode %d in the valid record %d" % [scancode, record]
			owner[scancode] = record
	return ""


## The serialised layout described in the class notes.
func to_array() -> PackedInt32Array:
	return _values.duplicate()


## An independent copy.
func copy() -> KeyBindings:
	var other := KeyBindings.new()
	other._values = _values.duplicate()
	other.error = error
	return other


## Record [param record]'s device.
func device(record: int) -> int:
	return _values[record * RECORD_STRIDE]


## Sets record [param record]'s device.
func set_device(record: int, value: int) -> void:
	_values[record * RECORD_STRIDE] = value


## Record [param record]'s stored valid flag.
func is_valid(record: int) -> bool:
	return _values[record * RECORD_STRIDE + 1] != 0


## Sets record [param record]'s stored valid flag.
func set_valid(record: int, value: bool) -> void:
	_values[record * RECORD_STRIDE + 1] = 1 if value else 0


## The scancode record [param record] binds to [param action].
func key(record: int, action: int) -> int:
	return _values[record * RECORD_STRIDE + 2 + action]


## Binds [param scancode] to [param action] in record [param record].
func set_key(record: int, action: int, scancode: int) -> void:
	_values[record * RECORD_STRIDE + 2 + action] = scancode


## Record [param record]'s nine keys in action order.
func keys(record: int) -> PackedInt32Array:
	var base: int = record * RECORD_STRIDE + 2
	return _values.slice(base, base + ACTION_COUNT)


## Replaces record [param record]'s nine keys.
func set_keys(record: int, scancodes: PackedInt32Array) -> void:
	for action: int in ACTION_COUNT:
		set_key(record, action, scancodes[action])


## True when record [param record]'s nine keys are distinct (Page25_RecordKeysUnique).
func keys_unique(record: int) -> bool:
	var seen: Dictionary = {}
	for action: int in ACTION_COUNT:
		var scancode: int = key(record, action)
		if seen.has(scancode):
			return false
		seen[scancode] = true
	return true


## True when every record's valid flag is set (Page25_EveryRecordValid).
func every_record_valid() -> bool:
	for record: int in RECORD_COUNT:
		if not is_valid(record):
			return false
	return true


## True when [param scancode] is bound in another record, or in [param record] at a slot below
## [param action] (Page25_KeyAlreadyBound, 0x0043AC60).
func key_already_bound(record: int, action: int, scancode: int) -> bool:
	for other: int in RECORD_COUNT:
		var bound: int = action if other == record else ACTION_COUNT
		for slot: int in bound:
			if key(other, slot) == scancode:
				return true
	return false


## The [enum Action] record [param record] binds to [param scancode], or -1.
func action_for(record: int, scancode: int) -> int:
	for action: int in ACTION_COUNT:
		if key(record, action) == scancode:
			return action
	return -1
