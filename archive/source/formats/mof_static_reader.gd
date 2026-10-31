class_name MofStaticReader
extends RefCounted
## Decodes a static model ([MofStatic]) from a model file or from inside an
## animated one, and gives an incomplete model the shape of its counterpart.


## True if a static model starts at [param base] of [param bytes].
static func is_static(bytes: PackedByteArray, base: int = 0) -> bool:
	return bytes.size() >= base + 4 and bytes[base] == 2 and bytes[base + 1] == 0x46 \
		and bytes[base + 2] == 0x4F and bytes[base + 3] == 0x4D


## True if the static model at [param base] of [param bytes] is incomplete.
static func is_incomplete_at(bytes: PackedByteArray, base: int = 0) -> bool:
	return bytes.size() >= base + MofStatic.INCOMPLETE_TEST_OFFSET + 4 \
		and bytes.decode_u32(base + MofStatic.INCOMPLETE_TEST_OFFSET) == MofStatic.INCOMPLETE_TEST_VALUE


## Parses the [param size] bytes at [param base] of [param bytes] ([param
## size] below 0: to the end). An incomplete model takes its shape from
## [param counterpart]. Check [member MofStatic.error].
static func read(bytes: PackedByteArray, base: int = 0, size: int = -1, counterpart: MofStatic = null) -> MofStatic:
	var model := MofStatic.new()
	var reader := ByteReader.new(bytes, base, size)
	if reader.has_error() or not is_static(bytes, base):
		model.error = "not a static model"
		return model
	reader.skip(4)
	model.length = reader.read_u32()
	model.flags = reader.read_u32()
	var part_count: int = reader.read_u32()
	model.is_incomplete = is_incomplete_at(bytes, base)
	if part_count * MofPart.HEADER_SIZE > reader.remaining():
		model.error = "%d parts do not fit in %d bytes" % [part_count, reader.size()]
		return model
	var part_readers: Array[MofPartReader] = []
	for i: int in part_count:
		var part_reader: MofPartReader = MofPartReader.read_header(reader, i)
		part_readers.append(part_reader)
		model.parts.append(part_reader.part)
	model.unknown_word = reader.read_u32()
	var pool_start: int = reader.get_position()
	var pool_end: int = part_readers[0].partcels_at if part_count > 0 else pool_start
	for part_reader: MofPartReader in part_readers:
		part_reader.read_body(reader, pool_start, pool_end, model.is_incomplete)
		if reader.has_error():
			model.error = reader.error
			return model
	if reader.has_error():
		model.error = reader.error
		return model
	var end: int = model.parts[-1].end_offset if part_count > 0 else reader.get_position()
	if end != model.length or model.length != reader.size():
		model.error = "states %d bytes, its data ends at %d, and %d bytes are present" % [model.length, end, reader.size()]
		return model
	if model.is_incomplete:
		model.error = _borrow(model, counterpart)
		if not model.error.is_empty():
			return model
	var expected: int = 0
	if model.texture_animation_target_count() > 0:
		expected |= MofStatic.FLAG_ANIMATED_TEXTURES
	var flipbook_source: MofStatic = counterpart if model.is_incomplete else model
	if flipbook_source.flipbook_action_count() > 0:
		expected |= MofStatic.FLAG_FLIPBOOK
	if model.flags != expected:
		model.error = "flags 0x%X, expected 0x%X from what it holds" % [model.flags, expected]
	return model


static func _borrow(model: MofStatic, counterpart: MofStatic) -> String:
	if counterpart == null or not counterpart.is_valid() or counterpart.is_incomplete:
		return "incomplete, and there is no complete model to take its shape from"
	if counterpart.parts.size() != model.parts.size():
		return "incomplete with %d parts, but the model it takes its shape from has %d" % [model.parts.size(), counterpart.parts.size()]
	for i: int in model.parts.size():
		model.parts[i].borrow_from(counterpart.parts[i])
	return ""
