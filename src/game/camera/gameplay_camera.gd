class_name GameplayCamera
extends RefCounted
## Discrete default terrain camera from frozen CAMERA.C, without zones or entity transforms.

const FOLLOW: int = 0
const FIXED_SWEEP: int = 2
const START: int = 3
const FIXED: int = 4
var error: String = ""
var _definition: GameplayCameraDefinition = null
var _state: GameplayCameraSnapshot = null
var _base_angle: int = 0

## Copies validated map defaults and creates a follow or original level-start camera.
static func create(definition: GameplayCameraDefinition, frog_world: Vector3i, startup: bool = false) -> GameplayCamera:
	var camera := GameplayCamera.new()
	if definition == null:
		camera.error = "Camera requires map default offsets"
		return camera
	if definition.source_offset.y >= definition.target_offset.y or Vector2i(definition.source_offset.x, definition.source_offset.z) == Vector2i(definition.target_offset.x, definition.target_offset.z):
		camera.error = "Terrain camera requires a downward view with a nonzero horizontal axis"
		return camera
	camera._definition = definition.copy()
	camera.reset(frog_world, startup)
	return camera

## Resets private timers/rotation, optionally reproducing CAMERA.C ResetCamera start offsets.
func reset(frog_world: Vector3i, startup: bool = false) -> void:
	_state = GameplayCameraSnapshot.new()
	_base_angle = 0
	_state.next_source_offset = _definition.source_offset
	_state.next_target_offset = _definition.target_offset
	_state.tracked_world = frog_world if not startup else Vector3i.ZERO
	_state.mode = START if startup else FOLLOW
	_state.move_timer = 30 if startup else 0
	_state.source_offset = Vector3i(200, -400, 400) if startup else _definition.source_offset
	_state.target_offset = Vector3i(0, 100, 0) if startup else _definition.target_offset
	_compose(frog_world, startup, not startup)

## Returns a fully detached camera snapshot.
func snapshot() -> GameplayCameraSnapshot:
	return _state.copy() if _state != null else null

## Copies the complete camera for a transactional candidate rule tick.
func copy() -> GameplayCamera:
	var camera := GameplayCamera.new()
	camera.error = error
	camera._definition = _definition.copy()
	camera._state = _state.copy()
	camera._base_angle = _base_angle
	return camera

## Starts the source eight-tick quarter turn; caller owns frog WAIT_FOR_CAMERA transition.
func request_turn(direction: int) -> String:
	if _state == null or _state.mode != FOLLOW:
		return "Camera turn requires follow mode"
	if direction != -1 and direction != 1:
		return "Camera turn direction must be -1 or 1"
	if _state.twist_counter != 0:
		return "Camera turn is already active"
	_state.twist_counter = direction
	_state.move_timer = 8
	_state.next_source_offset = _definition.source_offset
	_state.next_target_offset = _definition.target_offset
	return ""

## Freezes source camera processing as FrogKill does; post-update shake still runs.
func request_fixed() -> void:
	_state.mode = FIXED

## Starts source ShakeCamera with two ordered draws from the run's shared MRrand stream.
func request_shake(amplitude: int, duration: int, frequency: int, draw_1: int, draw_2: int) -> String:
	if _state == null or amplitude < 0 or amplitude > 128 or duration <= 0 or duration > 32767 or frequency < 8 or frequency > 32767:
		return "Camera shake requires supported source amplitude, duration and frequency"
	if draw_1 < 0 or draw_1 > 32767 or draw_2 < 0 or draw_2 > 32767:
		return "Camera shake requires two MRrand draws"
	var angle: int = (draw_1 & 511) - 256
	_state.shake_amplitude_x = (_sine(angle) * amplitude) >> 8
	_state.shake_amplitude_y = (_sine(angle + 1024) * amplitude) >> 8
	_state.shake_duration = duration
	_state.shake_timer = duration
	_state.shake_frequency_x = frequency
	_state.shake_frequency_y = frequency + draw_2 % (frequency >> 3)
	return ""

## Requests the source death offsets over 45 ticks, preserving current turn state.
func request_death() -> void:
	_state.next_source_offset = Vector3i(0, -1000, -100)
	_state.next_target_offset = Vector3i.ZERO
	_state.move_timer = 45

## Applies one integer camera tick; rejected unsupported input leaves state untouched.
func step(input: GameplayCameraTick) -> String:
	if _state == null or input == null:
		return "Camera and tick input must be initialized"
	if input.has_camera_zone or input.on_entity:
		return "Terrain camera does not yet support camera zones or entity transforms"
	if input.remaining_ticks < 0 or input.start_timer < 0:
		return "Camera timers must be nonnegative"
	match _state.mode:
		START:
			if input.start_timer <= _state.move_timer:
				_state.mode = FIXED_SWEEP
			_compose(input.frog_world, true, false)
		FIXED_SWEEP:
			_state.move_timer -= 1
			if _state.move_timer == 0:
				_state.mode = FOLLOW
				_state.tracked_world = input.frog_world
			else:
				_sweep_offsets(_state.move_timer)
			_compose(input.frog_world, true, false)
		FOLLOW:
			_follow(input)
	_apply_shake()
	return ""

