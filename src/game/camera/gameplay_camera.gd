class_name GameplayCamera
extends RefCounted
## Discrete default camera and detached platform attachment from frozen CAMERA.C.

const FOLLOW: int = 0
const FIXED_SWEEP: int = 2
const START: int = 3
const FIXED: int = 4
var error: String = ""
var _definition: GameplayCameraDefinition = null
var _state: GameplayCameraSnapshot = null
var _base_angle: int = 0
var _zone: ZoneDefinition = null

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
	_zone = null
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
	camera._zone = _zone.copy() if _zone != null else null
	return camera

## Starts the source eight-tick quarter turn; caller owns frog WAIT_FOR_CAMERA transition.
func request_turn(direction: int, frog_zone_present: bool = false, entity_matrix12: PackedInt32Array = PackedInt32Array()) -> String:
	if _state == null or _state.mode != FOLLOW:
		return "Camera turn requires follow mode"
	if direction != -1 and direction != 1:
		return "Camera turn direction must be -1 or 1"
	if _state.twist_counter != 0:
		return "Camera turn is already active"
	if not allows_manual_turn():
		return "Camera zone forces its direction"
	var source: Vector3i = _definition.source_offset
	var target: Vector3i = _definition.target_offset
	if frog_zone_present:
		if _zone == null:
			return "Manual zone turn requires a consumed camera zone; tick rolled back"
		if not entity_matrix12.is_empty() and not PlatformMath.valid(entity_matrix12):
			return "Manual zone turn requires a valid entity matrix"
		var matrix: PackedInt32Array = _state.mod_matrix12
		if not entity_matrix12.is_empty():
			matrix = PlatformMath.multiply(matrix, PlatformMath.project(entity_matrix12))
		var quadrant: int = (world_quadrant(matrix) + direction) & 3
		var offset_index: int = quadrant * 2
		if offset_index + 1 >= _zone.camera_offsets.size():
			return "ZONE[%d] manual turn quadrant %d reads outside the camera payload; tick rolled back" % [_zone.zone_index, quadrant]
		source = _zone.camera_offsets[offset_index]
		target = _zone.camera_offsets[offset_index + 1]
	_state.twist_counter = direction
	_state.twist_quadrants = 1
	_state.move_timer = 8
	_state.next_source_offset = source
	_state.next_target_offset = target
	return ""

## Source control ignores manual turns in a forced, non-semiforced camera zone.
func allows_manual_turn() -> bool:
	return _zone == null or _zone.camera_direction < 0 or _zone.camera_flags & 4 != 0

## Source GetWorldYQuadrantFromMatrix uses strict Z dominance, with ties on X.
static func world_quadrant(matrix: PackedInt32Array) -> int:
	return (0 if matrix[8] > 0 else 2) if absi(matrix[8]) > absi(matrix[2]) else (1 if matrix[2] > 0 else 3)

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

## Changes the source camera frame on mounting, transfer or dismounting.
func transition_attachment(old_matrix12: PackedInt32Array, new_matrix12: PackedInt32Array, snap: bool) -> String:
	if _state == null:
		return "Camera must be initialized"
	for matrix: PackedInt32Array in [old_matrix12, new_matrix12]:
		if not matrix.is_empty() and not PlatformMath.valid(matrix):
			return "Camera attachment requires a valid source matrix"
	var changed: PackedInt32Array = _state.mod_matrix12.duplicate()
	if not old_matrix12.is_empty():
		changed = PlatformMath.multiply(changed, PlatformMath.project(old_matrix12))
	if not new_matrix12.is_empty():
		changed = PlatformMath.multiply(changed, PlatformMath.transpose(PlatformMath.project(new_matrix12)))
	_state.mod_matrix12 = changed
	if snap:
		align_y()
	return ""

