class_name OptionsScene
extends RefCounted
## Where the options page's models, title sprites, frog and frog shadow sit on the front-end water,
## and which frog action plays, tick by tick (OptionsStartup, OptionsUpdate and OptionsUpdateFrog,
## tempopt.c:4295-5067; HSGetWaterSurfaceInfoFromXZ and HSProjectMatricesOntoWaterSurface,
## HSView.c:2697-2800).
##
## Matrices are 12 integers: a row-major 4.12 rotation then the translation, in source units with
## Y down. Every model starts at the fly-on height with the identity rotation. Each [method step]
## runs after [method OptionsMenu.step] with the same buttons, events and viewport frame count:
## every matrix is set onto the water surface under its model transform (falling 0xa0 a tick from
## the fly-on height while the fly-on counter runs, sliding 0x100 a tick away from x 0 while the
## fly-off counter runs), the prompt rises or falls, then the frog follows its lily or hop and the
## frog action is chosen as the C chooses it.
##
## The port's rows replace retail's four lilies (KEY_FACTS KF-110): each shown row has a lily at
## [method OptionsMenu.lily_z], each titled row a title, and each volume row a log on its lily and
## a volume model at x 0x400, 0xc0 nearer than the log, which puts the effects model of the
## four-row layout on retail's measured (0x400, -0x400). The five static extras follow retail's
## Options_extras_coords.

enum Direction { NORTH, SOUTH }
enum Extra { BULLRUSH, STATIC_LILY }

const LILY_SCALE: int = 0x1600
const LOG_SCALE: int = 0x1300
const TITLE_SCALE: Vector3i = Vector3i(0x1000, 0x1400, 0x1000)
const EXTRA_SCALE: int = 0x1800
const FROG_SCALE: int = 0x1400
const ONE: int = 0x1000
## Tilt of the volume models about X (rcos/rsin 0x400) and their Y spin per viewport frame.
const VOLUME_MODEL_TILT: int = 0x400
const VOLUME_MODEL_SPIN_SHIFT: int = 8
const VOLUME_MODEL_X: int = 0x400
## Volume model z relative to its log: retail's effects model (-0x400) less its log (-0x340).
const VOLUME_MODEL_Z_OFFSET: int = -0xc0
## Retail Options_extras_coords after the volume model: bullrush, three lilies, bullrush.
const EXTRA_KINDS: Array[Extra] = [Extra.BULLRUSH, Extra.STATIC_LILY, Extra.STATIC_LILY, Extra.STATIC_LILY, Extra.BULLRUSH]
const EXTRA_COORDS: Array[Vector2i] = [Vector2i(-0x680, 0x520), Vector2i(0x180, 0x680), Vector2i(0x580, 0x440),
	Vector2i(-0x600, 0x100), Vector2i(0x40, -0x580)]
## Title x is TITLE_X_BASE + (te_w >> 1) * TITLE_X_STEP.
const TITLE_X_BASE: int = -0x200
const TITLE_X_STEP: int = 8
## 3D sprite scale of the titles, their reflections and the landing splash (10 << 16).
const SPRITE_SCALE: int = 10 << 16
## Title image offset (sp_ofs_image.vy), reflection offset (vz), base colour and OT offsets.
const TITLE_RAISE: int = -0x40
const REFLECTION_OFFSET: int = 0x48
const REFLECTION_COLOUR: int = 0x40
const REFLECTION_OT_OFFSET: int = 0x10
const SPLASH_OT_OFFSET: int = -0x8
## Prompt sprite y is the display height less its te_h plus this start, moved PROMPT_STEP a tick.
const PROMPT_START: int = 76
## HIGH_SCORE_VIEW_WAVE_* sample step for the surface slopes.
const SLOPE_STEP: int = 0x100
## High_score_log_animated_poly_indices: first animated poly of log stages 1-8, eight polys each.
const LOG_POLY_INDICES: PackedInt32Array = [56, 48, 40, 8, 16, 24, 32, 0]
const LOG_POLYS_PER_STAGE: int = 8
## Frog actions by FrogLord name (GEN_FROG_*).
const ACTION_WAIT2: StringName = &"GEN_FROG_WAIT2"
const ACTION_WAIT1: StringName = &"GEN_FROG_WAIT1"
const ACTION_HOP: StringName = &"GEN_FROG_HOP"
const ACTION_OUCH: StringName = &"GEN_FROG_OUCH"
const ACTION_PANT2: StringName = &"GEN_FROG_PANT2"
const ACTION_DANCE: StringName = &"GEN_FROG_DANCE"
## Frog animation environment update period (ae_update_period).
const FROG_UPDATE_PERIOD: int = 2
## Jump shadow phases (Frog_jump_shadow_*: six entries).
const SHADOW_PHASES: int = 6

