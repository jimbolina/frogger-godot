class_name EntitySwampDefinition
extends RefCounted
## Detached Swamp squirt, crusher, press, rat and slug operands from FrogLord payloads.

## Source SWAMP_RAT_ANIM_* action count the rat selects.
const RAT_ACTIONS: int = 3
## Source SWAMP_SLUG_MOTION_TYPE_CURVY and the flipbook action it selects.
const SLUG_CURVY: int = 1
## Source per-frame divisor of the authored rat speed and the jump speed in units per frame.
const RAT_FRAME_DIVISOR: int = 30
## Source 2048 half-turn of the rat jump sine, divided by the jump time.
const RAT_SINE_HALF_TURN: int = 2048

## Signed sq_time_delay and sq_drop_time, with the signed MR_SVEC sq_target.
var time_delay: int = 0
var drop_time: int = 0
var target: Vector3i = Vector3i.ZERO
## Signed cr_speed/pr_speed, cr_distance/pr_distance, cr_direction/pr_direction and cr_delay/pr_delay.
var speed: int = 0
var distance: int = 0
var direction: int = 0
var delay: int = 0
## Signed ra_speed and the four signed MR_SVEC rat targets: start, start run, end run and end.
var rat_speed: int = 0
var rat_targets: Array[Vector3i] = []
## Unsigned sl_motion_type.
var motion_type: int = 0
## ENTSTRSwpCreateRat results: ra_speed per frame, phase times, <<4 velocities and sine steps.
var run_speed: int = 0
var jump1_time: int = 0
var jump1_velocity_4: Vector3i = Vector3i.ZERO
var jump1_sine_step: int = 0
var run_time: int = 0
var run_velocity_4: Vector3i = Vector3i.ZERO
var jump2_time: int = 0
var jump2_velocity_4: Vector3i = Vector3i.ZERO
var jump2_sine_step: int = 0

## Copies authored operands without sharing the rat target array.
func copy() -> EntitySwampDefinition:
	var result := EntitySwampDefinition.new()
	result.time_delay = time_delay
	result.drop_time = drop_time
	result.target = target
	result.speed = speed
	result.distance = distance
	result.direction = direction
	result.delay = delay
	result.rat_speed = rat_speed
	result.rat_targets = rat_targets.duplicate()
	result.motion_type = motion_type
	result.run_speed = run_speed
	result.jump1_time = jump1_time
	result.jump1_velocity_4 = jump1_velocity_4
	result.jump1_sine_step = jump1_sine_step
	result.run_time = run_time
	result.run_velocity_4 = run_velocity_4
	result.jump2_time = jump2_time
	result.jump2_velocity_4 = jump2_velocity_4
	result.jump2_sine_step = jump2_sine_step
	return result

## Source ENTSTRSwpCreateRat timing: truncating signed 32-bit division of the integer square root
## of the squared target distances. Returns an issue when the source would divide by zero.
func resolve_rat() -> String:
	if rat_targets.size() != 4:
		return "Swamp rat requires its four targets"
	run_speed = PlatformMath.divide(rat_speed, RAT_FRAME_DIVISOR)
	var jump1_length: int = _length(rat_targets[1] - rat_targets[0])
	var run_length: int = _length(rat_targets[2] - rat_targets[1])
	var jump2_length: int = _length(rat_targets[3] - rat_targets[2])
	if jump1_length < 0 or run_length < 0 or jump2_length < 0:
		return "Swamp rat target distances overflow the source 32-bit sum of squares"
	jump1_time = PlatformMath.divide(jump1_length, RAT_FRAME_DIVISOR)
	if jump1_time == 0:
		return "Swamp rat first jump has zero duration"
	jump1_velocity_4 = _velocity_4(rat_targets[1] - rat_targets[0], jump1_time)
	jump1_sine_step = PlatformMath.divide(RAT_SINE_HALF_TURN, jump1_time)
	if run_speed == 0:
		return "Swamp rat has zero run speed"
	run_time = PlatformMath.divide(run_length, run_speed)
	if run_time == 0:
		return "Swamp rat run has zero duration"
	run_velocity_4 = _velocity_4(rat_targets[2] - rat_targets[1], run_time)
	jump2_time = PlatformMath.divide(jump2_length, RAT_FRAME_DIVISOR)
	if jump2_time == 0:
		return "Swamp rat second jump has zero duration"
	jump2_velocity_4 = _velocity_4(rat_targets[3] - rat_targets[2], jump2_time)
	jump2_sine_step = PlatformMath.divide(RAT_SINE_HALF_TURN, jump2_time)
	return ""

## Integer square root of the signed 32-bit sum of squares, or -1 when the source sum would wrap negative.
static func _length(delta: Vector3i) -> int:
	var squared: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	return -1 if squared < 0 else EntityDistanceSound.isqrt(squared)

static func _velocity_4(delta: Vector3i, time: int) -> Vector3i:
	return Vector3i(PlatformMath.divide(PlatformMath.s32(delta.x << 4), time), PlatformMath.divide(PlatformMath.s32(delta.y << 4), time), PlatformMath.divide(PlatformMath.s32(delta.z << 4), time))
