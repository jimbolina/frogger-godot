class_name HighScoreEntry
extends RefCounted
## The high-score name-entry page's 30 Hz tick machine for one frog (HighScoreInputStartup,
## HighScoreInputUpdate and HSInputUpdateFrog, hsinput.c:178-545 and 1313-1608).
##
## The frog hops over a 10 by 3 grid of letter pads; fire on a pad enters its letter, the dot or a
## space into the next of three initials, rubs the last one out (BACK) or ends entry (END, the frog
## explodes). Each accepted change flips one of the three initials pads about its local Z axis,
## swapping its model half-way. Once the frog is stunned and its pop has finished the page raises
## ENTERED and requests the high-score view. There is no cancel, timeout or 2D text. State is
## integer and source-scaled; [HighScoreEntryScene] places it on the water.

## Controls of one tick as a bitmask: the directions are held this tick, FIRE (FR_GO, FRR_BLUE or
## FRR_START) is newly pressed this tick.
enum Buttons { UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8, FIRE = 16 }
## The frog's mode: ACTIVE is FROG_MODE_STATIONARY.
enum Mode { ACTIVE, JUMPING, STUNNED }
## HOP and SPLASH play GEN_FROG_HOP and GEN_SPLASH01; LETTER, RUB and END play GEN_FROG_CROAK,
## GEN_FROG_FLY_GULP and GEN_FROG_EXPLODE; ENTERED asks for the initials to be inserted;
## NO_HIGH_SCORE and GAME_QUIT are the startup bails.
enum EventKind { HOP, SPLASH, LETTER, RUB, END, ENTERED, NO_HIGH_SCORE, GAME_QUIT }
## VIEW is OPTIONS_PAGE_HIGH_SCORE_VIEW in automatic, LEVEL_SELECT, STATIC mode with From_options
## FALSE; MAIN_MENU is OPTIONS_PAGE_MAIN_OPTIONS.
enum Request { NONE, VIEW, MAIN_MENU }
## FROG_DIRECTION_* values of [member facing].
enum Facing { NORTH, EAST, SOUTH, WEST }

const GRID_COLUMNS: int = 10
const GRID_ROWS: int = 3
const PAD_COUNT: int = 30
const LETTER_COUNT: int = 26
const PAD_DOT: int = 26
const PAD_SPACE: int = 27
const PAD_RUB: int = 28
const PAD_END: int = 29
const PAD_PITCH: int = 0x100
const PAD_X_ORIGIN: int = -0x480
const PAD_TOP_ROW: int = 3
const INITIALS_COUNT: int = 3
const INITIALS_X_ORIGIN: int = -0x100
const INITIALS_Z_ORIGIN: int = -0x80
const INITIALS_Z_PITCH: int = -0x100
## Pad shown by [member pad_letter] for a blank initials pad (OPT_LILLYPAD_BLANK.XMR).
const BLANK_PAD: int = -1
const FROG_JUMP_TIME: int = 6
const FLIP_STEP: int = 0x100
const FLIP_SWAP_ANGLE: int = 0x500
const FLIP_RESUME_ANGLE: int = -0x300
## FROG_POLY_PIECE_POP_DURATION.
const POP_DURATION: int = 32
const PLAYER: int = 0
const START_GRID: Vector2i = Vector2i(4 + (PLAYER & 1), 1 + (PLAYER >> 1))
const START_FACING: int = (PLAYER & 2) + 1
const CAMERA_PERSPECTIVE: int = 0x100
const CAMERA_SOURCE: Vector3i = Vector3i(0, -2400, -256)
const CAMERA_TARGET: Vector3i = Vector3i(0, 1024, 0)
## Model of each pad, High_score_input_letters_resource_id by FrogLord name.
const PAD_MODELS: PackedStringArray = [
	"HI_A.XMR", "HI_B.XMR", "HI_C.XMR", "HI_D.XMR", "HI_E.XMR", "HI_F.XMR", "HI_G.XMR", "HI_H.XMR",
	"HI_I.XMR", "HI_J.XMR", "HI_K.XMR", "HI_L.XMR", "HI_M.XMR", "HI_N.XMR", "HI_O.XMR", "HI_P.XMR",
	"HI_Q.XMR", "HI_R.XMR", "HI_S.XMR", "HI_T.XMR", "HI_U.XMR", "HI_V.XMR", "HI_W.XMR", "HI_X.XMR",
	"HI_Y.XMR", "HI_Z.XMR", "HI_DOT.XMR", "OPT_LILLYPAD_BLANK.XMR", "HI_BACK.XMR", "HI_END.XMR",
]
const BLANK_MODEL: String = "OPT_LILLYPAD_BLANK.XMR"
## High_score_input_extras_resource_id and High_score_input_extras_coords (x, z).
const EXTRA_MODELS: PackedStringArray = [
	"OPT_STAT_BULLRUSH.XMR", "OPT_STAT_LILLY.XMR", "OPT_STAT_LILLY.XMR", "OPT_STAT_LILLY.XMR",
	"OPT_STAT_BULLRUSH.XMR", "OPT_STAT_BULLRUSH.XMR",
]
const EXTRA_COORDS: Array[Vector2i] = [Vector2i(-0x400, -0x040), Vector2i(-0x280, -0x200),
	Vector2i(0x480, -0x240), Vector2i(0x400, -0x080), Vector2i(0x240, -0x300), Vector2i(-0x300, -0x380)]
