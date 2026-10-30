class_name OptionsMenu
extends RefCounted
## The options page's 30 Hz tick machine (OptionsUpdate and OptionsUpdateFrog, tempopt.c:4551-5067).
##
## Each [method step] runs the camera sweep timer, HSUpdateFlying's fly-on/fly-off counters, the
## frog's hop between lilies, then the back, volume and fire reads. Retail PC shows four lilies
## (three titled rows and one volume log); the port shows exit, view high scores, controls, music
## and effects, with the high-score row hidden until [member scores_available]. State is integer
## and source-scaled; the presentation reads it and applies the volumes every tick.

enum Row { EXIT, VIEW_SCORES, CONTROLS, MUSIC, EFFECTS }
enum EventKind { HOP, SPLASH, VOLUME_STEP, CROAK, VOLUME_TEST_SOUND, STOP_TEST_SOUND, BACK, CONTROLS, VIEW_SCORES, LEAVE }
enum Request { NONE, MAIN_MENU, CONTROLS, VIEW_SCORES }
enum Camera { OPTIONS, MAIN, CONTROLS }

const SOUND_STAGES: int = 8
const START_MUSIC: int = 3
const START_SOUND: int = 5
const VOLUME_SCALE: int = 127
const FROG_JUMP_TIME: int = 12
const FLY_ON_TIME: int = 10
const FLY_OFF_TIME: int = 10
const FLY_ON_SPEED: int = 0xa0
const FLY_OFF_SPEED: int = 0x100
const FLY_ON_HEIGHT: int = -FLY_ON_TIME * FLY_ON_SPEED
const CAMERA_MOVE_TIME: int = FLY_OFF_TIME + FLY_ON_TIME
const PROMPT_STEP: int = 10
const GLOW_IDLE: int = 0x20
const LOG_CEL_BLANK: int = 10
const LOG_CEL_FULL: int = 11
const LOG_CEL_HALF: int = 12
const LILY_X: int = -0x380
const LOG_X: int = 0
const TOP_LILY_Z: int = 0x2c0
const ROW_PITCH: int = 0x200
const CONTROLS_CAMERA_SOURCE: Vector3i = Vector3i(1500, -2400, -1000)
const CONTROLS_CAMERA_TARGET: Vector3i = Vector3i.ZERO
const ROW_NAMES: PackedStringArray = ["exit", "view_scores", "controls", "music", "effects"]


## One tick's controls as bitmasks of the button constants: held and newly pressed.
class Buttons:
	extends RefCounted
	## FRR_UP.
	const UP: int = 1 << 0
	## FRR_DOWN.
	const DOWN: int = 1 << 1
	## FRR_LEFT.
	const LEFT: int = 1 << 2
	## FRR_RIGHT.
	const RIGHT: int = 1 << 3
	## FRR_CROSS, the fire button.
	const FIRE: int = 1 << 4
	## FRR_TRIANGLE, FRR_START or retail's pressed-edge Escape.
	const BACK: int = 1 << 5

	## Buttons held this tick; only UP and DOWN are read held.
	var held: int = 0
	## Buttons pressed this tick; LEFT, RIGHT, FIRE and BACK are read on the edge.
	var pressed: int = 0

	func _init(held_mask: int = 0, pressed_mask: int = 0) -> void:
		held = held_mask
		pressed = pressed_mask


var _rows: PackedInt32Array = PackedInt32Array()
var _scores_available: bool = false
var _row: int = 0
var _jumping: bool = false
var _count: int = 0
var _lift: int = 0
var _music: int = START_MUSIC
var _effects: int = START_SOUND
var _fly_on: int = FLY_ON_TIME
var _fly_off: int = 0
var _flying_on: int = FLY_ON_TIME
var _flying_off: int = 0
var _camera: int = Camera.OPTIONS
var _camera_timer: int = FLY_ON_TIME
var _request: int = Request.NONE
var _finished: bool = false
var _test_sound: bool = false
var _music_glow: int = GLOW_IDLE
var _effects_glow: int = GLOW_IDLE

## True when the view-high-scores row is shown.
var scores_available: bool:
	get:
		return _scores_available
## Index of the frog's lily among [method rows] (fr_grid_z): the lily it is on or hopping to.
var row: int:
	get:
		return _row
## The [enum Row] of the frog's lily.
var row_kind: int:
	get:
		return _rows[_row]
## True while the frog is hopping between lilies (FROG_MODE_JUMPING).
var jumping: bool:
	get:
		return _jumping
