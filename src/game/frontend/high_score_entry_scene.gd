class_name HighScoreEntryScene
extends RefCounted
## Where the name-entry page's letter pads, initials pads, extras, frog and frog shadow sit on the
## front-end water, tick by tick (HighScoreInputUpdate and HSInputUpdateFrog, hsinput.c:436-507
## and 1313-1608; HSProjectMatricesOntoWaterSurface, HSView.c:2760-2800).
##
## Matrices are 12 integers: a row-major 4.12 rotation then the translation, in source units with
## Y down. Each [method step] runs after [method HighScoreEntry.tick] with that tick's events and
## the options viewport frame count. The letter pads and extras are set onto the water surface
## under scale 0x1300 with both fly counters 0 (no page before this one leaves them running);
## the initials pads take the scale alone at the surface height, turned about local Z by
## [member HighScoreEntry.pad_turn]. The frog then sits on or hops between pads as
## HSInputUpdateFrog moves it, its rotation taken from the pad it stands on or takes off for.

const PAD_SCALE: int = 0x1300
const FROG_SCALE: int = 0x1400
const ONE: int = 0x1000
## Quarter turn per [member HighScoreEntry.facing] step about Y.
const FACING_ANGLE: int = 0x400
## Landing splash 3D sprite: scale 10 << 16 in the XZ plane at OT offset -8.
const SPRITE_SCALE: int = 10 << 16
const SPLASH_OT_OFFSET: int = -0x8
## Frog flipbook actions by FrogLord name (GENM_FROG_*), played at update period 2, one shot.
const ACTION_SIT: StringName = &"GENM_FROG_SIT"
const ACTION_HOP: StringName = &"GENM_FROG_HOP"
const FROG_UPDATE_PERIOD: int = 2
## Jump shadow phases (Frog_jump_shadow_*: six entries).
const SHADOW_PHASES: int = 6

## One matrix per letter pad 0..29.
var pads: Array[PackedInt32Array] = []
## One matrix per initials pad 0..2.
var initials: Array[PackedInt32Array] = []
## One matrix per static extra, in [constant HighScoreEntry.EXTRA_MODELS] order.
var extras: Array[PackedInt32Array] = []
## The frog's matrix (fr_lwtrans).
var frog: PackedInt32Array = PackedInt32Array()
## The frog's position, 16.16 (fr_pos).
var frog_position: Vector3i = Vector3i.ZERO
## The frog's flipbook action name.
var frog_action: StringName = ACTION_SIT
## True when the last tick set the frog action (restarting it at cel 0).
var frog_action_set: bool = true
## False once END hid the frog for its poly-piece pop.
var frog_visible: bool = true
## True on the tick END created the pop explosion particle generator at the frog.
var explosion: bool = false
## Pad indices a splash sprite was created on by the last tick.
var splashes: PackedInt32Array = PackedInt32Array()
## The jump shadow phase 0-5 of the last tick.
var shadow_phase: int = 0
## False once END hid the shadow.
var shadow_visible: bool = true
## The viewport frame count of the last tick.
var frame: int = 0

var _cell: int = 0
var _jumping: bool = false
var _count: int = 0
var _target: Vector3i = Vector3i.ZERO
var _velocity: Vector3i = Vector3i.ZERO
var _line_y: int = 0


## The startup layout for [param entry]: every model at y 0 with the identity rotation until the
## first tick sets it onto the water.
static func create(entry: HighScoreEntry) -> HighScoreEntryScene:
	var scene := HighScoreEntryScene.new()
	for index: int in HighScoreEntry.PAD_COUNT:
		scene.pads.append(_startup(HighScoreEntry.pad_position(index)))
	for index: int in HighScoreEntry.INITIALS_COUNT:
		scene.initials.append(_startup(HighScoreEntry.initials_pad_position(index)))
	for index: int in HighScoreEntry.EXTRA_COORDS.size():
		scene.extras.append(_startup(HighScoreEntry.extra_position(index)))
	scene._cell = entry.cell
	var at: Vector3i = HighScoreEntry.pad_position(entry.cell)
	scene.frog_position = Vector3i(at.x << 16, 0, at.z << 16)
	scene.frog = _startup(at)
	return scene


## The rotation about local Z by [param angle] (MRRot_matrix_Z).
static func turn_z(angle: int) -> PackedInt32Array:
	var cos_z: int = StackLayout.rcos(angle)
	var sin_z: int = StackLayout.rsin(angle)
	return PackedInt32Array([cos_z, sin_z, 0, -sin_z, cos_z, 0, 0, 0, ONE])


## The rotation about Y for [param facing] (MRRot_matrix_Y at facing * 0x400).
static func turn_y(facing: int) -> PackedInt32Array:
	var cos_y: int = StackLayout.rcos(facing * FACING_ANGLE)
	var sin_y: int = StackLayout.rsin(facing * FACING_ANGLE)
	return PackedInt32Array([cos_y, 0, sin_y, 0, ONE, 0, -sin_y, 0, cos_y])