## Retail PC sound ids and FrogLord names: retail compiled the PSX arm (froggy KEY_FACTS ruling R11).
const SOUND_LETTER: StringName = &"GEN_FROG_CROAK"
const SOUND_RUB: StringName = &"GEN_FROG_FLY_GULP"
const SOUND_END: StringName = &"GEN_FROG_EXPLODE"
const SOUND_HOP: StringName = &"GEN_FROG_HOP"
const SOUND_SPLASH: StringName = &"GEN_SPLASH01"
const SOUND_LETTER_ID: int = 3
const SOUND_RUB_ID: int = 5
const SOUND_END_ID: int = 17

var _grid: Vector2i = START_GRID
var _facing: int = START_FACING
var _mode: int = Mode.ACTIVE
var _count: int = 0
var _lift: int = 0
var _position: int = 0
var _initials: PackedStringArray = [" ", " ", " "]
var _pad_angle: PackedInt32Array = PackedInt32Array([0, 0, 0])
var _pad_turn: PackedInt32Array = PackedInt32Array([0, 0, 0])
var _pad_letter: PackedInt32Array = PackedInt32Array([BLANK_PAD, BLANK_PAD, BLANK_PAD])
var _flip_pad: int = -1
var _flip_letter: int = BLANK_PAD
var _pop_timer: int = 0
var _request: int = Request.NONE
var _startup_events: Array[int] = []
var _blocked: PackedInt32Array = PackedInt32Array()

## The frog's pad, fr_grid_z * 10 + fr_grid_x: the pad it is on or hopping to.
var cell: int:
	get:
		return _grid.y * GRID_COLUMNS + _grid.x
## Column 0..9 (fr_grid_x).
var grid_x: int:
	get:
		return _grid.x
## Row 0..2 (fr_grid_z), 0 the A-J row.
var grid_z: int:
	get:
		return _grid.y
## The [enum Facing] of the frog (fr_direction).
var facing: int:
	get:
		return _facing
## The frog's [enum Mode].
var mode: int:
	get:
		return _mode
## Hop ticks left, FROG_JUMP_TIME down to 1 while hopping, 0 when landed (fr_count).
var jump_count: int:
	get:
		return _count
## This tick's hop parabola height above the straight line, 0 when stationary or landed.
var jump_lift: int:
	get:
		return _lift
## Initials entered, 0..3 (High_score_input_initial_pos).
var position: int:
	get:
		return _position
## The three initials, unentered ones a space.
var initials: String:
	get:
		return "".join(_initials)
## hs_angle of each initials pad after this tick, 0 unless that pad is flipping.
var pad_angle: PackedInt32Array:
	get:
		return _pad_angle.duplicate()
## The rotation about local Z each initials pad is drawn with this tick: hs_angle as the previous
## tick left it while that pad was flipping, otherwise 0.
var pad_turn: PackedInt32Array:
	get:
		return _pad_turn.duplicate()
## The pad index 0..29 whose model each initials pad shows, or BLANK_PAD; it changes at the swap.
var pad_letter: PackedInt32Array:
	get:
		return _pad_letter.duplicate()
## Poly-piece pop ticks left after END (pp_timer).
var pop_timer: int:
	get:
		return _pop_timer
## The [enum Request] made; the page leaves once it is not NONE.
var request: int:
	get:
		return _request
## True once a request is made; further ticks do nothing.
var finished: bool:
	get:
		return _request != Request.NONE


## The page after HighScoreInputStartup: requests MAIN_MENU at once when the game was quit
## ([param quit]) or the frog has no score to enter ([param qualifies] false), otherwise the frog
## sits on 'O' facing east with three blank initials.
static func create(qualifies: bool, quit: bool) -> HighScoreEntry:
	var entry := HighScoreEntry.new()
	if quit:
		entry._request = Request.MAIN_MENU
		entry._startup_events.append(EventKind.GAME_QUIT)
	elif not qualifies:
		entry._request = Request.MAIN_MENU
		entry._startup_events.append(EventKind.NO_HIGH_SCORE)
	return entry


## Position (x, 0, z) of letter pad [param index] 0..29.
static func pad_position(index: int) -> Vector3i:
	return Vector3i((index % GRID_COLUMNS) * PAD_PITCH + PAD_X_ORIGIN, 0, (PAD_TOP_ROW - index / GRID_COLUMNS) * PAD_PITCH)