## Starts frozen SetupCameraYRotation's correction to the nearest quadrant.
func align_y() -> void:
	var matrix: PackedInt32Array = _state.mod_matrix12
	var direction: int = 0 if matrix[8] > 0xb50 else 2 if matrix[8] < -0xb50 else 1 if matrix[2] > 0xb50 else 3
	var fixed: Vector3i = [Vector3i(0, 0, 4096), Vector3i(4096, 0, 0), Vector3i(0, 0, -4096), Vector3i(-4096, 0, 0)][direction]
	var vector := Vector3i(matrix[2], matrix[5], matrix[8])
	var theta: int = PlatformMath.acos12((fixed.x * vector.x + fixed.z * vector.z) >> 12)
	var normal: Vector3i = EntityTransform._cross12(fixed, vector)
	_state.destination_ytheta = 0
	if normal.y > 0:
		_state.destination_ytheta = direction * 1024
		_state.current_ytheta = _state.destination_ytheta + theta
		_state.delta_ytheta = -32
	elif normal.y < 0:
		_state.destination_ytheta = 4096 if direction == 0 else direction * 1024
		_state.current_ytheta = _state.destination_ytheta - theta
		_state.delta_ytheta = 32
	else:
		_state.delta_ytheta = 0

## Applies one integer camera tick; rejected unsupported input leaves state untouched.
func step(input: GameplayCameraTick) -> String:
	if _state == null or input == null:
		return "Camera and tick input must be initialized"
	if input.camera_zone != null:
		var zone_issue: String = input.camera_zone.validate_camera()
		if not zone_issue.is_empty():
			return zone_issue
	if input.on_entity and not PlatformMath.valid(input.entity_matrix12):
		return "Camera entity transforms require a valid source matrix"
	if input.remaining_ticks < 0 or input.start_timer < 0:
		return "Camera timers must be nonnegative"
	_state.entity_angle_delta = 0
	match _state.mode:
		START:
			if input.start_timer <= _state.move_timer:
				_state.mode = FIXED_SWEEP
				if input.camera_zone != null:
					_set_zone(input.camera_zone)
					_state.next_source_offset = _zone.camera_offsets[0]
					_state.next_target_offset = _zone.camera_offsets[1]
				else:
					_state.next_source_offset = _definition.source_offset
					_state.next_target_offset = _definition.target_offset
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
	_update_zone(input)
	if _state.move_timer > 0:
		_sweep_offsets(_state.move_timer)
		_state.move_timer -= 1
	var desired_y: int = input.frog_world.y
	if not input.freefall and input.frog_mode == 1:
		var duration: int = 15 if input.superjump else 6
		desired_y = input.old_y + _divide((duration - input.remaining_ticks) * (input.target_y - input.old_y), duration)
	desired_y = mini(desired_y, 0)
	if _absolute_y():
		desired_y = _state.next_source_offset.y
	if not input.ignore_frog_y:
		_state.tracked_world.y = _approach_y(_state.tracked_world.y, desired_y)
	_state.tracked_world.x = _approach_horizontal(_state.tracked_world.x, input.frog_world.x)
	_state.tracked_world.z = _approach_horizontal(_state.tracked_world.z, input.frog_world.z)
	var twist_angle: int = 0
	var twist_end: bool = false
	if _state.twist_counter != 0:
		twist_angle = _divide(_state.twist_counter * 1024, 8)
		_state.twist_counter += 1 if _state.twist_counter > 0 else -1
		if absi(_state.twist_counter) > 8 * _state.twist_quadrants:
			_state.twist_counter = 0
			_base_angle = (_base_angle + twist_angle) & 4095
			_state.entity_angle_delta = _state.twist_quadrants * (1 if twist_angle > 0 else -1)
			twist_end = true
	if _state.delta_ytheta != 0:
		_state.current_ytheta += _state.delta_ytheta
		if (_state.delta_ytheta > 0 and _state.current_ytheta >= _state.destination_ytheta) or (_state.delta_ytheta < 0 and _state.current_ytheta <= _state.destination_ytheta):
			_state.current_ytheta = _state.destination_ytheta
			_state.delta_ytheta = 0
		_state.mod_matrix12 = PlatformMath.yaw(_state.current_ytheta)
	var composed: PackedInt32Array = _state.mod_matrix12.duplicate()
	if twist_angle != 0:
		composed = PlatformMath.multiply(PlatformMath.yaw(twist_angle), composed)
		if twist_end:
			_state.mod_matrix12 = composed.duplicate()
			twist_angle = 0
	if input.on_entity:
		composed = PlatformMath.multiply(composed, PlatformMath.project(input.entity_matrix12))
	_state.rotation_angle = (_base_angle + twist_angle) & 4095
	_compose(input.frog_world, false, true, composed)

