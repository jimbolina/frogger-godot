class_name MapGroupVisibility
extends RefCounted
## Frozen MAPVIEW.C single-viewport group selection, independent of drawing.

const HALF_WIDTH: int = 160
const HALF_HEIGHT: int = 120
const PERSPECTIVE: int = 256
const BORDER: int = 768
const GROUP_CAP: int = 128
const POLYGON_BUDGET: int = 2500

## Selects the source-ordered view list or explains why this bounded slice cannot use it.
static func query(lifecycle: EntityLifecycleDefinition, camera: GameplayCameraSnapshot) -> MapGroupVisibilityResult:
	var result := MapGroupVisibilityResult.new()
	if lifecycle == null or camera == null:
		result.error = "Lifecycle visibility requires map groups and a camera"
		return result
	result.error = lifecycle.validate()
	if not result.error.is_empty():
		return result
	if camera.axis_x_12 == Vector3i.ZERO or camera.axis_y_12 == Vector3i.ZERO or camera.axis_z_12 == Vector3i.ZERO:
		result.error = "Lifecycle visibility requires a valid camera frame"
		return result
	for axis: Vector3i in [camera.axis_x_12, camera.axis_y_12, camera.axis_z_12]:
		for coordinate: int in [axis.x, axis.y, axis.z]:
			if coordinate < -32768 or coordinate > 32767:
				result.error = "Lifecycle camera axes must fit source signed16"
				return result
	for coordinate: int in [camera.source_world.x, camera.source_world.y, camera.source_world.z]:
		if coordinate < -2147483648 or coordinate > 2147483647:
			result.error = "Lifecycle camera position must fit source signed32"
			return result
	var corners: Array[Vector3i] = [
		Vector3i(-HALF_WIDTH, HALF_HEIGHT, PERSPECTIVE),
		Vector3i(-HALF_WIDTH, -HALF_HEIGHT, PERSPECTIVE),
		Vector3i(HALF_WIDTH, -HALF_HEIGHT, PERSPECTIVE),
		Vector3i(HALF_WIDTH, HALF_HEIGHT, PERSPECTIVE),
	]
	var intersections: Array[Vector2i] = []
	var border_centre_y: int = 0
	for corner: Vector3i in corners:
		var ray := Vector3i(
			_s32((camera.axis_x_12.x * corner.x + camera.axis_y_12.x * corner.y + camera.axis_z_12.x * corner.z) >> 12),
			_s32((camera.axis_x_12.y * corner.x + camera.axis_y_12.y * corner.y + camera.axis_z_12.y * corner.z) >> 12),
			_s32((camera.axis_x_12.z * corner.x + camera.axis_y_12.z * corner.y + camera.axis_z_12.z * corner.z) >> 12))
		if ray.y <= 0:
			ray.y = 0
			var normal: Vector3i = _normalize(ray)
			intersections.append(Vector2i(_s32(camera.source_world.x + (normal.x << 2)), _s32(camera.source_world.z + (normal.z << 2))))
		else:
			var factor: int = _divide(_s32(-camera.source_world.y << 8), ray.y)
			intersections.append(Vector2i(_s32(camera.source_world.x + (_s32(factor * ray.x) >> 8)), _s32(camera.source_world.z + (_s32(factor * ray.z) >> 8))))
		border_centre_y = ray.y
	var centre := Vector2i(_s32(intersections[0].x + intersections[1].x + intersections[2].x + intersections[3].x) >> 2,
		_s32(intersections[0].y + intersections[1].y + intersections[2].y + intersections[3].y) >> 2)
	for index: int in 4:
		# MAPVIEW replaces only centre X/Z: its final ray Y survives into the
		# border normalization, while the static intersection vectors have Y=0.
		var delta: Vector3i = _normalize(Vector3i(_s32(intersections[index].x - centre.x), -border_centre_y, _s32(intersections[index].y - centre.y)))
		intersections[index] += Vector2i(_s32(delta.x * BORDER) >> 12, _s32(delta.z * BORDER) >> 12)
	intersections.append(Vector2i(camera.source_world.x, camera.source_world.z))
	var translated: Array[Vector2i] = []
	for point: Vector2i in intersections:
		translated.append(Vector2i(_s32(point.x - lifecycle.group_base.x), _s32(point.y - lifecycle.group_base.z)))
	var row_min := PackedInt32Array()
	var row_max := PackedInt32Array()
	for _row: int in lifecycle.group_dimensions.y:
		row_min.append(2147483647)
		row_max.append(-2147483647)
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 0), Vector2i(3, 0)]:
		_draw_line(translated[pair.x], translated[pair.y], lifecycle, row_min, row_max)
	var min_z: int = 2147483647
	var max_z: int = -2147483647
	for point: Vector2i in translated:
		var z: int = _divide(point.y, lifecycle.group_size.y)
		min_z = mini(min_z, z)
		max_z = maxi(max_z, z)
	for z: int in range(maxi(0, min_z), mini(lifecycle.group_dimensions.y - 1, max_z) + 1):
		for x: int in range(maxi(0, row_min[z]), mini(lifecycle.group_dimensions.x - 1, row_max[z]) + 1):
			var group_index: int = z * lifecycle.group_dimensions.x + x
			result.groups.append(group_index)
			result.polygon_total += lifecycle.polygon_counts[group_index]
			if result.groups.size() >= GROUP_CAP:
				break
		if result.groups.size() >= GROUP_CAP:
			break
	if result.polygon_total >= POLYGON_BUDGET:
		result.error = "Lifecycle requires selected map group polygons <2500"
		result.groups = PackedInt32Array()
	return result