## Hop ticks left, FROG_JUMP_TIME down to 1 while hopping, 0 when stationary (fr_count).
var jump_count: int:
	get:
		return _count
## This tick's hop parabola height above the straight line, 0 when stationary or landed.
var lift: int:
	get:
		return _lift
## Music volume step, 0..SOUND_STAGES (Music_volume).
var music_volume: int:
	get:
		return _music
## Effects volume step, 0..SOUND_STAGES (Sound_volume).
var effects_volume: int:
	get:
		return _effects
## Fly-on counter (High_score_view_flyon_counter): models drop onto the water while non-zero.
var fly_on: int:
	get:
		return _fly_on
## Fly-off counter (High_score_view_flyoff_counter): models slide away while non-zero.
var fly_off: int:
	get:
		return _fly_off
## The fly-on counter as HSUpdateFlying left it on the last tick, before that tick's input.
var flying_on: int:
	get:
		return _flying_on
## The fly-off counter as HSUpdateFlying left it on the last tick, before that tick's input.
var flying_off: int:
	get:
		return _flying_off
## The [enum Camera] the options camera is sweeping to.
var camera: int:
	get:
		return _camera
## Options camera sweep ticks left after this tick (ca_move_timer).
var camera_timer: int:
	get:
		return _camera_timer
## The [enum Request] chosen; the page leaves once [member finished].
var request: int:
	get:
		return _request
## True once the page has raised LEAVE; further steps do nothing.
var finished: bool:
	get:
		return _finished
## True while the repeating croak volume test plays on the effects row.
var test_sound: bool:
	get:
		return _test_sound
## Custom ambient of the music volume model: the glow while selected, otherwise GLOW_IDLE.
var music_glow: int:
	get:
		return _music_glow
## Custom ambient of the effects volume model: the glow while selected, otherwise GLOW_IDLE.
var effects_glow: int:
	get:
		return _effects_glow


## A page with volume steps [param music] and [param effects], the frog on [param start_row]
## (an [enum Row]; the first row when it is not shown) and the high-score row shown only when
## [param show_scores]. OptionsStartup keeps the row when returning from the controller page and
## resets it to EXIT when entered from the main menu.
static func create(music: int = START_MUSIC, effects: int = START_SOUND, start_row: int = Row.EXIT,
		show_scores: bool = false) -> OptionsMenu:
	var menu := OptionsMenu.new()
	menu._scores_available = show_scores
	menu._rows = rows_for(show_scores)
	menu._row = maxi(menu._rows.find(start_row), 0)
	menu._music = clampi(music, 0, SOUND_STAGES)
	menu._effects = clampi(effects, 0, SOUND_STAGES)
	return menu


## The shown [enum Row] values top to bottom, without VIEW_SCORES unless [param show_scores].
static func rows_for(show_scores: bool) -> PackedInt32Array:
	var result := PackedInt32Array()
	for kind: int in Row.values():
		if show_scores or kind != Row.VIEW_SCORES:
			result.append(kind)
	return result


## The lower-case name of [param kind], or "".
static func row_name(kind: int) -> String:
	return ROW_NAMES[kind] if kind >= 0 and kind < ROW_NAMES.size() else ""


## The MRSNDSetVolumeLevel level, 0..127, of volume step [param value].
static func volume_level(value: int) -> int:
	return (VOLUME_SCALE * value) / SOUND_STAGES


## The animated cel of stages 1..8 of a volume log at step [param value] (OptionsSetupVolumeLogAnimatedPolys).
static func log_cels(value: int) -> PackedInt32Array:
	var cels := PackedInt32Array()
	for stage: int in range(1, SOUND_STAGES + 1):
		if value == 0 or stage > value:
			cels.append(LOG_CEL_BLANK)
		elif stage == value:
			cels.append(LOG_CEL_HALF)
		else:
			cels.append(LOG_CEL_FULL)
	return cels


## The hop parabola height for [param count] hop ticks left before the decrement.
static func jump_lift(count: int) -> int:
	var half: int = FROG_JUMP_TIME >> 1
	return -8 * (half * half - (count - half) * (count - half))


## Z of the lily at shown row [param index]; four rows give retail's 0x2c0, 0xc0, -0x140, -0x340.
static func lily_z(index: int) -> int:
	return TOP_LILY_Z - index * ROW_PITCH


## The shown [enum Row] values top to bottom.
func rows() -> PackedInt32Array:
	return _rows.duplicate()


