class_name MofTransform
extends RefCounted
## One authored XAR transform, retaining the signed fields exactly as stored.

## Bytes used by each signature's transform encoding, including padding.
const SIZES: Array[int] = [24, 16, 10, 14, 14, 18]
## Encoding number from the XAR signature.
var code: int = 0
## Semantic fields in disk order, without matrix-byte padding.
var raw_values := PackedInt32Array()


## Reads one transform from a reader already bounded to the transform pool.
static func read(reader: ByteReader, encoding: int) -> MofTransform:
	var transform := MofTransform.new()
	transform.code = encoding
	if encoding < 0 or encoding >= SIZES.size():
		reader.fail("unsupported transform encoding %d" % encoding)
		return transform
	if encoding <= 1:
		for _i: int in 9:
			transform.raw_values.append(reader.read_s8() if encoding == 1 else reader.read_s16())
		if encoding == 1:
			reader.skip(1)
	else:
		for _i: int in 4:
			transform.raw_values.append(reader.read_s8() if encoding == 2 or encoding == 4 else reader.read_s16())
	for _i: int in 3:
		transform.raw_values.append(reader.read_s16())
	if encoding >= 4:
		for _i: int in 4:
			transform.raw_values.append(reader.read_s8())
	return transform


## Expands to nine row-major 4.12 matrix entries and three whole translations.
## Quaternion products use the C engine's integer formula without normalization.
func matrix_values() -> PackedInt32Array:
	if code <= 1:
		var values: PackedInt32Array = raw_values.duplicate()
		if code == 1:
			for i: int in 9:
				values[i] <<= 5
		return values
	var values: PackedInt32Array = quaternion_matrix(quaternion_values())
	if code >= 4 and raw_values[10] & 1 != 0:
		for row: int in 3:
			for column: int in 3:
				values[row * 3 + column] = _short((values[row * 3 + column] * raw_values[7 + row]) >> 5)
	values.append_array(raw_values.slice(4, 7))
	return values


## Returns the authored quaternion as c, x, y, z in 3.12 units.
func quaternion_values() -> PackedInt32Array:
	var values: PackedInt32Array = raw_values.slice(0, 4)
	if code == 2 or code == 4:
		for i: int in 4:
			values[i] <<= 6
	return values


## Samples an authored interpolation pair using shortest-path spherical weights.
## Translation and scale keep the reference's arithmetic right shifts.
func interpolate(next: MofTransform, amount: int) -> PackedInt32Array:
	var a: PackedInt32Array = quaternion_values()
	var b: PackedInt32Array = next.quaternion_values()
	var dot: int = 0
	for i: int in 4:
		dot += a[i] * b[i]
	dot = _short(dot >> 12)
	var sign_value: float = -1.0 if dot < 0 else 1.0
	var cosine: float = clampf(absf(float(dot)) / 4096.0, -1.0, 1.0)
	var t: float = float(amount) / 4096.0
	var start_weight: float = 1.0 - t
	var end_weight: float = t
	if 4096 - absi(dot) > 1:
		var angle: float = acos(cosine)
		end_weight = sin(t * angle) / sin(angle)
		start_weight = cos(t * angle) - cosine * end_weight
	var q := PackedInt32Array()
	for i: int in 4:
		if amount == 0:
			q.append(a[i])
		elif amount == 4096:
			q.append(_short(int(sign_value) * b[i]))
		else:
			q.append(_short(floori(start_weight * a[i] + sign_value * end_weight * b[i])))
	if amount > 0 and (code == 2 or code == 4):
		var magnitude_squared: int = 0
		for value: int in q:
			magnitude_squared += value * value
		var divisor: int = clampi(int(sqrt(float(magnitude_squared))), 4064, 4128)
		var factor: int = (1 << 24) / divisor
		for i: int in 4:
			q[i] = _short((q[i] * factor) >> 12)
	var values: PackedInt32Array = quaternion_matrix(q)
	if code >= 4 and (raw_values[10] | next.raw_values[10]) & 1 != 0:
		for row: int in 3:
			var scale_value: int = ((raw_values[7 + row] << 7) * (4096 - amount) + (next.raw_values[7 + row] << 7) * amount) >> 12
			for column: int in 3:
				values[row * 3 + column] = _short((values[row * 3 + column] * scale_value) >> 12)
	for i: int in range(4, 7):
		values.append((raw_values[i] * (4096 - amount) + next.raw_values[i] * amount) >> 12)
	return values


static func _short(value: int) -> int:
	return ((value + 32768) & 65535) - 32768


## The reference's quaternion matrix, including its stored rotation direction.
static func quaternion_matrix(q: PackedInt32Array) -> PackedInt32Array:
	var c: int = q[0]
	var x: int = q[1]
	var y: int = q[2]
	var z: int = q[3]
	var xx: int = 2 * x * x
	var xy: int = 2 * x * y
	var xz: int = 2 * x * z
	var yy: int = 2 * y * y
	var yz: int = 2 * y * z
	var zz: int = 2 * z * z
	var wx: int = 2 * c * x
	var wy: int = 2 * c * y
	var wz: int = 2 * c * z
	var values := PackedInt32Array([4096 - ((yy + zz) >> 12), (xy + wz) >> 12, (xz - wy) >> 12,
		(xy - wz) >> 12, 4096 - ((xx + zz) >> 12), (yz + wx) >> 12,
		(xz + wy) >> 12, (yz - wx) >> 12, 4096 - ((xx + yy) >> 12)])
	for i: int in 9:
		values[i] = ((values[i] + 32768) & 65535) - 32768
	return values
