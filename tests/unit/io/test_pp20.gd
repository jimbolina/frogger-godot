extends GutTest
## Pp20 against streams built by an independent test packer.

var _packer := Pp20TestPacker.new()
var _unpacker := Pp20.new()


func _sample(size: int, seed_value: int) -> PackedByteArray:
	# Text-like data: repeated words with some noise, so copies of every length occur.
	var words: Array[String] = ["frog ", "log ", "turtle ", "lorry ", "croak ", "hop ", "the "]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedByteArray()
	while out.size() < size:
		if rng.randi_range(0, 9) == 0:
			out.append(rng.randi_range(0, 255))
		else:
			out.append_array(words[rng.randi_range(0, words.size() - 1)].to_ascii_buffer())
	return out.slice(0, size)


func _round_trip(data: PackedByteArray, window: int = 700, literals_only: bool = false) -> void:
	var packed: PackedByteArray = _packer.pack(data, window, literals_only)
	assert_true(Pp20.is_packed(packed))
	assert_eq(Pp20.unpacked_size(packed), data.size())
	var out: PackedByteArray = _unpacker.unpack(packed)
	assert_eq(_unpacker.error, "")
	assert_eq(out, data)


func test_literals_only() -> void:
	_round_trip("Frogger!".to_ascii_buffer(), 0, true)


func test_single_byte() -> void:
	_round_trip(PackedByteArray([0x42]))


func test_long_literal_run_length_encoding() -> void:
	var data := PackedByteArray()
	for i: int in 50:
		data.append((i * 37 + 11) & 0xFF)
	_round_trip(data, 0, true)


func test_run_of_one_byte_uses_overlapping_copies() -> void:
	var data := PackedByteArray()
	data.resize(500)
	data.fill(0x7E)
	_round_trip(data)


func test_text_like_data() -> void:
	_round_trip(_sample(3000, 1))
	_round_trip(_sample(1500, 2))


func test_far_copies_use_the_wide_offset_fields() -> void:
	var block: PackedByteArray = _sample(40, 3)
	var data: PackedByteArray = block.duplicate()
	var filler := PackedByteArray()
	for i: int in 3000:
		filler.append((i * 131 + (i >> 3) * 7) & 0xFF)
	data.append_array(filler)
	data.append_array(block)
	_round_trip(data, 8192)


func test_compresses_repetitive_data() -> void:
	var data := PackedByteArray()
	for i: int in 400:
		data.append_array("ABCD".to_ascii_buffer())
	var packed: PackedByteArray = _packer.pack(data)
	assert_lt(packed.size(), data.size() / 4, "the test packer really uses copies")
	assert_eq(_unpacker.unpack(packed), data)


func test_not_pp20() -> void:
	assert_false(Pp20.is_packed("PP21xxxxxxxxxxxx".to_ascii_buffer()))
	assert_false(Pp20.is_packed("PP20".to_ascii_buffer()), "too short to be a stream")
	assert_eq(Pp20.unpacked_size(PackedByteArray([1, 2, 3])), -1)
	assert_eq(_unpacker.unpack("hello world, not packed".to_ascii_buffer()), PackedByteArray())
	assert_eq(_unpacker.error, "not PP20 data")


func test_truncated_stream_fails_cleanly() -> void:
	var packed: PackedByteArray = _packer.pack(_sample(800, 4))
	# Drop bytes from the middle of the bit stream, keeping header and trailer.
	var cut: PackedByteArray = packed.slice(0, 8)
	cut.append_array(packed.slice(packed.size() - 40))
	var out: PackedByteArray = _unpacker.unpack(cut)
	assert_eq(out, PackedByteArray())
	assert_ne(_unpacker.error, "")


func test_size_field_larger_than_the_stream() -> void:
	var packed: PackedByteArray = _packer.pack("tiny".to_ascii_buffer(), 0, true)
	packed[packed.size() - 3] = 0x40 # claim 16 KB of output
	assert_eq(_unpacker.unpack(packed), PackedByteArray())
	assert_ne(_unpacker.error, "")
