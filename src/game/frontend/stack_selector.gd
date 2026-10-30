class_name StackSelector
extends RefCounted
## The arcade level-select stack's 30 Hz tick machine (SelectLevelUpdate, SELECT.C:1255-1470).
##
## Each [method step] runs SelectUpdateLevelSlide, then the current mode: the glow update and
## camera/input handling while selecting, the spin-out info view, and the fade into the game.
## State is integer and source-scaled; the renderer reads it and interpolates between ticks.
## Flags and row levels are read from the [LevelProgress] given to [method create] every tick.
## After BACK or ENTER_GAME the selector is [member finished] and further steps do nothing.

enum Mode { SELECTING, SHOW_LEVEL_INFO, START_FADE, UPDATE_FADE }
enum EventKind { HOP, CROAK, ENTER_GAME, BACK }

const SPIN_OUT: int = 1 << 0
const SPIN_IN: int = 1 << 1
const SPIN_HOLD: int = 1 << 2
const SPIN_TIME: int = 10
const CAMERA_GOING_UP: int = 1 << 0
const CAMERA_GOING_DOWN: int = 1 << 1
const CAMERA_STATIONARY: int = 1 << 2
const CAMERA_STOPPING: int = 1 << 3
const CAMERA_MAX_VEL: int = 56
const CAMERA_ACC: int = 4
const SLIDE_INC: int = 0x40
const SLIDE_DIST: int = -(StackLayout.BOX_HALF_SIZE << 1)
const FADE_TICKS: int = 0x20
const GLOWY_MIN: int = 0x60
const GLOWY_MAX: int = 0xa0
const GLOWY_SPEED: int = 16
const DARK_COLOUR: int = 0x40
const LIGHT_COLOUR: int = 0x80
const SPIN_IMAGE_COLOUR: int = 0x80
const IDENTITY_AXES: Array[Vector3i] = [Vector3i(4096, 0, 0), Vector3i(0, 4096, 0), Vector3i(0, 0, 4096)]


## One tick's controls: held directions and newly pressed buttons.
class Buttons:
	extends RefCounted
	## MRIP_UP held.
	var up_held: bool = false
	## MRIP_DOWN held; wins over up.
	var down_held: bool = false
	## FR_GO pressed this tick.
	var go_pressed: bool = false
	## FRR_TRIANGLE pressed this tick.
	var back_pressed: bool = false

	func _init(up: bool = false, down: bool = false, go: bool = false, back: bool = false) -> void:
		up_held = up
		down_held = down
		go_pressed = go
		back_pressed = back


## Something a tick asks the front end to do.
class Event:
	extends RefCounted
	## An [enum EventKind] value.
	var kind: int = 0
	## The row's current level for ENTER_GAME, otherwise -1.
	var level: int = -1

	func _init(event_kind: int = 0, event_level: int = -1) -> void:
		kind = event_kind
		level = event_level


var _layout: StackLayout = null
var _progress: LevelProgress = null
var _name_widths: PackedInt32Array = PackedInt32Array()
var _glow_enabled: bool = true
var _finished: bool = false
var _mode: int = Mode.SELECTING
var _first_time: bool = true
var _work_row: int = 0
var _glowy_row: int = 0
var _spin_row: int = -1
var _camera_y: int = 0
var _camera_frame_y: int = 0
var _camera_vel: int = 0
var _camera_acc: int = 0
var _camera_flag: int = CAMERA_STATIONARY
var _target_y: int = 0
var _current_z: PackedInt32Array = PackedInt32Array()
var _tints: PackedInt32Array = PackedInt32Array()
var _glow: int = GLOWY_MAX
var _glow_dir: int = -GLOWY_SPEED
var _spin_mode: int = 0
var _spin_time: int = 0
var _spin_sin: int = -4096
var _spin_start: Vector3i = Vector3i.ZERO
var _spin_end: Vector3i = Vector3i.ZERO
var _spin_position: Vector3i = Vector3i.ZERO
var _spin_vec_y: Vector3i = StackLayout.SPIN_START_VEC_Y
var _spin_vec_roll: Vector3i = StackLayout.SPIN_START_VEC_ROLL
var _spin_axes: Array[Vector3i] = IDENTITY_AXES.duplicate()
var _panel_x: int = StackLayout.STATUS_START_X
var _title_x: int = StackLayout.STATUS_START_X
var _fade_count: int = 0
var _fade_title_y: int = StackLayout.TITLE_Y
var _fade_prompt_y: int = StackLayout.PROMPT_Y
var _fade_name_x: int = StackLayout.STATUS_START_X

