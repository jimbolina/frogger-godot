class_name HighScoreScene
extends RefCounted
## The scrolly high-score set on the front-end water: ten rank turtles, thirty initials pads, ten
## score logs, five static extras and the frog hopping up and down the turtles
## (HSInitialiseScrollyHighScore, HSUpdateScrollyHighScores, HSUpdateFrog and HSUpdateFlying,
## HSView.c:2283-2499, 2563-2641 and 2819-2993).
##
## Matrices are 12 integers as in [OptionsScene]: a row-major 4.12 rotation then the translation,
## in source units with Y down. Rank 1 is the top table row (largest z); turtle i shows rank 10 - i
## and the frog starts on turtle 0, nearest the camera. Every [method tick] runs HSUpdateFlying,
## sets every model onto the water and, with the scrolly camera, moves the frog and writes the
## camera's follow offsets. With the static camera the frog and its shadow are hidden and still.
## The frog's translation is initialised from its start position where the source leaves it unset
## until the first frog update, and the log matrices start as the identity where HSView.c:2439
## initialises an initials matrix instead.

enum Direction { NORTH, SOUTH }

const ROW_COUNT: int = 10
const PAD_COUNT: int = 30
const PADS_PER_ROW: int = 3
const TURTLE_X: int = -0x480
const PAD_X: int = -0x300
const LOG_X: int = 0x280
const ROW_Z0: int = -9 * 0x80
const ROW_PITCH: int = 0x100
const MODEL_SCALE: int = 0x1300
const LOG_SCALE_X: int = 0x1200
const LOG_TILT: int = 0x500
const FROG_SCALE: int = 0x1400
const FROG_RAISE: int = -64
## FROG_CROAK_MIN_SCALE on the throat part.
const THROAT_SCALE: int = 0x200
## LoadOptionsResources rotates the turtle model's vertices by this angle about Y (tempopt.c:6292-6298).
const TURTLE_MODEL_ROTATION_Y: int = 0xc00
const TURTLE_ANIMATED_POLYS: int = 12
const LOG_DIGITS: int = 8
const BLANK_DIGIT_CEL: int = 10
const FROG_WAIT_TIME: int = 18
const FROG_JUMP_TIME: int = 12
const FLY_TIME: int = 10
const SPLASH_SCALE: int = 10 << 16
const SPLASH_OT_OFFSET: int = -0x8
const CAMERA_FOLLOW_OFFSET: int = 1152
const MAIN_CAMERA_SOURCE: Vector3i = Vector3i(0, -2500, -1280)
const MAIN_CAMERA_TARGET: Vector3i = Vector3i(0, 1024, -800)
const SHADOW_PHASES: int = 6
const ONE: int = 0x1000
const TURTLE_MODEL: String = "OPT_TURTLE.XMR"
const LOG_MODEL: String = "HI_LOG.XMR"
## High_score_input_letters_resource_id by FrogLord name.
const LETTER_MODELS: PackedStringArray = [
	"HI_A.XMR", "HI_B.XMR", "HI_C.XMR", "HI_D.XMR", "HI_E.XMR", "HI_F.XMR", "HI_G.XMR", "HI_H.XMR",
	"HI_I.XMR", "HI_J.XMR", "HI_K.XMR", "HI_L.XMR", "HI_M.XMR", "HI_N.XMR", "HI_O.XMR", "HI_P.XMR",
	"HI_Q.XMR", "HI_R.XMR", "HI_S.XMR", "HI_T.XMR", "HI_U.XMR", "HI_V.XMR", "HI_W.XMR", "HI_X.XMR",
	"HI_Y.XMR", "HI_Z.XMR", "HI_DOT.XMR", "OPT_LILLYPAD_BLANK.XMR", "HI_BACK.XMR", "HI_END.XMR",
]
const DOT_LETTER: int = 26
const BLANK_LETTER: int = 27
## High_score_view_extras_resource_id and High_score_view_extras_coords (x, z).
const EXTRA_MODELS: PackedStringArray = [
	"OPT_STAT_BULLRUSH.XMR", "OPT_STAT_LILLY.XMR", "OPT_STAT_LILLY.XMR", "OPT_STAT_LILLY.XMR",
	"OPT_STAT_BULLRUSH.XMR",
]
const EXTRA_COORDS: Array[Vector2i] = [Vector2i(-0x400, -0x580), Vector2i(-0x280, -0x700),
	Vector2i(0x300, -0x600), Vector2i(-0x240, 0x700), Vector2i(0x200, 0x740)]