## Shown rows top to bottom, as [enum OptionsMenu.Row] values.
var rows: PackedInt32Array = PackedInt32Array()
## One matrix per shown row's lily.
var lilies: Array[PackedInt32Array] = []
## Row index of each title, top to bottom.
var title_rows: PackedInt32Array = PackedInt32Array()
## One matrix per title, shared by the title and its reflection.
var titles: Array[PackedInt32Array] = []
## Row index of each volume log, top to bottom.
var log_rows: PackedInt32Array = PackedInt32Array()
## One matrix per volume log.
var logs: Array[PackedInt32Array] = []
## One matrix per volume model, in [member log_rows] order.
var volume_models: Array[PackedInt32Array] = []
## One matrix per static extra, in [constant EXTRA_KINDS] order.
var extras: Array[PackedInt32Array] = []
## The frog's matrix (fr_lwtrans).
var frog: PackedInt32Array = PackedInt32Array()
## The frog's position, 16.16 (fr_pos).
var frog_position: Vector3i = Vector3i.ZERO
## The [enum Direction] the frog faces.
var frog_direction: int = Direction.SOUTH
## Index of the frog's action in [constant FrogAnimationCatalog.ACTION_NAMES].
var frog_action: int = -1
## True when the last tick set the frog action (MRAnimEnvSingleSetAction restarts it).
var frog_action_set: bool = true
## False while MR_ANIM_ENV_ONE_SHOT is set: the action holds its last frame.
var frog_looping: bool = false
## Lily indices a splash sprite was created on by the last tick.
var splashes: PackedInt32Array = PackedInt32Array()
## The jump shadow phase 0-5 of the last tick.
var shadow_phase: int = 0
## False while the fly-on counter hides the shadow.
var shadow_visible: bool = false
## True when the last tick set the shadow corners onto the water (no request was pending).
var shadow_on_water: bool = false
## The prompt sprite's y less the display height plus its te_h.
var prompt_offset: int = PROMPT_START
## The viewport frame count of the last tick.
var frame: int = 0

var _row: int = 0
var _jumping: bool = false
var _count: int = 0
var _target: Vector3i = Vector3i.ZERO
var _velocity: Vector3i = Vector3i.ZERO
var _line_y: int = 0
var _volumes: Dictionary[int, int] = {}
var _request: int = OptionsMenu.Request.NONE


## The startup layout of [param menu]'s rows; [param title_widths] holds each title image's te_w
## by [enum OptionsMenu.Row] (a missing width counts as 0).
static func create(menu: OptionsMenu, title_widths: Dictionary[int, int] = {}) -> OptionsScene:
	var scene := OptionsScene.new()
	scene.rows = menu.rows()
	for index: int in scene.rows.size():
		var kind: int = scene.rows[index]
		var z: int = OptionsMenu.lily_z(index)
		scene.lilies.append(_startup(OptionsMenu.LILY_X, z))
		if kind == OptionsMenu.Row.MUSIC or kind == OptionsMenu.Row.EFFECTS:
			scene.log_rows.append(index)
			scene.logs.append(_startup(OptionsMenu.LOG_X, z))
			scene.volume_models.append(_startup(VOLUME_MODEL_X, z + VOLUME_MODEL_Z_OFFSET))
		else:
			var width: int = title_widths[kind] if title_widths.has(kind) else 0
			scene.title_rows.append(index)
			scene.titles.append(_startup(title_x(width), z))
	for at: Vector2i in EXTRA_COORDS:
		scene.extras.append(_startup(at.x, at.y))
	scene._row = menu.row
	var lily: PackedInt32Array = scene.lilies[scene._row]
	scene.frog_position = Vector3i(lily[9] << 16, lily[10] << 16, lily[11] << 16)
	scene.frog = _startup(lily[9], lily[11])
	scene.frog_action = action_index(ACTION_WAIT2)
	scene._volumes = {OptionsMenu.Row.MUSIC: menu.music_volume, OptionsMenu.Row.EFFECTS: menu.effects_volume}
	scene._request = menu.request
	return scene


