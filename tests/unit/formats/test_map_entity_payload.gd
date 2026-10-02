extends GutTest
## Synthetic bounded entity base payloads; no retail bytes.

func _span(size: int) -> MapEntitySpan:
	var span := MapEntitySpan.new()
	span.payload.resize(size)
	return span

func test_matrix_reads_signed_row_rotation_and_translation() -> void:
	var span: MapEntitySpan = _span(36)
	for index: int in 9:
		span.payload.encode_s16(index * 2, (index - 4) * 100)
	span.payload.encode_u16(18, 0xFFFF)
	span.payload.encode_s32(20, -123456)
	span.payload.encode_s32(24, 42)
	span.payload.encode_s32(28, 987654)
	var decoded: MapEntityPayload = MapEntityPayload.read_matrix(span)
	assert_eq(decoded.error, "")
	assert_eq(decoded.matrix12.size(), 12)
	assert_eq(decoded.matrix12[0], -400)
	assert_eq(decoded.matrix12[8], 400)
	assert_eq(decoded.matrix12[9], -123456)
	assert_eq(decoded.matrix12[11], 987654)
	span.payload.encode_s16(0, 1)
	assert_eq(decoded.matrix12[0], -400)
	span.payload.resize(31)
	assert_ne(MapEntityPayload.read_matrix(span).error, "")

func test_path_info_reads_unsigned_fields_and_requires_zero_pad() -> void:
	var span: MapEntitySpan = _span(15)
	span.payload.encode_u16(0, 60000)
	span.payload.encode_u16(2, 2)
	span.payload.encode_u16(4, 200)
	span.payload.encode_u16(6, 10)
	span.payload.encode_u16(8, 65535)
	var decoded: MapEntityPayload = MapEntityPayload.read_path_info(span)
	assert_eq(decoded.error, "")
	assert_eq(decoded.path_index, 60000)
	assert_eq(decoded.motion_flags, 10)
	assert_eq(decoded.speed, 65535)
	span.payload.encode_u16(10, 1)
	assert_ne(MapEntityPayload.read_path_info(span).error, "")
	span.payload.resize(11)
	assert_ne(MapEntityPayload.read_path_info(span).error, "")