## Current [enum Mode].
var mode: int:
	get:
		return _mode
## True once BACK or ENTER_GAME has been raised; the front end leaves the page.
var finished: bool:
	get:
		return _finished
## Sel_first_time: true until a level is chosen; back is accepted only then.
var first_time: bool:
	get:
		return _first_time
## Row the camera is on or heading for (Sel_work_level_ptr).
var focused_row: int:
	get:
		return _work_row
## Row whose theme glows (Sel_glowy_level_ptr): the focused row, or the last row slid further out.
var glowy_row: int:
	get:
		return _glowy_row
## Row shown by the spinning box while [method spin_visible], otherwise -1.
var spin_row: int:
	get:
		return _spin_row
## Camera frame Y after this tick (Sel_camera_frame t[1]).
var camera_y: int:
	get:
		return _camera_frame_y
## Camera velocity (Sel_camera_vel).
var camera_velocity: int:
	get:
		return _camera_vel
## Camera acceleration (Sel_camera_acc).
var camera_acceleration: int:
	get:
		return _camera_acc
## Camera movement flags (CAMERA_*).
var camera_flag: int:
	get:
		return _camera_flag
## Camera Y being approached (Sel_target_y).
var target_y: int:
	get:
		return _target_y
## Glow colour component (Sel_glowy_col.r).
var glow_value: int:
	get:
		return _glow
## Glow step per update, +16 or -16 (Sel_glowy_dir).
var glow_direction: int:
	get:
		return _glow_dir
## Spin phase (SPIN_OUT, SPIN_HOLD or SPIN_IN), 0 before the first spin.
var spin_mode: int:
	get:
		return _spin_mode
## Spin timer, 0..SPIN_TIME; -1 after the spin has returned.
var spin_time: int:
	get:
		return _spin_time
## Last eased sine of the spin, -4096 at rest to 4096 at the info position.
var spin_sin: int:
	get:
		return _spin_sin
## World position of the spinning box's frame (Sel_temp_pos).
var spin_position: Vector3i:
	get:
		return _spin_position
## Interpolated Y axis of the spinning box before normalising (Sel_temp_vec_y).
var spin_vec_y: Vector3i:
	get:
		return _spin_vec_y
## Interpolated roll vector of the spinning box (Sel_temp_vec_roll).
var spin_vec_roll: Vector3i:
	get:
		return _spin_vec_roll
## Left X of the info panel and score lines (Sel_status_temp_x).
var panel_x: int:
	get:
		return _panel_x
## Level name sprite X during the spin (Sel_level_title sp_pos.x).
var title_x: int:
	get:
		return _title_x
## Fade counter (Sel_count): 1..FADE_TICKS while fading, then FADE_TICKS + 1.
var fade_count: int:
	get:
		return _fade_count
## Title sprite Y during the fade, rising 8 per tick.
var fade_title_y: int:
	get:
		return _fade_title_y
## Prompt sprite Y during the fade, falling 8 per tick.
var fade_prompt_y: int:
	get:
		return _fade_prompt_y
## Level name sprite X during the fade, easing to the screen centre.
var fade_name_x: int:
	get:
		return _fade_name_x


