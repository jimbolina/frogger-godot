class_name ControlsPage
extends RefCounted
## Retail PC controller page (page 25: Startup 0x0043AF20, Update 0x0043C260) as a tick machine.
##
## Each [method step] takes the DirectInput scancodes newly pressed on that tick (see
## [KeyScancodes]) and runs one Update. [enum State] uses retail's ten sub-state numbers.
## The device chooser (CHOOSER) moves a device cursor with LEFT/RIGHT, commits it with
## RETURN, opens the key list with F3 when the keyboard is chosen, changes the record with
## F1/F2 (clamped to 0..3) and leaves through ESC only when every record is valid. The key
## list (KEY_LIST) starts a capture with F1 and goes back with ESC. The capture (CAPTURE)
## takes the lowest pressed scancode for each of the nine slots in turn, refuses keys with
## no retail name and keys bound to another record or an earlier slot of this record, and
## ESC restores all nine keys it started from. Slides and turns last [constant SLIDE_FRAMES]
## ticks per phase and read no keys. The page edits the [KeyBindings] it was given.
## After the exit slide the page is [method is_finished] and further steps do nothing.

## Page sub-states in retail order: 4 slides the page in, 5-8 slide between the chooser,
## key list and capture, 9 slides it out.
enum State { SEED, CHOOSER, KEY_LIST, CAPTURE, ENTER, TO_KEY_LIST, TO_CHOOSER, TO_CAPTURE, FROM_CAPTURE, EXIT }
## What a tick asks the presentation to do; [constant SOUND_NAMES] gives each one's sound.
enum EventKind { REFUSE_EXIT, REFUSE_UNNAMED, REFUSE_DUPLICATE, CURSOR, PAGE, ACCEPT, BACK, ENTER, EXIT }
## Device-chooser sub-states (retail helper A's numbers).
enum Chooser { ENTER = 0, IDLE = 1, SLIDE_RIGHT = 2, SLIDE_LEFT = 3, RECORD_TURN = 5 }
## Capture sub-states (retail helper C's numbers).
enum Capture { ENTER, WAIT, ADVANCE }

## Ticks in each slide phase (P25_SLIDE_FRAMES).
const SLIDE_FRAMES: int = 16
## [method shown] value for a blank key-name area.
const SHOWN_BLANK: int = -2
## [method shown] value for the one-character capture prompt.
const SHOWN_PROMPT: int = -1
## FrogLord sound names per [enum EventKind]; EXIT has none.
const SOUND_NAMES: PackedStringArray = [
	"GEN_FROG_CROAK", "GEN_FROG_CROAK", "GEN_FROG_CROAK", "GEN_FROG_HOP", "GEN_FROG_HOP_SUPER",
	"GEN_FROG_HIT_GROUND", "GEN_SLURP", "GEN_CLOCK_TICK", "",
]

var _bindings: KeyBindings = null
var _joysticks: int = 0
var _state: int = State.SEED
var _helper_a: int = 0
var _helper_b: int = 0
var _helper_c: int = 0
var _phase: int = 0
var _counter: int = 0
var _record: int = 0
var _cursor: int = 0
var _cursor_max: int = KeyBindings.DEVICE_KEYBOARD
var _action: int = 0
var _scratch: PackedInt32Array = PackedInt32Array()
var _shown: PackedInt32Array = PackedInt32Array()
var _finished: bool = false
var _events: Array[int] = []


## Opens the page on record 0 of [param edited] with [param joystick_count] attached joysticks.
func _init(edited: KeyBindings, joystick_count: int = 0) -> void:
	_bindings = edited
	_joysticks = joystick_count
	_cursor = _bindings.device(0)
	for device: int in range(KeyBindings.DEVICE_FIRST_JOYSTICK, KeyBindings.DEVICE_FIRST_JOYSTICK + joystick_count):
		if _device_free(0, device):
			_cursor_max = device
	_cursor = mini(_cursor, _cursor_max)
	_shown.resize(KeyBindings.ACTION_COUNT)
	_shown.fill(SHOWN_BLANK)


## The FrogLord sound name for [param kind], or "" when it plays none.
static func sound_name(kind: int) -> String:
	return SOUND_NAMES[kind]