## Runs one tick after [param entry] ticked, raising [param events], while the options viewport
## frame count was [param at_frame].
func step(entry: HighScoreEntry, events: Array[int], at_frame: int) -> void:
	frame = at_frame
	splashes = PackedInt32Array()
	frog_action_set = false
	explosion = false
	var scale: PackedInt32Array = OptionsScene.diagonal(PAD_SCALE, PAD_SCALE, PAD_SCALE)
	for matrix: PackedInt32Array in pads:
		OptionsScene.project(matrix, scale, frame, 0, 0)
	var turns: PackedInt32Array = entry.pad_turn
	for index: int in initials.size():
		var matrix: PackedInt32Array = initials[index]
		var rotation: PackedInt32Array = scale
		if turns[index] != 0:
			rotation = OptionsScene.multiply(turn_z(turns[index]), scale)
		for item: int in 9:
			matrix[item] = rotation[item]
		matrix[10] = OptionsScene.surface_height(matrix[9], matrix[11], frame)
	for matrix: PackedInt32Array in extras:
		OptionsScene.project(matrix, scale, frame, 0, 0)
	if _jumping:
		_step_jump()
	elif frog_visible:
		_step_stationary(entry, events)
	frog[9] = frog_position.x >> 16
	frog[10] = frog_position.y >> 16
	frog[11] = frog_position.z >> 16
	shadow_phase = 0
	if _jumping:
		var phase: int = ((HighScoreEntry.FROG_JUMP_TIME - _count) * SHADOW_PHASES) / HighScoreEntry.FROG_JUMP_TIME
		shadow_phase = clampi(phase, 0, SHADOW_PHASES - 1)


## The frog shadow's four corners for corner [param offsets] (sh_offsets): the frog matrix applied
## to each offset, set onto the water.
func shadow_corners(offsets: Array[Vector3i]) -> Array[Vector3i]:
	var corners: Array[Vector3i] = []
	for offset: Vector3i in offsets:
		var corner := Vector3i.ZERO
		for row: int in 3:
			corner[row] = ((frog[row * 3] * offset.x + frog[row * 3 + 1] * offset.y + frog[row * 3 + 2] * offset.z) >> 12) + frog[9 + row]
		corner.y = OptionsScene.surface_height(corner.x, corner.z, frame)
		corners.append(corner)
	return corners


func _step_stationary(entry: HighScoreEntry, events: Array[int]) -> void:
	frog_position.y = pads[_cell][10] << 16
	if events.has(HighScoreEntry.EventKind.HOP):
		_cell = entry.cell
		var pad: PackedInt32Array = pads[_cell]
		_target = Vector3i(pad[9], pad[10], pad[11])
		_line_y = frog_position.y
		_jumping = true
		_count = HighScoreEntry.FROG_JUMP_TIME
		_velocity = Vector3i(_cdiv((_target.x << 16) - frog_position.x, _count), 0,
			_cdiv((_target.z << 16) - frog_position.z, _count))
		_set_action(ACTION_HOP)
	var rotation: PackedInt32Array = OptionsScene.multiply(OptionsScene.diagonal(FROG_SCALE, FROG_SCALE, FROG_SCALE), pads[_cell])
	rotation = OptionsScene.multiply(turn_y(entry.facing), rotation)
	for index: int in 9:
		frog[index] = rotation[index]
	if events.has(HighScoreEntry.EventKind.END):
		frog_visible = false
		shadow_visible = false
		explosion = true


func _step_jump() -> void:
	_target.y = pads[_cell][10]
	_line_y += _cdiv((_target.y << 16) - _line_y, _count)
	var half: int = HighScoreEntry.FROG_JUMP_TIME >> 1
	var lift: int = -(8 << 16) * (half * half - (_count - half) * (_count - half))
	frog_position.y = _line_y + lift
	frog_position.x += _velocity.x
	frog_position.z += _velocity.z
	_count -= 1
	if _count == 0:
		frog_position = Vector3i(_target.x << 16, _target.y << 16, _target.z << 16)
		_jumping = false
		splashes.append(_cell)
		_set_action(ACTION_SIT)


func _set_action(action_name: StringName) -> void:
	frog_action = action_name
	frog_action_set = true


static func _startup(at: Vector3i) -> PackedInt32Array:
	return PackedInt32Array([ONE, 0, 0, 0, ONE, 0, 0, 0, ONE, at.x, 0, at.z])


static func _cdiv(value: int, divisor: int) -> int:
	var quotient: int = absi(value) / absi(divisor)
	return quotient if (value < 0) == (divisor < 0) else -quotient