const ACTION_WAIT2: StringName = &"GEN_FROG_WAIT2"
const ACTION_WAIT1: StringName = &"GEN_FROG_WAIT1"
const ACTION_HOP: StringName = &"GEN_FROG_HOP"

## One matrix per rank turtle, index 0 nearest the camera.
var turtles: Array[PackedInt32Array] = []
## One matrix per initials pad: pad i is rank i / 3, column i % 3.
var pads: Array[PackedInt32Array] = []
## Index into [constant LETTER_MODELS] of each pad.
var pad_letters: PackedInt32Array = PackedInt32Array()
## One matrix per score log, index = rank - 1.
var logs: Array[PackedInt32Array] = []
## The eight digit cels of each log (see [method digit_cels]).
var log_digits: Array[PackedInt32Array] = []
## One matrix per static extra, in [constant EXTRA_MODELS] order.
var extras: Array[PackedInt32Array] = []
## The frog's matrix (fr_lwtrans): its translation is 64 above [member frog_position].
var frog: PackedInt32Array = PackedInt32Array()
## The frog's position, 16.16 (fr_pos).
var frog_position: Vector3i = Vector3i.ZERO
## The turtle the frog is on or hopping to (fr_grid_z).
var frog_turtle: int = 0
## The [enum Direction] of the frog's next hop: north is up the turtles.
var frog_direction: int = Direction.NORTH
## True while hopping (FROG_MODE_JUMPING).
var frog_jumping: bool = false
## Wait or hop ticks left (fr_count).
var frog_count: int = FROG_WAIT_TIME
## This tick's hop parabola offset, 16.16; 0 while waiting.
var frog_lift: int = 0
## False with the static camera: the frog and its shadow are not drawn.
var frog_visible: bool = false
## Index of the frog's action in [constant FrogAnimationCatalog.ACTION_NAMES].
var frog_action: int = -1
## True when the last tick set the frog action.
var frog_action_set: bool = true
## Turtles a splash sprite was created on by the last tick.
var splashes: PackedInt32Array = PackedInt32Array()
## False while flying on: the jump shadow is hidden.
var shadow_visible: bool = false
## Jump shadow phase 0-5 of the last tick.
var shadow_phase: int = 0
## High_score_view_flyon_counter after this tick's HSUpdateFlying.
var fly_on: int = FLY_TIME
## High_score_view_flyoff_counter after this tick's HSUpdateFlying.
var fly_off: int = 0
## True when the last tick wrote the camera's follow offsets.
var camera_followed: bool = false
## Camera source offset z last written (ca_current_source_ofs.vz).
var camera_source_z: int = MAIN_CAMERA_SOURCE.z
## Camera target offset z last written (ca_current_target_ofs.vz).
var camera_target_z: int = MAIN_CAMERA_TARGET.z
## The viewport frame count of the last tick.
var frame: int = 0

var _target: Vector3i = Vector3i.ZERO
var _velocity: Vector3i = Vector3i.ZERO
var _line_y: int = 0


## The startup set for [param main_rows], the ten main table rows best first (missing rows are
## blank with score 0); everything waits at the fly-on height.
static func create(main_rows: Array[HighScoreRow]) -> HighScoreScene:
	var scene := HighScoreScene.new()
	for index: int in ROW_COUNT:
		scene.turtles.append(_startup(TURTLE_X, ROW_Z0 + index * ROW_PITCH))
	for index: int in PAD_COUNT:
		var rank: int = index / PADS_PER_ROW
		var column: int = index % PADS_PER_ROW
		scene.pads.append(_startup(PAD_X + column * ROW_PITCH, row_z(rank)))
		var initials: String = main_rows[rank].initials if rank < main_rows.size() else "   "
		scene.pad_letters.append(letter_index(initials.substr(column, 1)))
	for index: int in ROW_COUNT:
		scene.logs.append(_startup(LOG_X, row_z(index)))
		scene.log_digits.append(digit_cels(main_rows[index].score if index < main_rows.size() else 0))
	for at: Vector2i in EXTRA_COORDS:
		scene.extras.append(_startup(at.x, at.y))
	var start: PackedInt32Array = scene.turtles[0]
	scene.frog_position = Vector3i(start[9] << 16, start[10] << 16, start[11] << 16)
	scene.frog = _startup(start[9], start[11])
	scene._place_frog()
	scene.frog_action = OptionsScene.action_index(ACTION_WAIT2)
	return scene


