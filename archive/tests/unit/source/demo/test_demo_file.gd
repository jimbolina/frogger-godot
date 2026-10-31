extends GutTest
## Synthetic demo headers and raw-byte preservation.


func _bytes(duration: int, x: int, z: int, inputs: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_s32(0, duration)
	bytes.encode_s32(4, x)
	bytes.encode_s32(8, z)
	bytes.append_array(inputs)
	return bytes


func test_header_and_every_action_bit_are_preserved() -> void:
	var inputs := PackedByteArray([0, 1, 2, 3, 4, 8, 16, 32, 64, 128, 255])
	var demo: SourceDemoFile = SourceDemoFileReader.parse(_bytes(900, 42, 73, inputs))
	assert_true(demo.is_valid())
	assert_eq(demo.duration, 900)
	assert_eq(demo.start_grid_x, 42)
	assert_eq(demo.start_grid_z, 73)
	assert_eq(demo.input_bytes, inputs)
	assert_eq(demo.input_at(10), 255)
	assert_eq(demo.input_at(11), -1)
	assert_eq(demo.input_at(-1), -1)


func test_duration_is_not_the_input_buffer_length() -> void:
	var demo: SourceDemoFile = SourceDemoFileReader.parse(_bytes(1800, 0, 0, PackedByteArray([128])))
	assert_true(demo.is_valid())
	assert_eq(demo.input_bytes.size(), 1)
	assert_true(SourceDemoFileReader.parse(_bytes(0, 0, 0, PackedByteArray())).is_valid())


func test_short_header_and_negative_fields_report_resource() -> void:
	for size: int in 12:
		var bytes := PackedByteArray()
		bytes.resize(size)
		assert_string_contains(SourceDemoFileReader.parse(bytes, "MOD.DAT").error, "MOD.DAT")
	for header: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1)]:
		assert_false(SourceDemoFileReader.parse(_bytes(header.x, header.y, header.z, PackedByteArray())).is_valid())


func test_decoded_bytes_are_detached_from_input() -> void:
	var bytes: PackedByteArray = _bytes(1, 2, 3, PackedByteArray([5]))
	var demo: SourceDemoFile = SourceDemoFileReader.parse(bytes)
	bytes[12] = 7
	assert_eq(demo.input_at(0), 5)


func test_extended_recordings_preserve_all_stored_inputs() -> void:
	var inputs := PackedByteArray()
	inputs.resize(1900)
	inputs[1899] = 253
	var demo: SourceDemoFile = SourceDemoFileReader.parse(_bytes(2000, 0, 0, inputs))
	assert_true(demo.is_valid())
	assert_eq(demo.input_bytes.size(), 1900)
	assert_eq(demo.input_at(1899), 253)
