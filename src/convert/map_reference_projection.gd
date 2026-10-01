class_name MapReferenceProjection
extends RefCounted
## Frozen map_slice's 640x480 PAL aspect and -512 pitch, for diagnostics only.
## MR_VIEW.C's aspect*transpose and mr_stub_gpu.c gte_rtps/avsz3/avsz4.


## Fixed matrix product, with C arithmetic right shift after each row sum.
static func rotate(vertex: Vector3i) -> Vector3i:
	return Vector3i((8192 * vertex.x) >> 12,
		(5430 * vertex.y - 5430 * vertex.z) >> 12,
		(2896 * vertex.y + 2896 * vertex.z) >> 12)


## TR3, view3, clamped SZ, screen XY and stored Win95 ushort Z.
static func sample(vertex: Vector3i, camera: Vector3i) -> PackedInt64Array:
	var negative_camera := Vector3i(_short(-camera.x), _short(-camera.y), _short(-camera.z))
	var translation: Vector3i = rotate(negative_camera)
	var view: Vector3i = rotate(Vector3i(_short(vertex.x), _short(vertex.y), _short(vertex.z))) + translation
	var depth: int = maxi(500, view.z)
	@warning_ignore("integer_division")
	var x: int = 320 + view.x * 1000 / depth
	@warning_ignore("integer_division")
	var y: int = 240 + view.y * 1000 / depth
	return PackedInt64Array([translation.x, translation.y, translation.z,
		view.x, view.y, view.z, depth, x, y, depth & 65535])


## Screen X/Y and clamped source-space Z for one raw game vertex.
static func project(vertex: Vector3i, camera: Vector3i) -> Vector3i:
	var values: PackedInt64Array = sample(vertex, camera)
	return Vector3i(values[7], values[8], values[6])


## Ordinary polygon's C ordering bucket, or -1 when RenderMap rejects it.
## ENVMAP/MAX_OT bypass this function and use their explicit far buckets.
static func ordering_bucket(depths: PackedInt32Array) -> int:
	var average: int = 0
	if depths.size() == 3:
		average = (1365 * (depths[0] + depths[1] + depths[2])) >> 12
	elif depths.size() == 4:
		@warning_ignore("integer_division")
		var mean: int = (depths[0] + depths[1] + depths[2] + depths[3]) / 4
		average = mean
	else:
		return -1
	var bucket: int = (average >> 2) + 64
	return -1 if average <= 16 or bucket >= 4096 else bucket


static func _short(value: int) -> int:
	return ((value + 32768) & 65535) - 32768