## Table z of rank [param rank] (0 best): its pads and log share it.
static func row_z(rank: int) -> int:
	return ROW_Z0 + (ROW_COUNT - 1 - rank) * ROW_PITCH


## The animated-poly cel the turtle at [param index] shows: 9 - index, so turtle 0 reads 10.
static func turtle_cel(index: int) -> int:
	return ROW_COUNT - 1 - index


## The [constant LETTER_MODELS] index for [param character]: '.' the dot, ' ' the blank pad, 'A'
## onwards by code ('[' is the dot, as retail's tables spell it). Anything else falls back to
## the blank pad, where the source would read past the table.
static func letter_index(character: String) -> int:
	if character == ".":
		return DOT_LETTER
	if character == " " or character.length() != 1:
		return BLANK_LETTER
	var index: int = character.unicode_at(0) - "A".unicode_at(0)
	return index if index >= 0 and index < LETTER_MODELS.size() else BLANK_LETTER


## The eight log digit cels of [param score], most significant first: leading zeros show the
## blank cel 10 except the last digit. A score of 10^8 or more puts its quotient in the first cel.
static func digit_cels(score: int) -> PackedInt32Array:
	var cels := PackedInt32Array()
	var rest: int = score
	var shown: bool = false
	for place: int in LOG_DIGITS:
		var power: int = 1
		for _step: int in LOG_DIGITS - 1 - place:
			power *= 10
		var digit: int = rest / power
		rest -= digit * power
		if digit == 0 and not shown and place < LOG_DIGITS - 1:
			digit = BLANK_DIGIT_CEL
		else:
			shown = true
		cels.append(digit)
	return cels


## The 64 animated-poly cels of a log showing [param score] (High_score_log_animated_poly_indices).
static func log_poly_cels(score: int) -> PackedInt32Array:
	return digit_poly_cels(digit_cels(score))


## The 64 animated-poly cels of a log showing the eight [param digits] cels of [method digit_cels].
static func digit_poly_cels(digits: PackedInt32Array) -> PackedInt32Array:
	var cels := PackedInt32Array()
	cels.resize(OptionsScene.LOG_POLY_INDICES.size() * OptionsScene.LOG_POLYS_PER_STAGE)
	for place: int in mini(digits.size(), OptionsScene.LOG_POLY_INDICES.size()):
		for poly: int in OptionsScene.LOG_POLYS_PER_STAGE:
			cels[OptionsScene.LOG_POLY_INDICES[place] + poly] = digits[place]
	return cels


## The hop parabola offset (16.16) with [param count] hop ticks left.
static func jump_lift(count: int) -> int:
	var half: int = FROG_JUMP_TIME >> 1
	return -(8 << 16) * (half * half - (count - half) * (count - half))


## The logs' transform: scale 0x1200 in X and 0x1300 in Y and Z times the 0x500 tilt about X.
static func log_transform() -> PackedInt32Array:
	var cos_x: int = StackLayout.rcos(LOG_TILT)
	var sin_x: int = StackLayout.rsin(LOG_TILT)
	var tilt := PackedInt32Array([ONE, 0, 0, 0, cos_x, -sin_x, 0, sin_x, cos_x])
	return OptionsScene.multiply(OptionsScene.diagonal(LOG_SCALE_X, MODEL_SCALE, MODEL_SCALE), tilt)


## Starts flying everything off (the main menu's fly-off: the off counter set, the on counter cleared).
func start_fly_off() -> void:
	fly_off = FLY_TIME
	fly_on = 0


## Stops both fly counters (OptionsCameraSnapToMain and OptionsCameraSnapToOptions).
func stop_flying() -> void:
	fly_on = 0
	fly_off = 0


