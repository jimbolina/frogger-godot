class_name MofAnimatedReader
extends RefCounted
## Decodes the outside of an animated model file ("XAR", [MofAnimated]): its
## header, model sets, authored actions and shared transform pool. The static
## models inside are read by [MofStaticReader].

## The model being read.
var model: MofAnimated
## Where the model sets start.
var sets_at: int = 0
## Where the shared animation data starts.
var shared_at: int = 0
## Where the table of static models starts.
var table_at: int = 0


## True if the first four bytes identify an animated model.
static func has_signature(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4:
		return false
	return bytes[0] in [0, 0x30, 0x31] and bytes[1] >= 0x30 and bytes[1] <= 0x39 and bytes[2] == 0x61 and bytes[3] == 0x78


## Reads only the outside header and static ranges, for counterpart discovery.
static func read_header(bytes: PackedByteArray) -> MofAnimated:
	return _header(bytes).model


## Reads bounded model sets, actions and all six shared transform encodings.
static func read(bytes: PackedByteArray) -> MofAnimated:
	var state: MofAnimatedReader = _header(bytes)
	var animated: MofAnimated = state.model
	if not animated.is_valid():
		return animated
	if animated.transform_code >= MofTransform.SIZES.size():
		animated.error = "unsupported transform encoding %d" % animated.transform_code
		return animated
	var end: int = animated.static_ranges[0].x if not animated.static_ranges.is_empty() else state.table_at
	var reader := ByteReader.new(bytes, 0, end)
	state._read_shared(reader)
	if not reader.has_error():
		state._read_sets(reader)
	animated.error = reader.error
	return animated


## Reads one transform of [param encoding] from a reader already bounded to
## the transform pool.
static func read_transform(reader: ByteReader, encoding: int) -> MofTransform:
	var transform := MofTransform.new()
	transform.code = encoding
	if encoding < 0 or encoding >= MofTransform.SIZES.size():
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


static func _header(bytes: PackedByteArray) -> MofAnimatedReader:
	var state := MofAnimatedReader.new()
	var animated := MofAnimated.new()
	state.model = animated
	var reader := ByteReader.new(bytes)
	if not has_signature(bytes) or bytes.size() < MofAnimated.HEADER_SIZE:
		animated.error = "not an animated model"
		return state
	animated.starts_at_frame_zero = bytes[0] == 0x31
	animated.transform_code = bytes[1] - 0x30
	reader.skip(4)
	animated.length = reader.read_u32()
	animated.flags = reader.read_u32()
	animated.model_set_count = reader.read_u16()
	var static_count: int = reader.read_u16()
	state.sets_at = reader.read_u32()
	state.shared_at = reader.read_u32()
	state.table_at = reader.read_u32()
	if animated.flags != MofAnimated.EXPECTED_FLAGS:
		animated.error = "flags 0x%X, expected 0x%X" % [animated.flags, MofAnimated.EXPECTED_FLAGS]
		return state
	if state.sets_at != MofAnimated.HEADER_SIZE:
		animated.error = "model sets at %d, expected %d" % [state.sets_at, MofAnimated.HEADER_SIZE]
		return state
	if state.table_at + 4 * static_count != animated.length or animated.length != bytes.size():
		animated.error = "states %d bytes, its model table ends at %d, and %d bytes are present" % [animated.length, state.table_at + 4 * static_count, bytes.size()]
		return state
	if state.shared_at < MofAnimated.HEADER_SIZE or state.shared_at >= state.table_at:
		animated.error = "shared animation data outside the animation section"
		return state
	var starts := PackedInt32Array()
	reader.seek(state.table_at)
	for _i: int in static_count:
		starts.append(reader.read_u32())
	for i: int in static_count:
		var end: int = starts[i + 1] if i + 1 < static_count else state.table_at
		if starts[i] <= state.shared_at or end <= starts[i] or end > state.table_at:
			animated.error = "static model %d runs from %d to %d" % [i, starts[i], end]
			return state
		animated.static_ranges.append(Vector2i(starts[i], end - starts[i]))
	animated.error = reader.error
	return state


func _range(reader: ByteReader, at: int, count: int, stride: int, what: String) -> bool:
	if count < 0 or at < MofAnimated.HEADER_SIZE or at > reader.size() or count > (reader.size() - at) / stride:
		reader.fail("%s at %d (%d entries) outside animation data" % [what, at, count])
		return false
	return not reader.has_error()


func _box(reader: ByteReader, at: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	if not _range(reader, at, 1, 64, "bounding box"):
		return values
	for i: int in 8:
		for component: int in 3:
			values.append(reader.s16_at(at + i * 8 + component * 2))
	return values


func _read_shared(reader: ByteReader) -> void:
	if not _range(reader, shared_at, 1, 28, "shared header"):
		return
	reader.seek(shared_at)
	model.shared_flags = reader.read_u32()
	model.transform_count = reader.read_s16()
	var rotations: int = reader.read_s16()
	var translations: int = reader.read_s16()
	var boxes: int = reader.read_s16()
	var at: int = reader.read_u32()
	var rotation_at: int = reader.read_u32()
	var translation_at: int = reader.read_u32()
	var box_at: int = reader.read_u32()
	if model.shared_flags != 9 or rotations != 0 or translations != 0 or rotation_at != 0 or translation_at != 0:
		reader.fail("unsupported shared animation flags or split transforms")
		return
	if not _range(reader, at, model.transform_count, MofTransform.SIZES[model.transform_code], "transforms"):
		return
	reader.seek(at)
	for _i: int in model.transform_count:
		var transform: MofTransform = read_transform(reader, model.transform_code)
		model.transforms.append(transform)
		if model.transform_code >= 4 and transform.raw_values.size() == 11 and transform.raw_values[10] & ~1 != 0:
			var message: String = "undefined scale flags 0x%02X preserved; only bit 0 is applied, as in C" % (transform.raw_values[10] & 255)
			if not model.diagnostics.has(message):
				model.diagnostics.append(message)
	if not _range(reader, box_at, boxes, 64, "shared bounding boxes"):
		return
	for i: int in boxes:
		model.bounding_boxes.append(_box(reader, box_at + i * 64))


func _read_sets(reader: ByteReader) -> void:
	if not _range(reader, sets_at, model.model_set_count, 20, "model sets"):
		return
	for set_index: int in model.model_set_count:
		reader.seek(sets_at + set_index * 20)
		var model_set := MofModelSet.new()
		model_set.flags = reader.read_u32()
		var model_count: int = reader.read_u8()
		var cel_sets: int = reader.read_u8()
		var bbox_sets: int = reader.read_u8()
		reader.skip(1)
		var models_at: int = reader.read_u32()
		var cels_at: int = reader.read_u32()
		var boxes_at: int = reader.read_u32()
		if model_set.flags != 0 or cel_sets != 1 or bbox_sets != 0:
			reader.fail("unsupported model set type, cel sets or per-cel bounding boxes")
			return
		if not _range(reader, models_at, model_count, 24, "models") or not _range(reader, boxes_at, 0, 1, "bounding box sets"):
			return
		for i: int in model_count:
			reader.seek(models_at + i * 24)
			var info := MofModelInfo.new()
			info.animation_type = reader.read_u16()
			info.flags = reader.read_u16()
			info.part_count = reader.read_u16()
			info.static_model_index = reader.read_u16()
			if info.animation_type != 1 or info.flags & ~3 != 0:
				reader.fail("unsupported animation model type or flags")
				return
			var model_cels_at: int = reader.read_u32()
			var box_at: int = reader.read_u32()
			var bbox_set_at: int = reader.read_u32()
			var constraint_at: int = reader.read_u32()
			if model_cels_at != cels_at or constraint_at != 0 or bbox_set_at != 0:
				reader.fail("model has an inconsistent cel set or unsupported constraint/bounding box set")
				return
			if info.flags & 1 != 0 and box_at != 0:
				info.bounding_box = _box(reader, box_at)
			elif info.flags & 1 != 0:
				reader.fail("model's global bounding box pointer is null")
			elif box_at != 0:
				_range(reader, box_at, 0, 1, "unused bounding box pointer")
			model_set.models.append(info)
		_read_actions(reader, cels_at, model_set)
		model.model_sets.append(model_set)
		if reader.has_error():
			return


func _read_actions(reader: ByteReader, cels_at: int, model_set: MofModelSet) -> void:
	if not _range(reader, cels_at, 1, 8, "cel set"):
		return
	reader.seek(cels_at)
	var action_count: int = reader.read_u16()
	reader.skip(2)
	var actions_at: int = reader.read_u32()
	if not _range(reader, actions_at, action_count, 16, "actions"):
		return
	for i: int in action_count:
		reader.seek(actions_at + i * 16)
		var action := MofAction.new()
		action.cel_count = reader.read_u16()
		action.part_count = reader.read_u16()
		action.frame_count = reader.read_u16()
		action.flags = reader.read_u16()
		var numbers_at: int = reader.read_u32()
		var indices_at: int = reader.read_u32()
		var number_count: int = action.frame_count * (3 if action.flags & 2 != 0 else 1)
		var index_count: int = action.cel_count * action.part_count
		if not _range(reader, numbers_at, number_count, 2, "virtual frames") or not _range(reader, indices_at, index_count, 2, "transform indices"):
			return
		for n: int in number_count:
			action.cel_numbers.append(reader.u16_at(numbers_at + n * 2))
		for n: int in index_count:
			var transform_index: int = reader.s16_at(indices_at + n * 2)
			action.transform_indices.append(transform_index)
			if transform_index < 0 or transform_index >= model.transforms.size():
				action.error = "transform index %d is outside the shared pool" % transform_index
		if action.flags != 1 and action.flags != 2:
			action.error = "unsupported action flags %d" % action.flags
		if action.cel_count == 0 or action.part_count == 0 or action.frame_count == 0:
			action.error = "action has no cels, parts or frames"
		if action.flags & 2 != 0 and model.transform_code < 2:
			action.error = "matrix transforms cannot interpolate virtual cels"
		for n: int in number_count:
			var value: int = action.cel_numbers[n]
			if action.flags & 2 != 0 and n % 3 == 2:
				if value > 4096:
					action.error = "interpolation parameter exceeds 4096"
			else:
				var cel: int = value - (1 if action.flags & 2 == 0 and not model.starts_at_frame_zero else 0)
				if cel < 0 or cel >= action.cel_count:
					action.error = "virtual frame names unavailable cel %d" % cel
		model_set.actions.append(action)