## A selector over [param layout] and [param progress] focused on the row holding
## [param focus_level] (ORG1 on the first entry; the first row when absent).
## [param first_time_entry] is Sel_first_time. [param name_widths] holds each row's level-name
## image width for the name sprite positions (zero when omitted). [param glow] enables the PSX
## glow update (SelectUpdateGlowyColours); without it the tints keep SelectCreateMOF's values.
static func create(layout: StackLayout, progress: LevelProgress, focus_level: int,
		first_time_entry: bool, name_widths: PackedInt32Array = PackedInt32Array(),
		glow: bool = true) -> StackSelector:
	var selector := StackSelector.new()
	selector._layout = layout
	selector._progress = progress
	selector._glow_enabled = glow
	selector._first_time = first_time_entry
	var count: int = layout.row_count()
	selector._name_widths = name_widths.duplicate()
	selector._name_widths.resize(count)
	selector._work_row = maxi(progress.arcade_levels.find(focus_level), 0)
	selector._glowy_row = selector._work_row
	selector._current_z.resize(count)
	selector._current_z.fill(0)
	for row: int in count:
		selector._tints.append(creation_tint(selector._flags(row)))
	if count > 0:
		selector._camera_y = layout.camera_target_y(selector._work_row)
	selector._camera_frame_y = selector._camera_y
	selector._target_y = selector._camera_y
	return selector


## The tint SelectCreateMOF gives every face of a row with [param flags].
static func creation_tint(flags: int) -> int:
	return LIGHT_COLOUR if flags & LevelProgress.COMPLETED != 0 else DARK_COLOUR


## The eased spin sine for [param time] of [param max_time] ticks (SelectUpdateInterpolation).
static func spin_sine(time: int, max_time: int = SPIN_TIME) -> int:
	var half: int = max_time >> 1
	if time < half:
		return -StackLayout.rsin(((half - time) * 0x800) / max_time)
	return StackLayout.rsin(((time - half) * 0x800) / max_time)


## [param from] moved toward [param to] by eased sine [param sine], truncating as the source does.
static func interpolate(from: int, to: int, sine: int) -> int:
	return from + ((sine + 0x1000) * (to - from)) / 0x2000


## [method interpolate] per component.
static func interpolate_vector(from: Vector3i, to: Vector3i, sine: int) -> Vector3i:
	return Vector3i(interpolate(from.x, to.x, sine), interpolate(from.y, to.y, sine), interpolate(from.z, to.z, sine))


## Spin progress 0..1 from the last eased sine.
func spin_ease() -> float:
	return float(_spin_sin + 0x1000) / 8192.0


## The spinning box frame's X, Y and Z axes in 4.12 (the matrix columns built from the
## interpolated vectors, SELECT.C:2339-2354).
func spin_axes() -> Array[Vector3i]:
	return _spin_axes.duplicate()


## Number of rows.
func row_count() -> int:
	return _current_z.size()


## Slide-out Z of row [param row], 0 at rest to SLIDE_DIST fully out (li_current_z).
func current_z(row: int) -> int:
	return _current_z[row]


## Face colour component of row [param row] (mp_cvec).
func tint(row: int) -> int:
	return _tints[row]


## The current level of the focused row.
func focused_level() -> int:
	return _progress.arcade_levels[_work_row]


## True while the spinning box replaces the spin row's box (SelectEnableSpinMOF until
## SelectDisableSpinMOF); it stays up through the fade.
func spin_visible() -> bool:
	return _spin_row >= 0


## Shade of the subtractive fade rectangle: 0 before the fade, count * 8 - 1, then 0xff.
func fade_shade() -> int:
	if _fade_count == 0:
		return 0
	return 0xff if _fade_count > FADE_TICKS else _fade_count * 8 - 1


## Colour of the LOADING sprite while fading: count * 4 up to 0x80.
func fade_loading_colour() -> int:
	return mini(_fade_count, FADE_TICKS) * 4


## Advances one tick with [param buttons] and returns the events it raised.
func step(buttons: Buttons) -> Array[Event]:
	var events: Array[Event] = []
	if _finished or row_count() == 0:
		return events
	_update_slide()
	match _mode:
		Mode.SELECTING:
			if _glow_enabled:
				_update_glow()
			_update_selecting(buttons, events)
		Mode.SHOW_LEVEL_INFO:
			if _glow_enabled:
				_update_glow()
			_update_show_info(buttons, events)
		_:
			_update_fade(events)
	return events


