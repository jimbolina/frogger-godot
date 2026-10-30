class_name ControlsView
extends Control
## The controller page (retail page 25) drawn from a [ControlsPage] stepped at 30 Hz on black,
## as retail shows it, while the front-end water keeps animating underneath.
##
## Each pressed key becomes a DirectInput scancode ([method KeyScancodes.from_godot]) and every
## scancode pressed since the last tick goes to that tick's step. The page shows the player
## record, the device carousel (none, keyboard and joysticks) with the named keyboard, pad and
## arrow images, the help lines and, in the key list and capture, the nine actions with their
## keys' retail English names. Labels are drawn in the default font, not the newfont image.
## Slides move the page sideways for their 16 ticks. Each tick's events are raised through
## [signal page_event]; the page is done when [method ControlsPage.is_finished].

## A [enum ControlsPage.EventKind] raised by the last tick.
signal page_event(kind: int)

## Seconds per page tick.
const PERIOD: float = GameplayHost.PERIOD
## The display the source draws on.
const DISPLAY_SIZE: Vector2 = Vector2(640.0, 480.0)
## Spacing of the carousel's devices.
const DEVICE_SPACING: float = 180.0
## Height of the carousel's centre line.
const DEVICE_Y: float = 230.0
## Joystick slots drawn after the keyboard even when none is attached.
const PAD_SLOTS: int = 2
## The page's background over the water.
const SHADE: Color = Color.BLACK
const TEXT_COLOUR: Color = Color(0.95, 0.95, 0.9)
const KEY_COLOUR: Color = Color(1.0, 0.85, 0.3)
const DIM: Color = Color(0.45, 0.45, 0.45, 0.8)
const WARNING_COLOUR: Color = Color(1.0, 0.35, 0.3)
const NONE_COLOUR: Color = Color(0.55, 0.12, 0.1)
## Each action's label, in [enum KeyBindings.Action] order.
const ACTION_LABELS: PackedStringArray = [
	"LEFT", "RIGHT", "UP", "DOWN", "SUPER JUMP", "TONGUE", "CROAK", "CAMERA CLOCKWISE", "CAMERA ANTICLOCKWISE",
]
const CHOOSER_HELP: PackedStringArray = ["F1  PREVIOUS PLAYER", "F2  NEXT PLAYER", "F3  VIEW KEYS", "RETURN  SELECT", "ESC  BACK"]
const KEY_LIST_HELP: PackedStringArray = ["F1  REDEFINE KEYS", "ESC  BACK"]
const CAPTURE_HELP: PackedStringArray = ["PRESS A KEY FOR EACH ACTION", "ESC  CANCEL"]

## The page being drawn.
var page: ControlsPage
## The shared options camera, swept on by this page.
var camera_rig: OptionsCamera
## The water and its camera.
var water: MenuWaterView
## Time since the last tick.
var elapsed: float = 0.0

var _assets: FrontEndAssets
var _pressed := PackedInt32Array()
var _font: Font


## A page editing [param bindings] over [param water_animation] seen through [param rig].
static func create(assets: FrontEndAssets, bindings: KeyBindings, water_animation: MenuWater, rig: OptionsCamera) -> ControlsView:
	var view := ControlsView.new()
	view._assets = assets
	view.camera_rig = rig
	view.page = ControlsPage.new(bindings)
	view._font = ThemeDB.fallback_font
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.water = MenuWaterView.create_with_camera(water_animation, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	view.water.camera.transform = rig.transform()
	view.add_child(view.water)
	return view


## The label shown for key-name value [param shown] ([method ControlsPage.shown]).
static func key_label(shown: int) -> String:
	if shown == ControlsPage.SHOWN_BLANK:
		return ""
	if shown == ControlsPage.SHOWN_PROMPT:
		return "_"
	return KeyScancodes.english_name(shown)


## Runs one page tick with the scancodes pressed since the last one and raises its events.
func tick() -> Array[int]:
	var pressed: PackedInt32Array = _pressed
	_pressed = PackedInt32Array()
	var events: Array[int] = page.step(pressed)
	camera_rig.tick()
	water.camera.transform = camera_rig.transform()
	queue_redraw()
	for kind: int in events:
		page_event.emit(kind)
	return events


## Records [param scancode] as pressed for the next tick.
func press(scancode: int) -> void:
	if scancode != KeyScancodes.UNKNOWN and not _pressed.has(scancode):
		_pressed.append(scancode)


func _process(delta: float) -> void:
	if page.is_finished():
		return
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo or not key.pressed:
		return
	press(BindingInput.scancode(key))
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DISPLAY_SIZE), SHADE)
	var state: int = page.state()
	_text("%dUP" % (page.record() + 1), Vector2(DISPLAY_SIZE.x * 0.5, 40.0), 32, TEXT_COLOUR, true)
	var title: Texture2D = _assets.texture("opt_ctrl_config")
	if title != null:
		draw_texture(title, Vector2((DISPLAY_SIZE.x - title.get_width()) * 0.5, 56.0))
	var offset: float = _slide_offset(state)
	if _shows_keys(state):
		_draw_keys(offset)
	else:
		_draw_chooser(offset)


func _shows_keys(state: int) -> bool:
	match state:
		ControlsPage.State.KEY_LIST, ControlsPage.State.CAPTURE, ControlsPage.State.TO_CAPTURE, ControlsPage.State.FROM_CAPTURE:
			return true
		ControlsPage.State.TO_KEY_LIST:
			return page.phase() == 1
		ControlsPage.State.TO_CHOOSER:
			return page.phase() == 0
	return false


