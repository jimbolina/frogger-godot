class_name HighScoreTour
extends RefCounted
## The high-score view page's 30 Hz tick machine (HSViewStartup, HSViewUpdate and its level-stack
## arms, HSView.c:633-1634).
##
## The page shows either the scrolly main table ([HighScoreScene]) or the level stack
## ([StackSelector]) whose spun-out level shows its three best rows. After name entry it tours the
## levels with new scores automatically, then shows the main table when it has a new score and
## returns to the main menu. From the options page the player switches between the stack and the
## table with LEFT and RIGHT and returns with BACK. A switch restarts the page as the source does
## (shutdown then startup) at the end of the tick that asked for it, so the state after that tick
## is the new view's startup state; BACK on that tick is overruled, as the switch's later write of
## Option_page_request wins (HSView.c:868, then :1066). The camera is always the static one here;
## the main menu runs [HighScoreScene] itself with the scrolly camera. After a request further
## ticks do nothing.

enum Operation { SCROLLY, LEVEL_SELECT }
enum CameraMode { STATIC, SCROLLY }
## HOP and CROAK play GEN_FROG_HOP and GEN_FROG_CROAK; SPLASH plays GEN_FROG_SPLASH1 (scene frog);
## SPIN_OUT shows [member shown_level]'s rows; SWITCHED restarted the page in the other view;
## BACK, BACK_TO_OPTIONS and TIMEOUT left the page; LEAVE ends a scene fly-off.
enum EventKind { HOP, CROAK, SPLASH, SPIN_OUT, SPIN_IN, SWITCHED, BACK, BACK_TO_OPTIONS, TIMEOUT, LEAVE }
## MAIN_MENU is OPTIONS_PAGE_MAIN_OPTIONS and OPTIONS is OPTIONS_PAGE_OPTIONS.
enum Request { NONE, MAIN_MENU, OPTIONS }

const AFTER_INPUT_DURATION: int = 4 * 30
const LEVEL_DURATION: int = 3 * 30
const CREEP_STEP: int = 20
const TOUR_WAIT: int = 10
const COUNTER_MASK: int = 0xffffffff
const LEVEL_ORIGINAL1: int = 24
const LEVEL_ORIGINAL_MULTI_PLAYER: int = 29
const STATIC_CAMERA_SOURCE: Vector3i = Vector3i(0, -3200, -200)
const STATIC_CAMERA_TARGET: Vector3i = Vector3i(0, 1024, 50)
const BACKGROUND_PERIOD: int = 24
const ARROW_LEFT: Vector2i = Vector2i(32, (StackLayout.DISPLAY_HEIGHT >> 1) - 16)
const ARROW_RIGHT: Vector2i = Vector2i(StackLayout.DISPLAY_WIDTH - 64, (StackLayout.DISPLAY_HEIGHT >> 1) - 16)
const PROMPT_SELECT1: StringName = &"select1"
const PROMPT_SELECT3: StringName = &"select3"
const PROMPT_SELECT5: StringName = &"select5"
const PROMPT_SKIP: StringName = &"skip_hi_score"

var _layout: StackLayout = null
var _progress: LevelProgress = null
var _main_rows: Array[HighScoreRow] = []
var _from_options: bool = false
var _automatic: bool = false
var _new_main: bool = false
var _new_levels: PackedByteArray = PackedByteArray()
var _first_time: bool = true
var _name_widths: PackedInt32Array = PackedInt32Array()
var _operation: int = Operation.LEVEL_SELECT
var _request: int = Request.NONE
var _counter: int = AFTER_INPUT_DURATION
var _wait: int = 0
var _picked: bool = false
var _background: int = 0
var _shown_level: int = -1
var _prompt: StringName = PROMPT_SELECT1
var _title_visible: bool = false
var _left_arrow: bool = false
var _right_arrow: bool = false
var _frame: int = 0
var _switch: int = -1
var _selector: StackSelector = null
var _scene: HighScoreScene = null

## Current [enum Operation].
var operation: int:
	get:
		return _operation
## Always [enum CameraMode] STATIC on this page (High_score_camera_operation_mode).
var camera_mode: int:
	get:
		return CameraMode.STATIC
## HSView_counter, an unsigned 32-bit count: the table's 120 ticks after entry, a level's 90.
var counter: int:
	get:
		return _counter
## HSView_automatic_counter: ticks waited at a toured level before it spins out.
var tour_wait: int:
	get:
		return _wait
## High_score_view_automatic_picked_flag: the tour has chosen its next level.
var picked: bool:
	get:
		return _picked
## The pending [enum Request]; the page has ended once it is not NONE.
var request: int:
	get:
		return _request
## True when the page was opened from the options page (From_options).
var from_options: bool:
	get:
		return _from_options
## True while touring after name entry (HSView_automatic_flag).
var automatic: bool:
	get:
		return _automatic
## The level stack while [member operation] is LEVEL_SELECT, otherwise null.
var selector: StackSelector:
	get:
		return _selector
## The scrolly table while [member operation] is SCROLLY, otherwise null.
var scene: HighScoreScene:
	get:
		return _scene