func _flags(row: int) -> int:
	return _progress.arcade_flags[row] if row < _progress.arcade_flags.size() else 0


func _name_width() -> int:
	return _name_widths[_work_row]


func _update_slide() -> void:
	var viewed_y: int = _camera_frame_y - StackLayout.CAMERA_Y_OFFSET
	_glowy_row = _work_row
	var max_z: int = _current_z[_work_row]
	for row: int in row_count():
		var centre: int = _layout.y_position(row)
		var size: int = _layout.y_size(row)
		if viewed_y >= centre - size and viewed_y <= centre + size:
			_current_z[row] = maxi(_current_z[row] - SLIDE_INC, SLIDE_DIST)
		else:
			_current_z[row] = mini(_current_z[row] + SLIDE_INC, 0)
		if _current_z[row] < max_z:
			_glowy_row = row


func _update_glow() -> void:
	if _camera_flag != CAMERA_STATIONARY or _mode == Mode.UPDATE_FADE or _glow > GLOWY_MAX:
		_glow_dir = -absi(_glow_dir)
	elif _glow < GLOWY_MIN:
		_glow_dir = absi(_glow_dir)
	if _glow >= DARK_COLOUR or _glow >= GLOWY_MIN:
		_glow = (_glow + _glow_dir) & 0xff
	var glowy_theme: int = _progress.arcade_themes[_glowy_row]
	for row: int in row_count():
		var flags: int = _flags(row)
		if flags & LevelProgress.SELECTABLE != 0 and flags & LevelProgress.COMPLETED == 0 \
				and _progress.arcade_themes[row] == glowy_theme:
			_tints[row] = _glow
		elif (flags & LevelProgress.COMPLETED) | int(flags & LevelProgress.ZONE_ACCESSIBLE == 0) != 0:
			_tints[row] = LIGHT_COLOUR
		else:
			_tints[row] = DARK_COLOUR


func _update_selecting(buttons: Buttons, events: Array[Event]) -> void:
	_camera_vel = clampi(_camera_vel + _camera_acc, -CAMERA_MAX_VEL, CAMERA_MAX_VEL)
	_camera_y += _camera_vel
	var reached: bool = false
	if _camera_flag & CAMERA_GOING_DOWN != 0:
		if _camera_frame_y <= _target_y and _camera_y >= _target_y:
			reached = true
			_glow = DARK_COLOUR
	elif _camera_flag & CAMERA_GOING_UP != 0:
		if _camera_frame_y >= _target_y and _camera_y <= _target_y:
			reached = true
			_glow = DARK_COLOUR
	elif _camera_flag == CAMERA_STATIONARY:
		reached = true
	_camera_frame_y = _camera_y
	if _camera_flag & CAMERA_STATIONARY != 0:
		if buttons.down_held:
			if _find_target(1):
				events.append(Event.new(EventKind.HOP))
				_camera_flag = CAMERA_GOING_DOWN
				_camera_acc = CAMERA_ACC
				reached = false
		elif buttons.up_held:
			if _find_target(-1):
				events.append(Event.new(EventKind.HOP))
				_camera_flag = CAMERA_GOING_UP
				_camera_acc = -CAMERA_ACC
				reached = false
		elif buttons.go_pressed:
			if _current_z[_work_row] == SLIDE_DIST:
				events.append(Event.new(EventKind.HOP))
				_mode = Mode.SHOW_LEVEL_INFO
				_enable_spin()
				return
		elif _first_time and buttons.back_pressed:
			events.append(Event.new(EventKind.BACK))
			_finished = true
	if _camera_flag == CAMERA_GOING_DOWN:
		if not buttons.down_held:
			_camera_flag |= CAMERA_STOPPING
		elif reached:
			if _find_target(1):
				reached = false
			else:
				_camera_flag |= CAMERA_STOPPING
	if _camera_flag == CAMERA_GOING_UP:
		if not buttons.up_held:
			_camera_flag |= CAMERA_STOPPING
		elif reached:
			if _find_target(-1):
				reached = false
			else:
				_camera_flag |= CAMERA_STOPPING
	if _camera_flag & CAMERA_STOPPING != 0 and reached:
		_camera_acc = 0
		_camera_vel = 0
		_camera_flag = CAMERA_STATIONARY
		_camera_y = _target_y
		_camera_frame_y = _camera_y