func _slide_offset(state: int) -> float:
	var progress: float = float(page.counter()) / ControlsPage.SLIDE_FRAMES
	match state:
		ControlsPage.State.SEED:
			return DISPLAY_SIZE.x
		ControlsPage.State.ENTER:
			return (1.0 - progress) * DISPLAY_SIZE.x
		ControlsPage.State.EXIT:
			return -progress * DISPLAY_SIZE.x
		ControlsPage.State.TO_KEY_LIST, ControlsPage.State.TO_CHOOSER:
			return -progress * DISPLAY_SIZE.x if page.phase() == 0 else (1.0 - progress) * DISPLAY_SIZE.x
	return 0.0


func _draw_chooser(offset: float) -> void:
	var cursor: float = page.device_cursor()
	var progress: float = float(page.counter()) / ControlsPage.SLIDE_FRAMES
	match page.chooser_state():
		ControlsPage.Chooser.SLIDE_RIGHT:
			cursor -= 1.0 - progress
		ControlsPage.Chooser.SLIDE_LEFT:
			cursor += 1.0 - progress
	var alpha: float = 1.0
	if page.chooser_state() == ControlsPage.Chooser.RECORD_TURN:
		alpha = 1.0 - progress if page.phase() == 0 else progress
	var last: int = maxi(page.device_cursor_max(), KeyBindings.DEVICE_FIRST_JOYSTICK + PAD_SLOTS - 1)
	for device: int in last + 1:
		var centre := Vector2(DISPLAY_SIZE.x * 0.5 + offset + (device - cursor) * DEVICE_SPACING, DEVICE_Y)
		var tint: Color = Color.WHITE if device == page.device_cursor() else DIM
		tint.a *= alpha
		_draw_device(device, centre, tint)
	var chosen: int = page.bindings().device(page.record())
	var chosen_x: float = DISPLAY_SIZE.x * 0.5 + offset + (chosen - cursor) * DEVICE_SPACING
	draw_line(Vector2(chosen_x - 50.0, DEVICE_Y + 60.0), Vector2(chosen_x + 50.0, DEVICE_Y + 60.0), Color(KEY_COLOUR, alpha), 3.0)
	var left: Texture2D = _assets.texture("opt_arrow_small_left")
	var right: Texture2D = _assets.texture("opt_arrow_small_right")
	if left != null and page.device_cursor() > 0:
		draw_texture(left, Vector2(DISPLAY_SIZE.x * 0.5 + offset - left.get_width() - 4.0, DEVICE_Y + 70.0))
	if right != null and page.device_cursor() < page.device_cursor_max():
		draw_texture(right, Vector2(DISPLAY_SIZE.x * 0.5 + offset + 4.0, DEVICE_Y + 70.0))
	_help(CHOOSER_HELP, offset)
	if not page.bindings().every_record_valid():
		_text("EVERY PLAYER NEEDS NINE DIFFERENT KEYS", Vector2(DISPLAY_SIZE.x * 0.5 + offset, 320.0), 16, WARNING_COLOUR, true)


func _draw_device(device: int, centre: Vector2, tint: Color) -> void:
	if device == KeyBindings.DEVICE_NONE:
		var colour := Color(NONE_COLOUR.r, NONE_COLOUR.g, NONE_COLOUR.b, tint.a) * Color(tint.r, tint.g, tint.b, 1.0)
		draw_line(centre + Vector2(-36.0, -36.0), centre + Vector2(36.0, 36.0), colour, 12.0)
		draw_line(centre + Vector2(36.0, -36.0), centre + Vector2(-36.0, 36.0), colour, 12.0)
		return
	var image: Texture2D = _assets.texture("opt_keyboard" if device == KeyBindings.DEVICE_KEYBOARD else "opt_insert_pad")
	if image != null:
		draw_texture(image, centre - image.get_size() * 0.5, tint)
	if device >= KeyBindings.DEVICE_FIRST_JOYSTICK:
		_text(str(device - KeyBindings.DEVICE_FIRST_JOYSTICK + 1), centre + Vector2(0.0, 40.0), 28, tint, true)


func _draw_keys(offset: float) -> void:
	var top: float = 120.0
	for slot: int in KeyBindings.ACTION_COUNT:
		var y: float = top + slot * 26.0
		var capturing: bool = page.state() == ControlsPage.State.CAPTURE and page.action() == slot
		_text(ACTION_LABELS[slot], Vector2(80.0 + offset, y), 18, KEY_COLOUR if capturing else TEXT_COLOUR, false)
		_text(key_label(page.shown(slot)), Vector2(420.0 + offset, y), 18, KEY_COLOUR, false)
	if not page.bindings().is_valid(page.record()):
		_text("KEYS REPEATED", Vector2(DISPLAY_SIZE.x * 0.5 + offset, top + 9.0 * 26.0 + 6.0), 16, WARNING_COLOUR, true)
	_help(CAPTURE_HELP if page.state() == ControlsPage.State.CAPTURE else KEY_LIST_HELP, offset)


func _help(lines: PackedStringArray, offset: float) -> void:
	var y: float = DISPLAY_SIZE.y - 16.0 - (lines.size() - 1) * 30.0
	for line: String in lines:
		_text(line, Vector2(24.0 + offset, y), 20, TEXT_COLOUR, false)
		y += 30.0


func _text(text: String, at: Vector2, font_size: int, colour: Color, centred: bool) -> void:
	var x: float = at.x
	if centred:
		x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(_font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