## The level whose three best rows are shown from spin-out until the spin back ends, or -1.
var shown_level: int:
	get:
		return _shown_level
## Image name of the prompt sprite: select1, select3 (BACK), select5 or skip_hi_score.
var prompt: StringName:
	get:
		return _prompt
## True when the prompt reads BACK (OPTION_TEXT_SELECT3).
var prompt_is_back: bool:
	get:
		return _prompt == PROMPT_SELECT3
## True when the stack's "select level" title is shown (hidden while touring).
var title_visible: bool:
	get:
		return _title_visible
## The left arrow (to the table) is shown: from options in the stack view.
var left_arrow_visible: bool:
	get:
		return _left_arrow
## The right arrow (to the stack) is shown: from options in the table view.
var right_arrow_visible: bool:
	get:
		return _right_arrow
## Select_bg_counter of the stack's checker background: cycles 0..23 by hand, 12 while touring.
var background_counter: int:
	get:
		return _background
## The viewport frame count of the last tick.
var frame: int:
	get:
		return _frame
## High_score_view_flyon_counter of the table, 0 in the stack view.
var fly_on: int:
	get:
		return _scene.fly_on if _scene != null else 0
## High_score_view_flyoff_counter of the table, 0 in the stack view.
var fly_off: int:
	get:
		return _scene.fly_off if _scene != null else 0


## A page over [param layout] and [param progress] showing [param main_rows] in the table.
## [param from_options] opens the stack by hand; [param automatic] tours after name entry; with
## neither the page opens on the table. [param new_main] is New_high_score and [param new_levels]
## New_high_scores by level id. [param first_time] is Sel_first_time (the stack prompt) and
## [param name_widths] each row's level-name image width.
static func create(layout: StackLayout, progress: LevelProgress, main_rows: Array[HighScoreRow],
		opened_from_options: bool, touring: bool, new_main: bool, new_levels: PackedByteArray,
		first_time: bool = true, name_widths: PackedInt32Array = PackedInt32Array()) -> HighScoreTour:
	var tour := HighScoreTour.new()
	tour._layout = layout
	tour._progress = progress
	tour._main_rows = main_rows.duplicate()
	tour._from_options = opened_from_options
	tour._automatic = touring
	tour._new_main = new_main
	tour._new_levels = new_levels.duplicate()
	tour._first_time = first_time
	tour._name_widths = name_widths.duplicate()
	tour._startup(Operation.LEVEL_SELECT if opened_from_options or touring else Operation.SCROLLY)
	return tour


## The arrows' colour component for viewport frame [param at_frame]: (count & 0xff) << 4 stored in
## a byte, so it ramps 0..0xf0 every 16 frames.
static func arrow_glow(at_frame: int) -> int:
	return ((at_frame & 0xff) << 4) & 0xff


## The prompt sprite's x for an image [param width] (te_w) wide: the table's sits 16 further left.
func prompt_x(width: int) -> int:
	var right: int = StackLayout.STATUS_END_X + StackLayout.STATUS_WIDTH
	return right - width - (16 if _operation == Operation.SCROLLY else 0)


## Advances one tick with [param buttons] (UP and DOWN held, the rest pressed) at [param water]'s
## frame count and returns the [enum EventKind] values raised.
func tick(buttons: OptionsMenu.Buttons, water: MenuWater) -> Array[int]:
	var events: Array[int] = []
	if _request != Request.NONE:
		return events
	_frame = water.frame_count
	_switch = -1
	if not _from_options and buttons.pressed & OptionsMenu.Buttons.BACK != 0:
		_request = Request.MAIN_MENU
		events.append(EventKind.BACK)
		if _scene != null:
			_scene.stop_flying()
	if _operation == Operation.SCROLLY:
		_scrolly_tick(buttons, water, events)
	elif _automatic:
		_automatic_tick(events)
	else:
		_manual_tick(buttons, events)
	if _switch >= 0:
		_automatic = false
		_request = Request.NONE
		events.erase(EventKind.BACK)
		_startup(_switch)
	return events


func _startup(next: int) -> void:
	_operation = next
	_counter = AFTER_INPUT_DURATION
	_scene = null
	_selector = null
	_picked = false
	_background = 0
	_shown_level = -1
	if next == Operation.SCROLLY:
		_scene = HighScoreScene.create(_main_rows)
		_prompt = PROMPT_SELECT3 if _from_options else PROMPT_SKIP
		_title_visible = false
	else:
		_selector = StackSelector.create(_layout, _progress, LEVEL_ORIGINAL1, _first_time, _name_widths, false)
		_prompt = PROMPT_SELECT1 if _first_time else PROMPT_SELECT5
		_title_visible = not _automatic
	_left_arrow = _from_options and next == Operation.LEVEL_SELECT
	_right_arrow = _from_options and next == Operation.SCROLLY


func _hide_arrows() -> void:
	_left_arrow = false
	_right_arrow = false


func _flag(level: int) -> int:
	return _new_levels[level] if level >= 0 and level < _new_levels.size() else 0


