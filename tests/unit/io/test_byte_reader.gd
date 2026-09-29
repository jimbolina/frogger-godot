extends GutTest
## ByteReader: widths, sign, endianness, windows, strings and sticky errors.


func _bytes(values: Array[int]) -> PackedByteArray:
	return PackedByteArray(values)


func test_reads_little_endian_widths() -> void:
	var r := ByteReader.new(_bytes([0x01, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12, 0xFF, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
	assert_eq(r.read_u8(), 0x01)
	assert_eq(r.read_u16(), 0x1234)
	assert_eq(r.read_u32(), 0x12345678)
	assert_eq(r.read_s8(), -1)
	assert_eq(r.read_s16(), -2)
	assert_eq(r.read_u32(), 0xFFFFFFFF)
	assert_false(r.has_more())
	assert_false(r.has_error())


func test_signed_32_bit() -> void:
	var r := ByteReader.new(_bytes([0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x80]))
	assert_eq(r.read_s32(), -1)
	assert_eq(r.read_s32(), -2147483648)


func test_reading_past_the_end_is_a_sticky_error() -> void:
	var r := ByteReader.new(_bytes([1, 2, 3]))
	assert_eq(r.read_u16(), 0x0201)
	assert_eq(r.read_u16(), 0, "a short read returns 0")
	assert_true(r.has_error())
	assert_string_contains(r.error, "exceeds")
	assert_eq(r.read_u8(), 0, "reads after an error return 0 even if bytes remain")


func test_seek_skip_align_and_remaining() -> void:
	var r := ByteReader.new(PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8]))
	r.skip(1)
	r.align(4)
	assert_eq(r.get_position(), 4)
	assert_eq(r.remaining(), 5)
	r.seek(9)
	assert_false(r.has_error(), "seeking to exactly the end is allowed")
	r.seek(10)
	assert_true(r.has_error())


func test_sub_reader_shares_the_buffer_with_its_own_origin() -> void:
	var r := ByteReader.new(PackedByteArray([9, 9, 0x11, 0x22, 0x33, 0x44, 9]))
	var sub: ByteReader = r.sub_reader(2, 4)
	assert_eq(sub.size(), 4)
	assert_eq(sub.get_base(), 2)
	assert_eq(sub.read_u32(), 0x44332211)
	assert_eq(sub.read_u8(), 0, "the sub-window ends before the parent's last byte")
	assert_true(sub.has_error())
	assert_false(r.has_error(), "a child's error does not leak into the parent")


func test_sub_reader_out_of_range() -> void:
	var r := ByteReader.new(PackedByteArray([1, 2, 3]))
	var sub: ByteReader = r.sub_reader(2, 5)
	assert_true(sub.has_error())
	assert_true(r.has_error())


func test_absolute_reads_do_not_move_the_cursor() -> void:
	var r := ByteReader.new(PackedByteArray([0x78, 0x56, 0x34, 0x12, 0xFE, 0xFF]))
	assert_eq(r.u32_at(0), 0x12345678)
	assert_eq(r.s16_at(4), -2)
	assert_eq(r.u16_at(4), 0xFFFE)
	assert_eq(r.get_position(), 0)
	assert_eq(r.u32_at(4), 0)
	assert_true(r.has_error())


func test_fixed_and_terminated_strings() -> void:
	var data: PackedByteArray = "ABC".to_ascii_buffer()
	data.append_array(PackedByteArray([0, 0x5A, 0x5A]))
	data.append_array("HELLO".to_ascii_buffer())
	data.append(0)
	var r := ByteReader.new(data)
	assert_eq(r.read_fixed_string(6), "ABC", "text stops at the NUL, cursor moves the full width")
	assert_eq(r.get_position(), 6)
	assert_eq(r.read_cstring(), "HELLO")
	assert_eq(r.get_position(), data.size())
	assert_eq(r.cstring_at(0), "ABC")


func test_unterminated_string_is_an_error() -> void:
	var r := ByteReader.new("NOEND".to_ascii_buffer())
	assert_eq(r.read_cstring(), "")
	assert_true(r.has_error())


func test_signature() -> void:
	var r := ByteReader.new("DAWM".to_ascii_buffer())
	assert_true(r.expect_signature("DAWM"))
	var bad := ByteReader.new("MAWD".to_ascii_buffer())
	assert_false(bad.expect_signature("DAWM"))
	assert_string_contains(bad.error, "DAWM")


func test_window_constructor_bounds() -> void:
	var r := ByteReader.new(PackedByteArray([1, 2, 3, 4]), 1, 2)
	assert_eq(r.size(), 2)
	assert_eq(r.read_u16(), 0x0302)
	var too_long := ByteReader.new(PackedByteArray([1, 2]), 1, 5)
	assert_true(too_long.has_error())
	assert_eq(too_long.size(), 1)
	assert_eq(ByteReader.new(PackedByteArray([1]), 5).size(), 0)


func test_read_bytes_copies() -> void:
	var r := ByteReader.new(PackedByteArray([1, 2, 3, 4]))
	r.skip(1)
	assert_eq(r.read_bytes(2), PackedByteArray([2, 3]))
	assert_eq(r.to_bytes(), PackedByteArray([1, 2, 3, 4]))
	assert_eq(r.read_bytes(5), PackedByteArray())
	assert_true(r.has_error())