## Runs one Update with [param pressed] newly pressed scancodes; returns that tick's events in order.
func step(pressed: PackedInt32Array) -> Array[int]:
	_events = []
	if _finished:
		return _events.duplicate()
	match _state:
		State.SEED:
			_state = State.ENTER
			_counter = 0
		State.CHOOSER:
			_update_chooser(pressed)
		State.KEY_LIST:
			_update_key_list(pressed)
		State.CAPTURE:
			_update_capture(pressed)
		State.ENTER:
			_counter += 1
			if _counter == SLIDE_FRAMES:
				_helper_a = Chooser.ENTER
				_counter = 0
				_state = State.CHOOSER
		State.TO_KEY_LIST, State.FROM_CAPTURE:
			if _transition():
				_helper_b = 0
				_state = State.KEY_LIST
		State.TO_CHOOSER:
			if _transition():
				_helper_a = Chooser.ENTER
				_state = State.CHOOSER
		State.TO_CAPTURE:
			if _transition():
				_helper_c = Capture.ENTER
				_state = State.CAPTURE
		_:
			_counter += 1
			if _counter >= SLIDE_FRAMES:
				_counter = 0
				_finished = true
				_events.append(EventKind.EXIT)
	return _events.duplicate()


## The bindings being edited.
func bindings() -> KeyBindings:
	return _bindings


## The current [enum State].
func state() -> int:
	return _state


## The chooser sub-state, a [enum Chooser] value.
func chooser_state() -> int:
	return _helper_a


## The key-list sub-state: 0 before its names are drawn, 1 waiting.
func key_list_state() -> int:
	return _helper_b


## The capture sub-state, a [enum Capture] value.
func capture_state() -> int:
	return _helper_c


## The slide phase, 0 or 1.
func phase() -> int:
	return _phase


## Ticks done in the current slide phase.
func counter() -> int:
	return _counter


## The record shown (player index 0..3).
func record() -> int:
	return _record


## The device cursor.
func device_cursor() -> int:
	return _cursor


## The highest device the cursor reaches.
func device_cursor_max() -> int:
	return _cursor_max


## The slot being captured.
func action() -> int:
	return _action


## True once the exit slide has finished.
func is_finished() -> bool:
	return _finished


## What key-name area [param slot] shows: a scancode, [constant SHOWN_PROMPT] or [constant SHOWN_BLANK].
func shown(slot: int) -> int:
	return _shown[slot]


## All nine [method shown] values.
func shown_values() -> PackedInt32Array:
	return _shown.duplicate()


func _transition() -> bool:
	_counter += 1
	if _phase == 0:
		if _counter == SLIDE_FRAMES:
			_phase = 1
			_counter = 0
		return false
	if _counter != SLIDE_FRAMES:
		return false
	_counter = 0
	_phase = 0
	return true


func _device_free(record_index: int, device: int) -> bool:
	if device < KeyBindings.DEVICE_FIRST_JOYSTICK:
		return true
	if device - KeyBindings.DEVICE_FIRST_JOYSTICK >= _joysticks:
		return false
	for other: int in KeyBindings.RECORD_COUNT:
		if other != record_index and _bindings.device(other) == device:
			return false
	return true


func _update_chooser(pressed: PackedInt32Array) -> void:
	match _helper_a:
		Chooser.ENTER:
			_helper_a = Chooser.IDLE
		Chooser.IDLE:
			_chooser_keys(pressed)
		Chooser.SLIDE_RIGHT, Chooser.SLIDE_LEFT:
			_counter += 1
			if _counter >= SLIDE_FRAMES:
				_counter = 0
				if not _device_free(_record, _cursor):
					_cursor += 1 if _helper_a == Chooser.SLIDE_RIGHT else -1
					return
				_helper_a = Chooser.IDLE
		_:
			_record_turn()