## Runs one tick at [param water]'s frame count. [param camera_scrolly] is the scrolly camera
## mode: the camera follows the frog and the frog hops. Returns [enum HighScoreTour.EventKind]
## values: LEAVE when the fly-off ends, HOP on take-off and SPLASH on landing.
func tick(water: MenuWater, camera_scrolly: bool) -> Array[int]:
	var events: Array[int] = []
	frame = water.frame_count
	splashes = PackedInt32Array()
	frog_action_set = false
	camera_followed = false
	if camera_scrolly and fly_off == 0 and fly_on == 0:
		var follow: int = frog[11] + CAMERA_FOLLOW_OFFSET
		camera_source_z = follow + MAIN_CAMERA_SOURCE.z
		camera_target_z = follow + MAIN_CAMERA_TARGET.z
		camera_followed = true
	if fly_on != 0:
		fly_on -= 1
	if fly_off != 0:
		fly_off -= 1
		if fly_off == 0:
			events.append(HighScoreTour.EventKind.LEAVE)
	var scale: PackedInt32Array = OptionsScene.diagonal(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	for group: Array[PackedInt32Array] in [pads, turtles, extras]:
		for matrix: PackedInt32Array in group:
			OptionsScene.project(matrix, scale, frame, fly_on, fly_off)
	var tilted: PackedInt32Array = log_transform()
	for matrix: PackedInt32Array in logs:
		OptionsScene.project(matrix, tilted, frame, fly_on, fly_off)
	frog_visible = camera_scrolly
	if camera_scrolly:
		_update_frog(events)
	return events


func _update_frog(events: Array[int]) -> void:
	if not frog_jumping:
		frog_lift = 0
		frog_position.y = turtles[frog_turtle][10] << 16
		frog_count -= 1
		if frog_count == 0:
			if frog_turtle == ROW_COUNT - 1:
				frog_direction = Direction.SOUTH
			elif frog_turtle == 0:
				frog_direction = Direction.NORTH
			frog_turtle += 1 if frog_direction == Direction.NORTH else -1
			frog_jumping = true
			frog_count = FROG_JUMP_TIME
			var pad: PackedInt32Array = turtles[frog_turtle]
			_target = Vector3i(pad[9], pad[10], pad[11])
			_line_y = frog_position.y
			_velocity = Vector3i(((_target.x << 16) - frog_position.x) / frog_count, 0,
				((_target.z << 16) - frog_position.z) / frog_count)
			_set_action(ACTION_HOP)
			events.append(HighScoreTour.EventKind.HOP)
		var rotation: PackedInt32Array = OptionsScene.multiply(OptionsScene.diagonal(FROG_SCALE, FROG_SCALE, FROG_SCALE),
			turtles[frog_turtle])
		if frog_direction == Direction.SOUTH:
			rotation = OptionsScene.multiply(OptionsScene.diagonal(-ONE, ONE, -ONE), rotation)
		for index: int in 9:
			frog[index] = rotation[index]
	else:
		_target.y = turtles[frog_turtle][10]
		_line_y += ((_target.y << 16) - _line_y) / frog_count
		frog_lift = jump_lift(frog_count)
		frog_position.y = _line_y + frog_lift
		frog_position.x += _velocity.x
		frog_position.z += _velocity.z
		frog_count -= 1
		if frog_count == 0:
			frog_position = Vector3i(_target.x << 16, _target.y << 16, _target.z << 16)
			frog_jumping = false
			frog_count = FROG_WAIT_TIME
			_set_action(ACTION_WAIT1)
			splashes.append(frog_turtle)
			events.append(HighScoreTour.EventKind.SPLASH)
	if fly_off != 0:
		frog_position.x -= OptionsMenu.FLY_OFF_SPEED << 16
		_target.x -= OptionsMenu.FLY_OFF_SPEED
	_place_frog()
	shadow_visible = fly_on == 0
	shadow_phase = 0
	if frog_jumping:
		shadow_phase = clampi(((FROG_JUMP_TIME - frog_count) * SHADOW_PHASES) / FROG_JUMP_TIME, 0, SHADOW_PHASES - 1)


func _place_frog() -> void:
	frog[9] = frog_position.x >> 16
	frog[10] = (frog_position.y >> 16) + FROG_RAISE
	frog[11] = frog_position.z >> 16


func _set_action(action_name: StringName) -> void:
	frog_action = OptionsScene.action_index(action_name)
	frog_action_set = true


static func _startup(x: int, z: int) -> PackedInt32Array:
	return PackedInt32Array([ONE, 0, 0, 0, ONE, 0, 0, 0, ONE, x, OptionsMenu.FLY_ON_HEIGHT, z])