func _follow(input: GameplayCameraTick) -> void:
	if _state.move_timer > 0:
		_sweep_offsets(_state.move_timer)
		_state.move_timer -= 1
	var desired_y: int = input.frog_world.y
	if not input.freefall and input.frog_mode == 1:
		var duration: int = 15 if input.superjump else 6
		desired_y = input.old_y + _divide((duration - input.remaining_ticks) * (input.target_y - input.old_y), duration)
	desired_y = mini(desired_y, 0)
	if not input.ignore_frog_y:
		_state.tracked_world.y = _approach_y(_state.tracked_world.y, desired_y)
	_state.tracked_world.x = _approach_horizontal(_state.tracked_world.x, input.frog_world.x)
	_state.tracked_world.z = _approach_horizontal(_state.tracked_world.z, input.frog_world.z)
	var twist_angle: int = 0
	if _state.twist_counter != 0:
		twist_angle = _divide(_state.twist_counter * 1024, 8)
		_state.twist_counter += 1 if _state.twist_counter > 0 else -1
		if absi(_state.twist_counter) > 8:
			_state.twist_counter = 0
			_base_angle = (_base_angle + twist_angle) & 4095
			twist_angle = 0
	_state.rotation_angle = (_base_angle + twist_angle) & 4095
	_compose(input.frog_world, false, true)

func _sweep_offsets(divisor: int) -> void:
	_state.source_offset = _offset_step(_state.source_offset, _state.next_source_offset, divisor)
	_state.target_offset = _offset_step(_state.target_offset, _state.next_target_offset, divisor)

func _compose(origin: Vector3i, use_origin: bool, update_controls: bool) -> void:
	var anchor: Vector3i = origin if use_origin else _state.tracked_world
	_state.source_world = anchor + (_state.source_offset if use_origin else _rotate(_state.source_offset, _state.rotation_angle))
	_state.target_world = anchor + (_state.target_offset if use_origin else _rotate(_state.target_offset, _state.rotation_angle))
	_state.axis_z_12 = _normalize(_state.target_world - _state.source_world)
	_state.axis_x_12 = _normalize(_cross_12(Vector3i(0, 4096, 0), _state.axis_z_12))
	_state.axis_y_12 = _cross_12(_state.axis_z_12, _state.axis_x_12)
	if update_controls:
		var north: Vector3i = _normalize(Vector3i(-_state.axis_y_12.x, 0, -_state.axis_y_12.z))
		var direction: int = (0 if north.z > 0 else 2) if absi(north.z) > absi(north.x) else (1 if north.x > 0 else 3)
		for index: int in range(4):
			_state.controller_directions[index] = (direction + index) & 3

func _rotate(vector: Vector3i, angle: int) -> Vector3i:
	var theta: float = float(angle) * TAU / 4096.0
	var cosine: int = roundi(cos(theta) * 4096.0)
	var sine: int = roundi(sin(theta) * 4096.0)
	return Vector3i((cosine * vector.x + sine * vector.z) >> 12, vector.y, (-sine * vector.x + cosine * vector.z) >> 12)

func _normalize(vector: Vector3i) -> Vector3i:
	var x: float = float(vector.x)
	var y: float = float(vector.y)
	var z: float = float(vector.z)
	var length: float = sqrt(x * x + y * y + z * z)
	if length < 0.000001:
		return Vector3i.ZERO
	var scale: float = 4096.0 / length
	return Vector3i(roundi(vector.x * scale), roundi(vector.y * scale), roundi(vector.z * scale))

func _cross_12(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i((a.y * b.z - a.z * b.y) >> 12, (a.z * b.x - a.x * b.z) >> 12, (a.x * b.y - a.y * b.x) >> 12)

func _offset_step(current: Vector3i, target: Vector3i, divisor: int) -> Vector3i:
	return current + Vector3i(_divide(target.x - current.x, divisor), _divide(target.y - current.y, divisor), _divide(target.z - current.z, divisor))

func _divide(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator

func _approach_y(current: int, target: int) -> int:
	return current + clampi(target - current, -24, 24)

func _approach_horizontal(current: int, target: int) -> int:
	var distance: int = absi(target - current)
	if distance < 5:
		return target
	return current + (distance >> 1) * (1 if target > current else -1)

func _sine(angle: int) -> int:
	return roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)

func _signed_32(value: int) -> int:
	return ((value + 2147483648) & 4294967295) - 2147483648

func _apply_shake() -> void:
	if _state.shake_timer == 0:
		return
	var elapsed: int = _state.shake_duration - _state.shake_timer
	var wave_x: int = _sine(_divide(elapsed * _state.shake_frequency_x, _state.shake_duration))
	var wave_y: int = _sine(_divide(elapsed * _state.shake_frequency_y, _state.shake_duration))
	var x: int = _divide(_signed_32(wave_x * _state.shake_amplitude_x * _state.shake_timer), _state.shake_duration) >> 16
	var y: int = _divide(_signed_32(wave_y * _state.shake_amplitude_y * _state.shake_timer), _state.shake_duration) >> 16
	_state.source_world += Vector3i((_state.axis_x_12.x * x + _state.axis_y_12.x * y) >> 12, (_state.axis_x_12.y * x + _state.axis_y_12.y * y) >> 12, (_state.axis_x_12.z * x + _state.axis_y_12.z * y) >> 12)
	_state.shake_timer -= 1