func _chooser_keys(pressed: PackedInt32Array) -> void:
	if pressed.has(KeyScancodes.ESCAPE):
		if _bindings.every_record_valid():
			_state = State.EXIT
			_phase = 0
			_counter = 0
			_events.append(EventKind.BACK)
			return
		_events.append(EventKind.REFUSE_EXIT)
	if pressed.has(KeyScancodes.RETURN):
		_bindings.set_device(_record, _cursor)
		_events.append(EventKind.ENTER)
		if _cursor == KeyBindings.DEVICE_KEYBOARD:
			_bindings.set_valid(_record, _bindings.keys_unique(_record))
	if pressed.has(KeyScancodes.F3) and _cursor == KeyBindings.DEVICE_KEYBOARD:
		_state = State.TO_KEY_LIST
		_events.append(EventKind.ENTER)
	if pressed.has(KeyScancodes.LEFT) and _cursor != 0:
		_cursor -= 1
		_events.append(EventKind.CURSOR)
		_counter = 0
		_helper_a = Chooser.SLIDE_LEFT
	if pressed.has(KeyScancodes.RIGHT) and _cursor < _cursor_max:
		_cursor += 1
		_events.append(EventKind.CURSOR)
		_counter = 0
		_helper_a = Chooser.SLIDE_RIGHT
	if pressed.has(KeyScancodes.F1) and _record != 0:
		_record -= 1
		_events.append(EventKind.PAGE)
		_helper_a = Chooser.RECORD_TURN
	if pressed.has(KeyScancodes.F2) and _record < KeyBindings.RECORD_COUNT - 1:
		_record += 1
		_events.append(EventKind.PAGE)
		_helper_a = Chooser.RECORD_TURN


func _record_turn() -> void:
	_counter += 1
	if _phase == 0:
		if _counter != SLIDE_FRAMES:
			return
		_counter = 0
		_phase = 1
		_cursor = _bindings.device(_record)
		if _cursor == KeyBindings.DEVICE_KEYBOARD:
			_bindings.set_valid(_record, _bindings.keys_unique(_record))
		if not _device_free(_record, _cursor):
			_cursor = KeyBindings.DEVICE_NONE
			_bindings.set_device(_record, KeyBindings.DEVICE_NONE)
		return
	if _counter != SLIDE_FRAMES:
		return
	_counter = 0
	_phase = 0
	_helper_a = Chooser.IDLE


func _update_key_list(pressed: PackedInt32Array) -> void:
	if _helper_b == 0:
		_shown = _bindings.keys(_record)
		_helper_b = 1
		return
	if pressed.has(KeyScancodes.ESCAPE):
		_state = State.TO_CHOOSER
		_phase = 0
		_counter = 0
		_shown.fill(SHOWN_BLANK)
		_events.append(EventKind.BACK)
		return
	if pressed.has(KeyScancodes.F1):
		_state = State.TO_CAPTURE
		_phase = 0
		_counter = 0
		_events.append(EventKind.ENTER)
		_shown.fill(SHOWN_BLANK)


func _update_capture(pressed: PackedInt32Array) -> void:
	match _helper_c:
		Capture.ENTER:
			_action = 0
			_scratch = _bindings.keys(_record)
			_helper_c = Capture.WAIT
			_shown[0] = SHOWN_PROMPT
		Capture.WAIT:
			_capture_key(pressed)
		_:
			_capture_advance()


func _capture_key(pressed: PackedInt32Array) -> void:
	if pressed.has(KeyScancodes.ESCAPE):
		_state = State.FROM_CAPTURE
		_phase = 0
		_counter = 0
		_bindings.set_keys(_record, _scratch)
		_events.append(EventKind.BACK)
		return
	if pressed.is_empty():
		return
	var ordered: PackedInt32Array = pressed.duplicate()
	ordered.sort()
	var scancode: int = ordered[0]
	if not KeyScancodes.is_bindable(scancode):
		_events.append(EventKind.REFUSE_UNNAMED)
		return
	if _bindings.key_already_bound(_record, _action, scancode):
		_events.append(EventKind.REFUSE_DUPLICATE)
		return
	_bindings.set_key(_record, _action, scancode)
	_shown[_action] = scancode
	_events.append(EventKind.ACCEPT)
	_phase = 0
	_counter = 0
	_helper_c = Capture.ADVANCE


func _capture_advance() -> void:
	_counter += 1
	if _phase == 0:
		if _counter != SLIDE_FRAMES:
			return
		_counter = 0
		_phase = 1
		if _action != KeyBindings.ACTION_COUNT - 1:
			_shown[_action + 1] = SHOWN_PROMPT
		return
	if _counter != SLIDE_FRAMES:
		return
	_counter = 0
	_phase = 0
	_action += 1
	if _action == KeyBindings.ACTION_COUNT:
		_bindings.set_valid(_record, _bindings.keys_unique(_record))
		_state = State.FROM_CAPTURE
		_phase = 0
		_counter = 0
		return
	_helper_c = Capture.WAIT
