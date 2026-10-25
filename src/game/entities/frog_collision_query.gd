class_name FrogCollisionQuery
extends RefCounted
## Exact stored-LW frog point sampling, independent of drawing resources.

## The root/action/cel must be from the last animation pose refresh, not movement.
class Sample:
	extends RefCounted
	var error: String = ""
	var points: Array[Vector3i] = []
	var part_indices := PackedInt32Array()
	var hilite_indices := PackedInt32Array()

	## Returns an independent stored collision pose.
	func copy() -> Sample:
		var result := Sample.new()
		result.error = error
		result.points.assign(points)
		result.part_indices = part_indices.duplicate()
		result.hilite_indices = hilite_indices.duplicate()
		return result

## Composes stored part LW matrices and applies their hilites as frozen C does.
## Collision precedes the next pose refresh: callers retain the resulting sample.
static func sample(definition: FrogCollisionDefinition, action: int, cel: int, root_matrix12: PackedInt32Array) -> Sample:
	var result := Sample.new()
	if definition == null:
		result.error = "Frog collision definition is absent"
		return result
	result.error = validate_matrix(root_matrix12)
	if not result.error.is_empty():
		return result
	if action < 0 or action >= definition.actions.size() or definition.actions[action] == null:
		result.error = "Frog collision action is unavailable"
		return result
	var frames: Array[PackedInt32Array] = definition.actions[action].frames
	if cel < 0 or cel >= frames.size() or frames[cel].size() != definition.part_count * 12:
		result.error = "Frog collision virtual cel is unavailable"
		return result
	var frame: PackedInt32Array = frames[cel]
	var last_part: int = -1
	var lw := PackedInt32Array()
	for probe: FrogCollisionDefinition.Probe in definition.probes:
		if probe == null or probe.part_index < 0 or probe.part_index >= definition.part_count:
			result.error = "Frog collision hilite references an unavailable part"
			result.points.clear()
			return result
		if probe.part_index != last_part:
			last_part = probe.part_index
			lw = compose(root_matrix12, frame.slice(last_part * 12, last_part * 12 + 12))
		var vertex: Vector3i = probe.vertex
		var point := Vector3i.ZERO
		for axis: int in 3:
			# ApplyMatrixSV narrows before adding the stored 32-bit translation;
			# MRCollisionCheck then stores the sum back into the world SVEC.
			var rotated: int = signed16(signed32(lw[axis * 3] * vertex.x + lw[axis * 3 + 1] * vertex.y + lw[axis * 3 + 2] * vertex.z) >> 12)
			point[axis] = signed16(rotated + lw[9 + axis])
		result.points.append(point)
		result.part_indices.append(probe.part_index)
		result.hilite_indices.append(probe.hilite_index)
	return result

## Source fixed12 matrix product and separately rotated part translation.
static func compose(root: PackedInt32Array, part: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(12)
	for row: int in 3:
		for column: int in 3:
			var product: int = 0
			for index: int in 3:
				product += root[row * 3 + index] * part[index * 3 + column]
			result[row * 3 + column] = signed16(signed32(product) >> 12)
		result[row + 9] = signed32((signed32(root[row * 3] * part[9] + root[row * 3 + 1] * part[10] + root[row * 3 + 2] * part[11]) >> 12) + root[row + 9])
	return result

## Validates matrix width before source arithmetic; packed translations are int32.
static func validate_matrix(matrix: PackedInt32Array) -> String:
	if matrix.size() != 12:
		return "Collision matrix requires twelve source values"
	for index: int in 9:
		if matrix[index] < -32768 or matrix[index] > 32767:
			return "Collision matrix rotation is outside signed16"
	return ""

## Narrows a source short store.
static func signed16(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

## Narrows a frozen Windows long accumulator or store.
static func signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low
