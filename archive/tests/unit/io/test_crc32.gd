extends GutTest
## Crc32 against the standard check values.


func test_standard_check_value() -> void:
	assert_eq(Crc32.of_bytes("123456789".to_ascii_buffer()), 0xCBF43926)


func test_empty_input() -> void:
	assert_eq(Crc32.of_bytes(PackedByteArray()), 0)


func test_chunked_update_matches_one_pass() -> void:
	var data: PackedByteArray = "The quick brown fox jumps over the lazy dog".to_ascii_buffer()
	var whole: int = Crc32.of_bytes(data)
	assert_eq(whole, 0x414FA339)
	var chunked: int = Crc32.update(Crc32.update(0, data.slice(0, 10)), data.slice(10))
	assert_eq(chunked, whole)