## Title x for an image [param width] (te_w) wide.
static func title_x(width: int) -> int:
	return TITLE_X_BASE + (width >> 1) * TITLE_X_STEP


## The index of the frog action called [param action_name], or -1.
static func action_index(action_name: StringName) -> int:
	return FrogAnimationCatalog.ACTION_NAMES.find(action_name)


## The animated poly cels of a volume log at step [param volume]: 64 cels in poly order.
static func log_poly_cels(volume: int) -> PackedInt32Array:
	var cels := PackedInt32Array()
	cels.resize(LOG_POLY_INDICES.size() * LOG_POLYS_PER_STAGE)
	var stages: PackedInt32Array = OptionsMenu.log_cels(volume)
	for stage: int in stages.size():
		for poly: int in LOG_POLYS_PER_STAGE:
			cels[LOG_POLY_INDICES[stage] + poly] = stages[stage]
	return cels


## Water height at ([param x], [param z]) for viewport frame [param at_frame].
static func surface_height(x: int, z: int, at_frame: int) -> int:
	var phases: Vector2i = _phases(x, z, at_frame, 0, 0)
	return _height(phases)


## The water height and normalised x and z slopes at ([param x], [param z]) for viewport frame
## [param at_frame]: [height, x slope, z slope] with the height in the first component's x.
static func surface(x: int, z: int, at_frame: int) -> Array[Vector3i]:
	var height: int = _height(_phases(x, z, at_frame, 0, 0))
	var x_rise: int = _height(_phases(x, z, at_frame, SLOPE_STEP, 0)) - height
	var z_rise: int = _height(_phases(x, z, at_frame, 0, SLOPE_STEP)) - height
	var result: Array[Vector3i] = [Vector3i(height, 0, 0), StackLayout.normalise(Vector3i(SLOPE_STEP, x_rise, 0)),
		StackLayout.normalise(Vector3i(0, z_rise, SLOPE_STEP))]
	return result


## Sets [param matrix] onto the water for viewport frame [param at_frame] under [param transform]
## (a row-major 4.12 rotation applied after the surface axes) with the fly counters [param fly_on]
## and [param fly_off] as HSUpdateFlying left them.
static func project(matrix: PackedInt32Array, transform: PackedInt32Array, at_frame: int, fly_on: int, fly_off: int) -> void:
	var info: Array[Vector3i] = surface(matrix[9], matrix[11], at_frame)
	var height: int = info[0].x
	if fly_on != 0:
		matrix[10] += OptionsMenu.FLY_ON_SPEED
		if matrix[10] >= height:
			matrix[10] = height
	if fly_off != 0:
		matrix[9] += -OptionsMenu.FLY_OFF_SPEED if matrix[9] < 0 else OptionsMenu.FLY_OFF_SPEED
	if fly_on == 0:
		matrix[10] = height
	var axis_x: Vector3i = info[1]
	var axis_y: Vector3i = StackLayout.normalise(StackLayout.outer12(info[2], axis_x))
	var axis_z: Vector3i = StackLayout.outer12(axis_x, axis_y)
	var axes := PackedInt32Array([axis_x.x, axis_y.x, axis_z.x, axis_x.y, axis_y.y, axis_z.y, axis_x.z, axis_y.z, axis_z.z])
	var rotation: PackedInt32Array = multiply(transform, axes)
	for index: int in 9:
		matrix[index] = rotation[index]