static func _draw_line(first: Vector2i, last: Vector2i, lifecycle: EntityLifecycleDefinition, row_min: PackedInt32Array, row_max: PackedInt32Array) -> void:
	var x0: int = first.x
	var z0: int = first.y
	var x1: int = last.x
	var z1: int = last.y
	var delta_z: int = _s32(z1 - z0)
	var min_x: int = _divide(x0, lifecycle.group_size.x)
	var max_x: int = min_x
	var row: int = _divide(z0, lifecycle.group_size.y)
	var last_row: int = _divide(z1, lifecycle.group_size.y)
	var boundary: int = z0
	if z1 > z0:
		boundary = _divide(boundary, lifecycle.group_size.y) * lifecycle.group_size.y + lifecycle.group_size.y
	elif z1 < z0:
		boundary = _divide(boundary, lifecycle.group_size.y) * lifecycle.group_size.y
	while row != last_row:
		if row >= 0 and row < lifecycle.group_dimensions.y:
			if z1 > z0 and boundary >= z1 or z1 < z0 and boundary <= z1:
				break
			var crossing_x: int = 0
			if absi(delta_z) >= 16:
				crossing_x = _s32(_divide(_s32((_s32(boundary - z0) >> 2) * (_s32(x1 - x0) >> 2)), delta_z >> 4) + x0)
			else:
				crossing_x = _s32(z0 + z1) >> 1
			if x1 >= x0:
				max_x = _divide(crossing_x, lifecycle.group_size.x)
			else:
				min_x = _divide(crossing_x, lifecycle.group_size.x)
			row_min[row] = mini(min_x, row_min[row])
			row_max[row] = maxi(max_x, row_max[row])
			if x1 >= x0:
				min_x = max_x
			else:
				max_x = min_x
		else:
			if row < 0 and z1 <= z0 or row >= lifecycle.group_dimensions.y and z1 >= z0:
				return
		if z1 > z0:
			row += 1
			boundary += lifecycle.group_size.y
		else:
			row -= 1
			boundary -= lifecycle.group_size.y
	if row >= 0 and row < lifecycle.group_dimensions.y:
		if x1 >= x0:
			max_x = _divide(x1, lifecycle.group_size.x)
		else:
			min_x = _divide(x1, lifecycle.group_size.x)
		row_min[row] = mini(min_x, row_min[row])
		row_max[row] = maxi(max_x, row_max[row])

static func _normalize(value: Vector3i) -> Vector3i:
	var magnitude: float = sqrt(float(value.x) * value.x + float(value.y) * value.y + float(value.z) * value.z)
	if magnitude < 0.000001:
		return Vector3i.ZERO
	var scale: float = 4096.0 / magnitude
	return Vector3i(roundi(value.x * scale), roundi(value.y * scale), roundi(value.z * scale))

static func _divide(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator

static func _s32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low