## The glow of the volume model for [param kind] (MUSIC or EFFECTS), GLOW_IDLE for other rows.
func glow(kind: int) -> int:
	match kind:
		Row.MUSIC:
			return _music_glow
		Row.EFFECTS:
			return _effects_glow
	return GLOW_IDLE


## Volume step of [param kind] (MUSIC or EFFECTS), -1 for other rows.
func volume(kind: int) -> int:
	match kind:
		Row.MUSIC:
			return _music
		Row.EFFECTS:
			return _effects
	return -1


## Advances one tick with [param buttons] while the options viewport's frame count is
## [param frame] and returns the [enum EventKind] values it raised, in order.
func step(buttons: Buttons, frame: int) -> PackedInt32Array:
	var events := PackedInt32Array()
	if _finished:
		return events
	_camera_timer = maxi(1, _camera_timer) - 1
	if _fly_on != 0:
		_fly_on -= 1
	if _fly_off != 0:
		_fly_off -= 1
		if _fly_off == 0:
			_finished = true
			events.append(EventKind.LEAVE)
	_flying_on = _fly_on
	_flying_off = _fly_off
	_music_glow = GLOW_IDLE
	_effects_glow = GLOW_IDLE
	_update_frog(buttons, events)
	if _request != Request.NONE or _finished:
		return events
	if buttons.pressed & Buttons.BACK != 0 and _fly_off == 0 and _fly_on == 0:
		_stop_test_sound(events)
		events.append(EventKind.CROAK)
		_start_leaving(Request.MAIN_MENU, Camera.MAIN, EventKind.BACK, events)
		return events
	if _jumping:
		return events
	var kind: int = _rows[_row]
	if kind == Row.MUSIC or kind == Row.EFFECTS:
		_step_volume(kind, buttons, frame, events)
	if buttons.pressed & Buttons.FIRE != 0 and _fly_off == 0 and _fly_on == 0:
		events.append(EventKind.CROAK)
		match kind:
			Row.EXIT:
				_start_leaving(Request.MAIN_MENU, Camera.MAIN, EventKind.BACK, events)
			Row.CONTROLS:
				_start_leaving(Request.CONTROLS, Camera.CONTROLS, EventKind.CONTROLS, events)
			Row.VIEW_SCORES:
				_request = Request.VIEW_SCORES
				_finished = true
				events.append(EventKind.VIEW_SCORES)
				events.append(EventKind.LEAVE)
	return events


func _update_frog(buttons: Buttons, events: PackedInt32Array) -> void:
	if not _jumping:
		_lift = 0
		var old: int = _row
		if buttons.held & Buttons.UP != 0 and _row > 0:
			_row -= 1
		elif buttons.held & Buttons.DOWN != 0 and _row < _rows.size() - 1:
			_row += 1
		if _row != old:
			_jumping = true
			_count = FROG_JUMP_TIME
			events.append(EventKind.HOP)
			if _rows[old] == Row.EFFECTS:
				_stop_test_sound(events)
		return
	_lift = jump_lift(_count)
	_count -= 1
	if _count == 0:
		_jumping = false
		_lift = 0
		events.append(EventKind.SPLASH)
		if _rows[_row] == Row.EFFECTS:
			_test_sound = true
			events.append(EventKind.VOLUME_TEST_SOUND)


func _step_volume(kind: int, buttons: Buttons, frame: int, events: PackedInt32Array) -> void:
	var value: int = _music if kind == Row.MUSIC else _effects
	var glow_value: int = (frame & 7) << 5
	if kind == Row.MUSIC:
		_music_glow = glow_value
	else:
		_effects_glow = glow_value
	if buttons.pressed & Buttons.RIGHT != 0:
		if value < SOUND_STAGES:
			value += 1
			events.append(EventKind.VOLUME_STEP)
	elif buttons.pressed & Buttons.LEFT != 0:
		if value > 0:
			value -= 1
			events.append(EventKind.VOLUME_STEP)
	if kind == Row.MUSIC:
		_music = value
	else:
		_effects = value


func _stop_test_sound(events: PackedInt32Array) -> void:
	if _test_sound:
		_test_sound = false
		events.append(EventKind.STOP_TEST_SOUND)


func _start_leaving(chosen: int, target: int, event: int, events: PackedInt32Array) -> void:
	_request = chosen
	_fly_off = FLY_OFF_TIME
	_fly_on = 0
	_camera = target
	_camera_timer = CAMERA_MOVE_TIME
	events.append(event)
