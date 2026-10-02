class_name PathEvaluator
extends RefCounted
## Evaluates source path geometry with the frozen C port's fixed-point formulas.

const I32_MIN: int = -2147483648
const I32_MAX: int = 2147483647

## Checks fields required by the source evaluator without changing source values.
static func validate_segment(segment: PathSegmentDefinition) -> String:
	if segment == null:
		return "Path contains a null segment"
	if segment.length <= 0 or segment.length > I32_MAX:
		return "Path segment length must be positive signed32"
	if segment.segment_type == PathSegmentDefinition.LINE:
		# The frozen backend normalizes a zero direction to a zero tangent.
		pass
	elif segment.segment_type == PathSegmentDefinition.ARC:
		if segment.radius <= 0:
			return "Path arc requires a positive radius"
		if segment.radius * 0x6487 > I32_MAX:
			return "Path arc circumference overflows source signed32"
	elif segment.segment_type == PathSegmentDefinition.SPLINE:
		if segment.matrix.size() != 12 or segment.smooth_t.size() != 4 or segment.smooth_c.size() != 12:
			return "Path spline requires 12 matrix, 4 smooth_t and 12 smooth_c values"
	else:
		return "Unknown path segment type %d" % segment.segment_type
	return ""

## Evaluates a source distance, including extrapolation after a single overshoot.
static func sample(segment: PathSegmentDefinition, distance: int, backwards: bool = false) -> PathSample:
	var result := PathSample.new()
	result.error = validate_segment(segment)
	if not result.error.is_empty():
		return result
	# PATH.C evaluates the result of just one segment transition even when its
	# speed leaves the distance beyond that segment. Keep that extrapolation.
	match segment.segment_type:
		PathSegmentDefinition.LINE:
			var delta: Vector3i = segment.end - segment.start
			result.position = segment.start + Vector3i(_div(_signed32(delta.x * distance), segment.length), _div(_signed32(delta.y * distance), segment.length), _div(_signed32(delta.z * distance), segment.length))
			result.tangent = _normalise(delta)
			result.segment_param = _div(_signed32(distance * 4096), segment.length)
		PathSegmentDefinition.ARC:
			_sample_arc(segment, distance, result)
		PathSegmentDefinition.SPLINE:
			_sample_spline(segment, distance, result)
	if backwards:
		result.tangent = -result.tangent
	return result

static func _sample_spline(segment: PathSegmentDefinition, distance: int, result: PathSample) -> void:
	var length: int = _signed32(distance << 5)
	var section: int = 0
	var d: int = length
	for i: int in range(3, 0, -1):
		d = _signed32(length - (segment.smooth_t[i - 1] >> 3))
		if d >= 0:
			section = i
			break
	if section == 0:
		d = length
	var e: int = d
	d = segment.smooth_c[section * 3] >> 11
	d = _signed32(d * e) >> 13
	d = _signed32(d + (segment.smooth_c[section * 3 + 1] >> 11))
	d = _signed32(d * e) >> 13
	d = _signed32(d + (segment.smooth_c[section * 3 + 2] >> 11))
	d = _signed32(d * e) >> 13
	d >>= 5
	var fixed_t: PackedInt32Array = PackedInt32Array([0, 0, 512, 1024, 1536, 2048])
	var t: int = _signed32(d + fixed_t[section + 1])
	result.segment_param = _signed32(t << 1)
	var t2: int = _signed32(t * t) >> 3
	var t3: int = _signed32(t2 * t) >> 11
	var p: Array[int] = [0, 0, 0]
	var v: Array[int] = [0, 0, 0]
	for axis: int in 3:
		p[axis] = _signed32((_signed32(t3 * segment.matrix[axis]) >> 16) + (_signed32(t2 * segment.matrix[3 + axis]) >> 16) + (_signed32(t * segment.matrix[6 + axis]) >> 8) + _signed32(segment.matrix[9 + axis] << 3))
		var tangent_t2: int = _signed32(3 * t * t) >> 3
		v[axis] = _signed32((_signed32(tangent_t2 * segment.matrix[axis]) >> 16) + (_signed32(t * segment.matrix[3 + axis]) >> 7) + _signed32(segment.matrix[6 + axis] << 3))
	result.position = Vector3i(_signed16(p[0]), _signed16(p[1]), _signed16(p[2]))
	result.tangent = _normalise(Vector3i(v[0] >> 4, v[1] >> 4, v[2] >> 4))

static func _sample_arc(segment: PathSegmentDefinition, distance: int, result: PathSample) -> void:
	var radial: Vector3i = _normalise(segment.start - segment.centre)
	var up: Vector3i = segment.normal
	var cross: Vector3i = Vector3i((radial.y * up.z - radial.z * up.y) >> 12, (radial.z * up.x - radial.x * up.z) >> 12, (radial.x * up.y - radial.y * up.x) >> 12)
	result.segment_param = _div(_signed32(distance * 4096), segment.length)
	var circumference: int = segment.radius * 0x6487
	var turns: int = _div(_signed32(distance << 12), circumference)
	var angle: int = _div(_signed32(_signed32(distance << 18) - _signed32(turns * circumference)), segment.radius * 0x192)
	var y: int = _div(_signed32(-segment.pitch * distance), segment.length)
	var cosine: int = roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var sine: int = roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)
	var local: Vector3i = Vector3i(_signed16((cosine * segment.radius) >> 12), _signed16(y), _signed16((sine * segment.radius) >> 12))
	result.position = segment.centre + _rotate(local, radial, up, cross)
	result.tangent = _rotate(Vector3i(-sine, 0, cosine), radial, up, cross)

static func _rotate(local: Vector3i, radial: Vector3i, up: Vector3i, cross: Vector3i) -> Vector3i:
	return Vector3i(_signed32(_signed16(radial.x) * local.x + _signed16(-up.x) * local.y + _signed16(-cross.x) * local.z) >> 12, _signed32(_signed16(radial.y) * local.x + _signed16(-up.y) * local.y + _signed16(-cross.y) * local.z) >> 12, _signed32(_signed16(radial.z) * local.x + _signed16(-up.z) * local.y + _signed16(-cross.z) * local.z) >> 12)

static func _signed16(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low

static func _normalise(value: Vector3i) -> Vector3i:
	var magnitude: float = sqrt(float(value.x) * value.x + float(value.y) * value.y + float(value.z) * value.z)
	if magnitude < 0.000001:
		return Vector3i.ZERO
	return Vector3i(roundi(value.x * 4096.0 / magnitude), roundi(value.y * 4096.0 / magnitude), roundi(value.z * 4096.0 / magnitude))

@warning_ignore("integer_division")
static func _div(numerator: int, denominator: int) -> int:
	return numerator / denominator
