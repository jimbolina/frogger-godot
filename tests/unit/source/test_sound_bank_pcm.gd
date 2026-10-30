extends GutTest
## SoundBankPcm slicing and sample widening on synthetic bank bodies.

func _entry(offset: int, size: int, bits: int, present: bool = true) -> SoundBankEntry:
	var entry := SoundBankEntry.new()
	entry.sound_id = 7
	entry.audio_present = present
	entry.data_offset = offset
	entry.data_size = size
	entry.sample_rate = 11025
	entry.sample_bits = bits
	return entry

func _body() -> PackedByteArray:
	var body := PackedByteArray()
	for index: int in 16:
		body.append(index * 16)
	return body

func test_sixteen_bit_span_is_sliced_and_kept_signed() -> void:
	var pcm: SoundBankPcm = SoundBankPcm.slice(_entry(4, 6, 16), _body())
	assert_eq(pcm.error, "")
	assert_eq(pcm.bytes, PackedByteArray([64, 80, 96, 112, 128, 144]))
	assert_eq(pcm.frame_count(), 3)
	var wide: PackedByteArray = pcm.to_signed_16()
	assert_eq(wide, pcm.bytes)
	assert_eq(wide.decode_s16(4), -28544)

func test_eight_bit_span_is_recentred_and_widened() -> void:
	var body := PackedByteArray([9, 0, 128, 255, 9])
	var pcm: SoundBankPcm = SoundBankPcm.slice(_entry(1, 3, 8), body)
	assert_eq(pcm.error, "")
	assert_eq(pcm.frame_count(), 3)
	var wide: PackedByteArray = pcm.to_signed_16()
	assert_eq(wide.size(), 6)
	assert_eq(wide.decode_s16(0), -32768)
	assert_eq(wide.decode_s16(2), 0)
	assert_eq(wide.decode_s16(4), 32512)

func test_span_ending_at_the_body_end_is_accepted() -> void:
	assert_eq(SoundBankPcm.slice(_entry(14, 2, 16), _body()).bytes, PackedByteArray([224, 240]))

func test_invalid_rows_are_rejected_without_bytes() -> void:
	var cases: Array[SoundBankEntry] = [
		_entry(0, 4, 16, false),
		_entry(0, 4, 12),
		_entry(14, 4, 16),
		_entry(17, 0, 16),
		_entry(-2, 4, 16),
		_entry(0, 0, 16),
		_entry(0, 3, 16),
	]
	for entry: SoundBankEntry in cases:
		var pcm: SoundBankPcm = SoundBankPcm.slice(entry, _body())
		assert_ne(pcm.error, "")
		assert_eq(pcm.bytes.size(), 0)
		assert_eq(pcm.frame_count(), 0)
	assert_ne(SoundBankPcm.slice(null, _body()).error, "")
