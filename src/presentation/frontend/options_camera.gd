class_name OptionsCamera
extends RefCounted
## The front-end options camera's fixed sweep between its presets (camera.c CAMERA_MODE_FIXED_SWEEP).
##
## Each tick the move timer becomes [code]MAX(1, timer) - 1[/code]; while it is non-zero the
## eye and target each move by [code](goal - current) / timer[/code], truncated toward zero.
## One camera serves the main menu, options and controller pages, so a sweep begun on one
## page continues on the next.

## The options camera's OPTIONS preset eye (tempopt.h OPTIONS_CAMERA_OPTIONS_SOURCE_OFS_*).
const OPTIONS_SOURCE: Vector3i = Vector3i(-1200, -2000, -1800)
## The options camera's OPTIONS preset target (tempopt.h OPTIONS_CAMERA_OPTIONS_TARGET_OFS_*).
const OPTIONS_TARGET: Vector3i = Vector3i(300, 1000, 500)

## The current eye.
var source: Vector3i = MenuWaterView.MAIN_SOURCE
## The current target.
var target: Vector3i = MenuWaterView.MAIN_TARGET
## The [enum OptionsMenu.Camera] preset being swept to.
var goal: int = OptionsMenu.Camera.MAIN
## Move ticks left (ca_move_timer).
var timer: int = 0


## The eye of preset [param kind], an [enum OptionsMenu.Camera] value.
static func preset_source(kind: int) -> Vector3i:
	match kind:
		OptionsMenu.Camera.OPTIONS:
			return OPTIONS_SOURCE
		OptionsMenu.Camera.CONTROLS:
			return OptionsMenu.CONTROLS_CAMERA_SOURCE
	return MenuWaterView.MAIN_SOURCE


## The target of preset [param kind], an [enum OptionsMenu.Camera] value.
static func preset_target(kind: int) -> Vector3i:
	match kind:
		OptionsMenu.Camera.OPTIONS:
			return OPTIONS_TARGET
		OptionsMenu.Camera.CONTROLS:
			return OptionsMenu.CONTROLS_CAMERA_TARGET
	return MenuWaterView.MAIN_TARGET


## Starts a sweep to preset [param kind] over [param ticks] ticks.
func aim(kind: int, ticks: int) -> void:
	goal = kind
	timer = ticks


## Runs one tick: decrements the timer, then moves toward the goal.
func tick() -> void:
	timer = maxi(1, timer) - 1
	move(goal, timer)


## Moves one step toward preset [param kind] with [param remaining] ticks left after this one,
## as [method tick] does once its timer is decremented; the page's own counter drives it.
func move(kind: int, remaining: int) -> void:
	goal = kind
	timer = remaining
	if remaining == 0:
		return
	source += _step(preset_source(kind) - source, remaining)
	target += _step(preset_target(kind) - target, remaining)


## The camera transform for the current eye and target.
func transform() -> Transform3D:
	return MenuWaterView.camera_transform(source, target)


static func _step(delta: Vector3i, divisor: int) -> Vector3i:
	return Vector3i(_cdiv(delta.x, divisor), _cdiv(delta.y, divisor), _cdiv(delta.z, divisor))


static func _cdiv(value: int, divisor: int) -> int:
	var quotient: int = absi(value) / divisor
	return quotient if value >= 0 else -quotient