func _clear_flag(level: int) -> void:
	if level >= 0 and level < _new_levels.size():
		_new_levels[level] = 0


func _scrolly_tick(buttons: OptionsMenu.Buttons, water: MenuWater, events: Array[int]) -> void:
	events.append_array(_scene.tick(water, false))
	if _from_options:
		if buttons.pressed & OptionsMenu.Buttons.RIGHT != 0:
			events.append_array([EventKind.HOP, EventKind.SWITCHED])
			_switch = Operation.LEVEL_SELECT
			_hide_arrows()
		elif buttons.pressed & OptionsMenu.Buttons.BACK != 0:
			events.append_array([EventKind.CROAK, EventKind.BACK_TO_OPTIONS])
			_request = Request.OPTIONS
			_hide_arrows()
			_scene.stop_flying()
	else:
		if _counter == 0:
			_request = Request.MAIN_MENU
			events.append(EventKind.TIMEOUT)
			_scene.stop_flying()
		_counter = (_counter - 1) & COUNTER_MASK


func _reach_level(events: Array[int]) -> void:
	events.append_array([EventKind.CROAK, EventKind.SPIN_OUT])
	_selector.spin_out(true)
	_prompt = PROMPT_SKIP
	_shown_level = _selector.focused_level()
	_counter = LEVEL_DURATION


func _automatic_tick(events: Array[int]) -> void:
	_selector.update_slide()
	_background = BACKGROUND_PERIOD >> 1
	if _selector.mode == StackSelector.Mode.SELECTING:
		_prompt = PROMPT_SKIP
		if _flag(LEVEL_ORIGINAL1) == 1 or _flag(LEVEL_ORIGINAL_MULTI_PLAYER) == 1:
			_clear_flag(LEVEL_ORIGINAL1)
			_clear_flag(LEVEL_ORIGINAL_MULTI_PLAYER)
			_reach_level(events)
		elif not _picked:
			while true:
				if not _selector.find_target(1):
					if _new_main:
						events.append(EventKind.SWITCHED)
						_switch = Operation.SCROLLY
					else:
						events.append(EventKind.TIMEOUT)
						_request = Request.MAIN_MENU
					return
				var level: int = _selector.focused_level()
				var wanted: int = LevelProgress.LEVEL_JUNGLE1 if level == LevelProgress.LEVEL_JUNGLE2 else level
				if _flag(wanted) == 1:
					break
			_picked = true
		elif not _selector.creep_camera(CREEP_STEP):
			_wait += 1
			if _wait == TOUR_WAIT:
				_reach_level(events)
				_picked = false
				_wait = 0
	elif _selector.advance_spin():
		if _selector.mode == StackSelector.Mode.SELECTING:
			_prompt = PROMPT_SKIP
			_shown_level = -1
	else:
		if _counter == 0:
			events.append_array([EventKind.CROAK, EventKind.SPIN_IN])
			_selector.spin_in()
		_counter = (_counter - 1) & COUNTER_MASK


func _manual_tick(buttons: OptionsMenu.Buttons, events: Array[int]) -> void:
	_selector.update_slide()
	_background = (_background + 1) % BACKGROUND_PERIOD
	var down: bool = buttons.held & OptionsMenu.Buttons.DOWN != 0
	var up: bool = buttons.held & OptionsMenu.Buttons.UP != 0
	if _selector.mode == StackSelector.Mode.SELECTING:
		var reached: bool = _selector.advance_camera(false)
		if _selector.camera_flag & StackSelector.CAMERA_STATIONARY != 0:
			if down or up:
				events.append(EventKind.HOP)
				if _selector.start_travel(1 if down else -1):
					reached = false
				else:
					events.append(EventKind.CROAK)
			elif buttons.pressed & OptionsMenu.Buttons.LEFT != 0:
				events.append_array([EventKind.HOP, EventKind.SWITCHED])
				_switch = Operation.SCROLLY
				_hide_arrows()
			elif buttons.pressed & OptionsMenu.Buttons.FIRE != 0:
				if _selector.current_z(_selector.focused_row) == StackSelector.SLIDE_DIST:
					events.append_array([EventKind.CROAK, EventKind.SPIN_OUT])
					_selector.spin_out()
					_prompt = PROMPT_SELECT3
					_shown_level = _selector.focused_level()
					return
			elif buttons.pressed & OptionsMenu.Buttons.BACK != 0:
				events.append_array([EventKind.CROAK, EventKind.BACK_TO_OPTIONS])
				_request = Request.OPTIONS
				_hide_arrows()
		_selector.continue_travel(down, up, reached)
	elif _selector.advance_spin():
		if _selector.mode == StackSelector.Mode.SELECTING:
			_prompt = PROMPT_SELECT1
			_shown_level = -1
	elif buttons.pressed & OptionsMenu.Buttons.BACK != 0:
		events.append_array([EventKind.CROAK, EventKind.SPIN_IN])
		_selector.spin_in()
	elif buttons.pressed & OptionsMenu.Buttons.LEFT != 0:
		events.append_array([EventKind.HOP, EventKind.SWITCHED])
		_switch = Operation.SCROLLY
		_hide_arrows()
