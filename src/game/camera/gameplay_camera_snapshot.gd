class_name GameplayCameraSnapshot
extends RefCounted
## Detached source camera state; presentation may interpolate source/target only.

var shake_timer: int = 0
var shake_duration: int = 0
var shake_amplitude_x: int = 0
var shake_amplitude_y: int = 0
var shake_frequency_x: int = 0
var shake_frequency_y: int = 0
var source_world: Vector3i = Vector3i.ZERO
var target_world: Vector3i = Vector3i.ZERO
var tracked_world: Vector3i = Vector3i.ZERO
var source_offset: Vector3i = Vector3i.ZERO
var target_offset: Vector3i = Vector3i.ZERO
var next_source_offset: Vector3i = Vector3i.ZERO
var next_target_offset: Vector3i = Vector3i.ZERO
var mode: int = 0
var move_timer: int = 0
var twist_counter: int = 0
var rotation_angle: int = 0
var controller_directions: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var axis_x_12: Vector3i = Vector3i(4096, 0, 0)
var axis_y_12: Vector3i = Vector3i(0, 4096, 0)
var axis_z_12: Vector3i = Vector3i(0, 0, 4096)

## True only after both source timers expire; frog movement checks before camera update.
func turn_wait_complete() -> bool:
	return move_timer == 0 and twist_counter == 0

## Copies every scalar and array so observers cannot change the authoritative camera.
func copy() -> GameplayCameraSnapshot:
	var value := GameplayCameraSnapshot.new()
	value.source_world = source_world
	value.target_world = target_world
	value.tracked_world = tracked_world
	value.source_offset = source_offset
	value.target_offset = target_offset
	value.next_source_offset = next_source_offset
	value.next_target_offset = next_target_offset
	value.mode = mode
	value.move_timer = move_timer
	value.twist_counter = twist_counter
	value.rotation_angle = rotation_angle
	value.controller_directions = controller_directions.duplicate()
	value.axis_x_12 = axis_x_12
	value.axis_y_12 = axis_y_12
	value.axis_z_12 = axis_z_12
	value.shake_timer = shake_timer
	value.shake_duration = shake_duration
	value.shake_amplitude_x = shake_amplitude_x
	value.shake_amplitude_y = shake_amplitude_y
	value.shake_frequency_x = shake_frequency_x
	value.shake_frequency_y = shake_frequency_y
	return value