func _set_zone(zone: ZoneDefinition) -> void:
	_zone = zone.copy() if zone != null else null
	_state.zone_index = zone.zone_index if zone != null else -1

func _absolute_y() -> bool:
	return _zone != null and _zone.camera_flags & 8 != 0

func _update_zone(input: GameplayCameraTick) -> void:
	var identity: int = input.camera_zone.zone_index if input.camera_zone != null else -1
	if identity == _state.zone_index:
		return
	_state.move_timer = 30
	if input.camera_zone == null:
		if _absolute_y():
			_state.tracked_world.y = input.frog_world.y
			_state.source_offset = _definition.source_offset
			_state.target_offset = _definition.target_offset
		_set_zone(null)
		_state.next_source_offset = _definition.source_offset
		_state.next_target_offset = _definition.target_offset
		return
	if _absolute_y():
		_state.tracked_world.y = 0
	_set_zone(input.camera_zone)
	if _absolute_y():
		_state.tracked_world.y = _state.source_world.y
	var matrix: PackedInt32Array = _state.mod_matrix12
	if input.on_entity:
		matrix = PlatformMath.multiply(matrix, PlatformMath.project(input.entity_matrix12))
	var quadrant: int = world_quadrant(matrix)
	if _zone.camera_direction >= 0:
		var difference: int = (_zone.camera_direction - quadrant) & 3
		if difference != 0:
			_state.twist_counter = -1 if difference == 3 else 1
			_state.twist_quadrants = 2 if difference == 2 else 1
		quadrant = _zone.camera_direction
	_state.next_source_offset = _zone.camera_offsets[quadrant * 2]
	_state.next_target_offset = _zone.camera_offsets[quadrant * 2 + 1]

func _sweep_offsets(divisor: int) -> void:
	_state.source_offset = _offset_step(_state.source_offset, _state.next_source_offset, divisor)
	_state.target_offset = _offset_step(_state.target_offset, _state.next_target_offset, divisor)

func _compose(origin: Vector3i, use_origin: bool, update_controls: bool, rotation: PackedInt32Array = PackedInt32Array()) -> void:
	var anchor: Vector3i = origin if use_origin else _state.tracked_world
	var source_offset: Vector3i = _rotate(_state.source_offset, _state.rotation_angle) if rotation.is_empty() else PlatformMath.apply(rotation, _state.source_offset)
	var target_offset: Vector3i = _rotate(_state.target_offset, _state.rotation_angle) if rotation.is_empty() else PlatformMath.apply(rotation, _state.target_offset)
	_state.source_world = anchor + (_state.source_offset if use_origin else source_offset)
	_state.target_world = anchor + (_state.target_offset if use_origin else target_offset)
	if not use_origin and _absolute_y():
		_state.source_world.y = _state.tracked_world.y
		_state.target_world.y = _state.target_offset.y
	_state.axis_z_12 = _normalize(_state.target_world - _state.source_world)
	_state.axis_x_12 = _normalize(_cross_12(Vector3i(0, 4096, 0), _state.axis_z_12))
	_state.axis_y_12 = _cross_12(_state.axis_z_12, _state.axis_x_12)
	if update_controls:
		var north: Vector3i = _normalize(Vector3i(-_state.axis_y_12.x, 0, -_state.axis_y_12.z))
		var east: Vector3i = _normalize(Vector3i(_state.axis_x_12.x, 0, _state.axis_x_12.z))
		_state.direction_vectors_12.assign([north, east, -north, -east])
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