## Row-major 4.12 [param a] times [param b] (MulMatrix2: each sum shifted right by 12).
static func multiply(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(9)
	for row: int in 3:
		for column: int in 3:
			result[row * 3 + column] = (a[row * 3] * b[column] + a[row * 3 + 1] * b[3 + column] + a[row * 3 + 2] * b[6 + column]) >> 12
	return result


## A diagonal row-major 4.12 matrix.
static func diagonal(x: int, y: int, z: int) -> PackedInt32Array:
	return PackedInt32Array([x, 0, 0, 0, y, 0, 0, 0, z])


## The volume models' transform for viewport frame [param at_frame]: the Y spin times the X tilt.
static func volume_model_transform(at_frame: int) -> PackedInt32Array:
	var spin: int = at_frame << VOLUME_MODEL_SPIN_SHIFT
	var cos_y: int = StackLayout.rcos(spin)
	var sin_y: int = StackLayout.rsin(spin)
	var cos_x: int = StackLayout.rcos(VOLUME_MODEL_TILT)
	var sin_x: int = StackLayout.rsin(VOLUME_MODEL_TILT)
	var rotate_y := PackedInt32Array([cos_y, 0, sin_y, 0, ONE, 0, -sin_y, 0, cos_y])
	var rotate_x := PackedInt32Array([ONE, 0, 0, 0, cos_x, -sin_x, 0, sin_x, cos_x])
	return multiply(rotate_y, rotate_x)


## The volume logs' transform: scale 0x1300 times the half turn about X.
static func log_transform() -> PackedInt32Array:
	return multiply(diagonal(LOG_SCALE, LOG_SCALE, LOG_SCALE), diagonal(ONE, -ONE, -ONE))


## Runs one tick after [param menu] stepped with [param buttons], raising [param events], while the
## options viewport frame count was [param at_frame].
func step(menu: OptionsMenu, buttons: OptionsMenu.Buttons, events: PackedInt32Array, at_frame: int) -> void:
	frame = at_frame
	splashes = PackedInt32Array()
	frog_action_set = false
	var fly_on: int = menu.flying_on
	var fly_off: int = menu.flying_off
	var lily_transform: PackedInt32Array = diagonal(LILY_SCALE, LILY_SCALE, LILY_SCALE)
	for matrix: PackedInt32Array in lilies:
		project(matrix, lily_transform, frame, fly_on, fly_off)
	var logs_transform: PackedInt32Array = log_transform()
	for matrix: PackedInt32Array in logs:
		project(matrix, logs_transform, frame, fly_on, fly_off)
	var title_transform: PackedInt32Array = diagonal(TITLE_SCALE.x, TITLE_SCALE.y, TITLE_SCALE.z)
	for matrix: PackedInt32Array in titles:
		project(matrix, title_transform, frame, fly_on, fly_off)
	var extra_transform: PackedInt32Array = diagonal(EXTRA_SCALE, EXTRA_SCALE, EXTRA_SCALE)
	for matrix: PackedInt32Array in extras:
		project(matrix, extra_transform, frame, fly_on, fly_off)
	var volume_transform: PackedInt32Array = volume_model_transform(frame)
	for matrix: PackedInt32Array in volume_models:
		project(matrix, volume_transform, frame, fly_on, fly_off)
	if fly_on != 0:
		prompt_offset -= OptionsMenu.PROMPT_STEP
	if fly_off != 0:
		prompt_offset += OptionsMenu.PROMPT_STEP
	_step_frog(menu, events, fly_off)
	shadow_visible = fly_on == 0
	shadow_phase = 0
	if _jumping:
		shadow_phase = clampi(((OptionsMenu.FROG_JUMP_TIME - _count) * SHADOW_PHASES) / OptionsMenu.FROG_JUMP_TIME, 0, SHADOW_PHASES - 1)
	shadow_on_water = _request == OptionsMenu.Request.NONE
	_choose_actions(menu, buttons, events)
	_request = menu.request


## The frog shadow's four corners for corner [param offsets] (sh_offsets): the frog matrix applied
## to each offset, set onto the water when [member shadow_on_water].
func shadow_corners(offsets: Array[Vector3i]) -> Array[Vector3i]:
	var corners: Array[Vector3i] = []
	for offset: Vector3i in offsets:
		var corner := Vector3i.ZERO
		for row: int in 3:
			corner[row] = ((frog[row * 3] * offset.x + frog[row * 3 + 1] * offset.y + frog[row * 3 + 2] * offset.z) >> 12) + frog[9 + row]
		if shadow_on_water:
			corner.y = surface_height(corner.x, corner.z, frame)
		corners.append(corner)
	return corners


func _step_frog(menu: OptionsMenu, events: PackedInt32Array, fly_off: int) -> void:
	if not _jumping:
		frog_position.y = lilies[_row][10] << 16
		if events.has(OptionsMenu.EventKind.HOP):
			frog_direction = Direction.NORTH if menu.row < _row else Direction.SOUTH
			_row = menu.row
			_jumping = true
			_count = OptionsMenu.FROG_JUMP_TIME
			var lily: PackedInt32Array = lilies[_row]
			_target = Vector3i(lily[9], lily[10], lily[11])
			_line_y = frog_position.y
			_velocity = Vector3i(_cdiv((_target.x << 16) - frog_position.x, _count), 0,
				_cdiv((_target.z << 16) - frog_position.z, _count))
			_set_action(ACTION_HOP)
		var rotation: PackedInt32Array = multiply(diagonal(FROG_SCALE, FROG_SCALE, FROG_SCALE), lilies[_row])
		if frog_direction == Direction.SOUTH:
			rotation = multiply(diagonal(-ONE, ONE, -ONE), rotation)
		for index: int in 9:
			frog[index] = rotation[index]
	else:
		_target.y = lilies[_row][10]
		_line_y += _cdiv((_target.y << 16) - _line_y, _count)
		var half: int = OptionsMenu.FROG_JUMP_TIME >> 1
		var lift: int = -(8 << 16) * (half * half - (_count - half) * (_count - half))
		frog_position.y = _line_y + lift
		frog_position.x += _velocity.x
		frog_position.z += _velocity.z
		_count -= 1
		if _count == 0:
			frog_position = Vector3i(_target.x << 16, _target.y << 16, _target.z << 16)
			_jumping = false
			_set_action(ACTION_WAIT1)
			splashes.append(_row)
			if rows[_row] == OptionsMenu.Row.MUSIC and menu.music_volume > 0:
				_set_action(ACTION_DANCE)
				frog_looping = true
	if fly_off != 0:
		frog_position.x -= OptionsMenu.FLY_OFF_SPEED << 16
		_target.x -= OptionsMenu.FLY_OFF_SPEED
	frog[9] = frog_position.x >> 16
	frog[10] = frog_position.y >> 16
	frog[11] = frog_position.z >> 16


func _choose_actions(menu: OptionsMenu, buttons: OptionsMenu.Buttons, events: PackedInt32Array) -> void:
	if events.has(OptionsMenu.EventKind.VOLUME_STEP):
		var kind: int = menu.row_kind
		var volume: int = menu.volume(kind)
		var before: int = _volumes[kind] if _volumes.has(kind) else 0
		if volume == 1 and before == 0:
			_set_action(ACTION_PANT2 if kind == OptionsMenu.Row.EFFECTS else ACTION_DANCE)
			frog_looping = true
		elif volume == 0:
			frog_looping = false
	_volumes = {OptionsMenu.Row.MUSIC: menu.music_volume, OptionsMenu.Row.EFFECTS: menu.effects_volume}
	if events.has(OptionsMenu.EventKind.CROAK) and buttons.pressed & OptionsMenu.Buttons.BACK == 0:
		_set_action(ACTION_OUCH)


func _set_action(action_name: StringName) -> void:
	frog_action = action_index(action_name)
	frog_action_set = true


static func _startup(x: int, z: int) -> PackedInt32Array:
	return PackedInt32Array([ONE, 0, 0, 0, ONE, 0, 0, 0, ONE, x, OptionsMenu.FLY_ON_HEIGHT, z])


static func _phases(x: int, z: int, at_frame: int, x_step: int, z_step: int) -> Vector2i:
	var dx: int = x - (-(MenuWater.WATER_X_LEN * MenuWater.WATER_X_NUM) / 2) + x_step
	var dz: int = (MenuWater.WATER_Z_LEN * MenuWater.WATER_Z_NUM) / 2 - z + z_step
	var tx: int = StackLayout.s32(_cdiv(dx * MenuWater.WAVE_PERIOD_X, MenuWater.WATER_X_NUM * MenuWater.WATER_X_LEN) + at_frame * MenuWater.WAVE_FREQ_X)
	var tz: int = StackLayout.s32(_cdiv(dz * MenuWater.WAVE_PERIOD_Z, MenuWater.WATER_Z_NUM * MenuWater.WATER_Z_LEN) + at_frame * MenuWater.WAVE_FREQ_Z)
	return Vector2i(tx, tz)


static func _height(phases: Vector2i) -> int:
	return (StackLayout.rsin(phases.x) * MenuWater.WAVE_AMP_X + StackLayout.rsin(phases.y) * MenuWater.WAVE_AMP_Z) >> 12


static func _cdiv(value: int, divisor: int) -> int:
	var quotient: int = absi(value) / absi(divisor)
	return quotient if (value < 0) == (divisor < 0) else -quotient