func _find_target(direction: int) -> bool:
	var row: int = _work_row + direction
	while row >= 0 and row < row_count():
		if _flags(row) & LevelProgress.SELECTABLE != 0:
			_work_row = row
			_target_y = _layout.camera_target_y(row)
			return true
		row += direction
	return false


func _enable_spin() -> void:
	_spin_row = _work_row
	_spin_start = _layout.spin_start(_work_row, _current_z[_work_row])
	_spin_end = _layout.spin_end(_work_row)
	_spin_position = _spin_start
	_spin_vec_y = StackLayout.SPIN_START_VEC_Y
	_spin_vec_roll = StackLayout.SPIN_START_VEC_ROLL
	_spin_axes = IDENTITY_AXES.duplicate()
	_spin_time = 0
	_spin_mode = SPIN_OUT


func _update_show_info(buttons: Buttons, events: Array[Event]) -> void:
	if _spin_mode == SPIN_OUT or _spin_mode == SPIN_IN:
		_interpolate_spin()
		if _spin_mode == SPIN_OUT:
			_spin_time += 1
			if _spin_time > SPIN_TIME:
				_spin_time = SPIN_TIME
				_spin_mode = SPIN_HOLD
		else:
			_spin_time -= 1
			if _spin_time < 0:
				_mode = Mode.SELECTING
				_spin_row = -1
		var local_y: Vector3i = StackLayout.normalise(_spin_vec_y)
		var local_x: Vector3i = StackLayout.normalise(StackLayout.outer12(local_y, _spin_vec_roll))
		var local_z: Vector3i = StackLayout.outer12(local_x, local_y)
		_spin_axes = [_s16_vector(local_x), _s16_vector(local_y), _s16_vector(local_z)]
		_title_x = _panel_x + (StackLayout.STATUS_WIDTH >> 1) - (_name_width() >> 1)
	elif buttons.back_pressed:
		events.append(Event.new(EventKind.HOP))
		_spin_mode = SPIN_IN
	elif buttons.go_pressed:
		events.append(Event.new(EventKind.CROAK))
		_mode = Mode.START_FADE
		_fade_count = 0
		_first_time = false


func _interpolate_spin() -> void:
	_spin_sin = spin_sine(_spin_time)
	_spin_position = interpolate_vector(_spin_start, _spin_end, _spin_sin)
	_spin_vec_y = interpolate_vector(StackLayout.SPIN_START_VEC_Y, StackLayout.spin_dest_vec_y(), _spin_sin)
	_spin_vec_roll = interpolate_vector(StackLayout.SPIN_START_VEC_ROLL, StackLayout.spin_dest_vec_roll(), _spin_sin)
	_panel_x = interpolate(StackLayout.STATUS_START_X, StackLayout.STATUS_END_X, _spin_sin)


func _update_fade(events: Array[Event]) -> void:
	if _mode == Mode.START_FADE:
		_fade_title_y = StackLayout.TITLE_Y
		_fade_prompt_y = StackLayout.PROMPT_Y
		_fade_name_x = _title_x
		_fade_count = 0
		_mode = Mode.UPDATE_FADE
	_fade_count += 1
	if _fade_count <= FADE_TICKS:
		_fade_title_y -= 8
		_fade_prompt_y += 8
		var centre: int = (StackLayout.DISPLAY_WIDTH >> 1) - (_name_width() >> 1)
		_fade_name_x -= (_fade_name_x - centre) / (0x21 - _fade_count)
	else:
		events.append(Event.new(EventKind.ENTER_GAME, focused_level()))
		_finished = true


static func _s16_vector(vector: Vector3i) -> Vector3i:
	return Vector3i(StackLayout.s16(vector.x), StackLayout.s16(vector.y), StackLayout.s16(vector.z))
