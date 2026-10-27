class_name FormContactQuery
extends RefCounted
## Pure frozen-C FORM point query; it does not run frog reactions or callbacks.

## Queries a detached entity pose using source integer widths and bounds.
static func query(definition: FormContactDefinition, entity_snapshot: EntitySnapshot, probe_world: Vector3i) -> FormContactResult:
	var result := FormContactResult.new()
	if definition == null or entity_snapshot == null:
		result.reason = "Contact requires a definition and entity snapshot"
		return result
	result.entity_index = definition.entity_index
	result.unique_id = definition.unique_id
	result.form_grid_id = definition.form_grid_id
	result.form_id = definition.form_id
	result.form_name = definition.form_name
	if entity_snapshot.entity_index != definition.entity_index or entity_snapshot.unique_id != definition.unique_id:
		result.reason = "Entity snapshot identity does not match contact definition"
		return result
	if not entity_snapshot.live:
		result.status = FormContactResult.DISABLED
		result.reason = "Entity has no live instance"
		return result
	if not definition.disabled_reason.is_empty():
		result.status = FormContactResult.DISABLED
		result.reason = definition.disabled_reason
		return result
	var matrix: PackedInt32Array = entity_snapshot.matrix12
	if matrix.size() != 12:
		result.reason = "Entity matrix requires 12 source values"
		return result
	for index: int in 9:
		if not _fits_signed(matrix[index], 16):
			result.reason = "Entity rotation is outside signed 16-bit source range"
			return result
	for index: int in range(9, 12):
		if not _fits_signed(matrix[index], 32):
			result.reason = "Entity translation is outside signed 32-bit source range"
			return result
	if not _fits_signed(probe_world.x, 32) or not _fits_signed(probe_world.y, 32) or not _fits_signed(probe_world.z, 32):
		result.reason = "Probe position is outside signed 32-bit source range"
		return result
	if entity_snapshot.effective_flags(definition.entity_flags) & EntityDefinition.NO_COLLISION:
		result.status = FormContactResult.DISABLED
		result.reason = "ENTITY_NO_COLLISION"
		return result
	if not definition.unsupported_reason.is_empty():
		result.status = FormContactResult.UNSUPPORTED
		result.reason = definition.unsupported_reason
		return result
	if not definition.has_form_data:
		result.status = FormContactResult.MISS
		result.reason = "FORM has no FORM_DATA fallback"
		return result
	if definition.dimensions.x <= 0 or definition.dimensions.y <= 0 or not _fits_signed(definition.dimensions.x, 16) or not _fits_signed(definition.dimensions.y, 16) or definition.grid_flags.size() != definition.dimensions.x * definition.dimensions.y:
		result.reason = "FORM dimensions or square count are invalid"
		return result
	for flags: int in definition.grid_flags:
		if flags < 0 or flags > 0xffff:
			result.reason = "FORM square flags are outside unsigned 16-bit source range"
			return result
	if not _fits_signed(definition.radius_squared, 32):
		result.reason = "FORM squared radius is outside signed 32-bit source range"
		return result
	if not _fits_signed(definition.height, 16) or not _fits_signed(definition.max_y, 16):
		result.reason = "FORM heights are outside signed 16-bit source range"
		return result
	if not _fits_signed(definition.offsets.x, 16) or not _fits_signed(definition.offsets.y, 16):
		result.reason = "FORM offsets are outside signed 16-bit source range"
		return result
	var delta := Vector3i(_signed16(probe_world.x - matrix[9]), _signed16(probe_world.y - matrix[10]), _signed16(probe_world.z - matrix[11]))
	var distance_squared: int = _signed32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	if distance_squared >= definition.radius_squared:
		result.status = FormContactResult.MISS
		result.reason = "Outside strict form-book bounding sphere"
		return result
	result.local_position = Vector3i(
		_signed32(matrix[0] * delta.x + matrix[3] * delta.y + matrix[6] * delta.z) >> 12,
		_signed32(matrix[1] * delta.x + matrix[4] * delta.y + matrix[7] * delta.z) >> 12,
		_signed32(matrix[2] * delta.x + matrix[5] * delta.y + matrix[8] * delta.z) >> 12)
	var local: Vector3i = result.local_position
	var x_min: int = definition.offsets.x
	var x_max: int = x_min + (definition.dimensions.x << 8)
	var z_min: int = definition.offsets.y
	var z_max: int = z_min + (definition.dimensions.y << 8)
	if local.x <= x_min or local.x >= x_max or local.z <= z_min or local.z >= z_max:
		result.status = FormContactResult.MISS
		result.reason = "Outside strict FORM XZ bounds"
		return result
	if local.y < definition.height or local.y > definition.max_y:
		result.status = FormContactResult.MISS
		result.reason = "Outside inclusive FORM Y bounds"
		return result
	result.cell = Vector2i((local.x - x_min) >> 8, (local.z - z_min) >> 8)
	result.height = definition.height
	result.cell_flags = definition.grid_flags[result.cell.y * definition.dimensions.x + result.cell.x]
	result.status = FormContactResult.CONTACT
	return result

static func _fits_signed(value: int, bits: int) -> bool:
	var limit: int = 1 << (bits - 1)
	return value >= -limit and value < limit

static func _signed16(value: int) -> int:
	var low: int = value & 0xffff
	return low - 0x10000 if low >= 0x8000 else low

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low