## Position (x, 0, z) of initials pad [param index] 0..2 of [param player].
static func initials_pad_position(index: int, player: int = PLAYER) -> Vector3i:
	return Vector3i(index * PAD_PITCH + INITIALS_X_ORIGIN, 0, player * INITIALS_Z_PITCH + INITIALS_Z_ORIGIN)


## Position (x, 0, z) of static extra [param index] 0..5.
static func extra_position(index: int) -> Vector3i:
	return Vector3i(EXTRA_COORDS[index].x, 0, EXTRA_COORDS[index].y)


## The character pad [param index] enters, or "" for BACK and END.
static func pad_character(index: int) -> String:
	if index >= 0 and index < LETTER_COUNT:
		return String.chr(65 + index)
	if index == PAD_DOT:
		return "."
	if index == PAD_SPACE:
		return " "
	return ""


## The hop parabola height for [param count] hop ticks left before the decrement.
static func lift_for(count: int) -> int:
	var half: int = FROG_JUMP_TIME >> 1
	return -8 * (half * half - (count - half) * (count - half))


## The FrogLord model name pad [param index] (or BLANK_PAD) shows.
static func model_name(index: int) -> String:
	return PAD_MODELS[index] if index >= 0 and index < PAD_COUNT else BLANK_MODEL


## Events HighScoreInputStartup raised: empty, NO_HIGH_SCORE or GAME_QUIT.
func startup_events() -> Array[int]:
	return _startup_events.duplicate()


## True while initials pad [param index] is flipping (hs_new_mof set), which holds off fire.
func pad_flipping(index: int) -> bool:
	return _flip_pad == index


## Sets the pads other active frogs stand on; a hop onto one is refused.
func set_blocked_cells(cells: PackedInt32Array) -> void:
	_blocked = cells.duplicate()


## Advances one tick with [param buttons] (a [enum Buttons] mask) and returns the
## [enum EventKind] values it raised, in order.
func tick(buttons: int) -> Array[int]:
	var events: Array[int] = []
	if _request != Request.NONE:
		return events
	for index: int in INITIALS_COUNT:
		_pad_turn[index] = _pad_angle[index] if _flip_pad == index else 0
	match _mode:
		Mode.ACTIVE:
			_update_active(buttons, events)
		Mode.JUMPING:
			_update_jumping(events)
	if _pop_timer > 0:
		_pop_timer -= 1
	_update_flip()
	if _mode == Mode.STUNNED and _pop_timer == 0:
		_request = Request.VIEW
		events.append(EventKind.ENTERED)
	return events


func _update_active(buttons: int, events: Array[int]) -> void:
	_lift = 0
	var old: Vector2i = _grid
	var jump: bool = true
	if buttons & Buttons.UP != 0 and _grid.y > 0:
		_facing = Facing.NORTH
		_grid.y -= 1
	elif buttons & Buttons.DOWN != 0 and _grid.y < GRID_ROWS - 1:
		_facing = Facing.SOUTH
		_grid.y += 1
	elif buttons & Buttons.LEFT != 0 and _grid.x > 0:
		_facing = Facing.WEST
		_grid.x -= 1
	elif buttons & Buttons.RIGHT != 0 and _grid.x < GRID_COLUMNS - 1:
		_facing = Facing.EAST
		_grid.x += 1
	else:
		jump = false
		if _flip_pad < 0 and buttons & Buttons.FIRE != 0:
			_select(events)
	if not jump:
		return
	if _blocked.has(cell):
		_grid = old
		return
	_mode = Mode.JUMPING
	_count = FROG_JUMP_TIME
	events.append(EventKind.HOP)


func _update_jumping(events: Array[int]) -> void:
	_lift = lift_for(_count)
	_count -= 1
	if _count == 0:
		_lift = 0
		_mode = Mode.ACTIVE
		events.append(EventKind.SPLASH)


func _select(events: Array[int]) -> void:
	var letter: int = cell
	if letter == PAD_RUB:
		if _position > 0:
			events.append(EventKind.RUB)
			_position -= 1
			_initials[_position] = " "
			_start_flip(_position, BLANK_PAD)
	elif letter == PAD_END:
		events.append(EventKind.END)
		_pop_timer = POP_DURATION
		_mode = Mode.STUNNED
	elif _position < INITIALS_COUNT:
		events.append(EventKind.LETTER)
		_initials[_position] = pad_character(letter)
		_start_flip(_position, letter)
		_position += 1


func _start_flip(index: int, letter: int) -> void:
	_flip_pad = index
	_flip_letter = letter
	_pad_angle[index] = 0


func _update_flip() -> void:
	if _flip_pad < 0:
		return
	_pad_angle[_flip_pad] += FLIP_STEP
	if _pad_angle[_flip_pad] == FLIP_SWAP_ANGLE:
		_pad_letter[_flip_pad] = _flip_letter
		_pad_angle[_flip_pad] = FLIP_RESUME_ANGLE
	elif _pad_angle[_flip_pad] == 0:
		_flip_pad = -1
