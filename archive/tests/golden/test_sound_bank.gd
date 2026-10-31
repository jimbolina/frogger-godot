extends GutTest
## Independent Windows header facts, edited formats and source-located bounds errors.

func _facts() -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/sound_bank.json"))
	return result

func _bytes(facts: Dictionary) -> PackedByteArray:
	var rows: Array = facts.rows
	var bytes := PackedByteArray()
	bytes.resize(4 + rows.size() * 28)
	bytes.encode_s32(0, rows.size())
	for index: int in rows.size():
		var row: Array = rows[index]
		for field: int in 7:
			var value: int = row[field]
			bytes.encode_s32(4 + index * 28 + field * 4, value)
	return bytes

func test_sound_bank_matches_independent_facts() -> void:
	var facts: Dictionary = _facts()
	var body_size: int = facts.body_size
	var header: SoundBankHeader = SoundBankReader.read(_bytes(facts), body_size, "test.vh")
	assert_eq(header.error, "")
	assert_eq(header.entries.size(), 4)
	for row: Dictionary in facts.facts:
		var entry: SoundBankEntry = header.entries[row.sound_id]
		var observed: Array[int] = [entry.sound_id, entry.source_offset, entry.data_offset, entry.data_size, entry.sample_rate, entry.sample_bits, entry.frame_count()]
		var expected: Array[int] = [row.sound_id, row.source_offset, row.offset, row.size, row.rate, row.bits, row.frames]
		assert_eq(observed, expected)
		var present: bool = row.present
		assert_eq(entry.audio_present, present)

func test_sound_bank_rejects_invalid_spans_and_metadata() -> void:
	var facts: Dictionary = _facts()
	var body_size: int = facts.body_size
	for field: int in [1, 2, 3, 4, 5, 6]:
		var bytes: PackedByteArray = _bytes(facts)
		bytes.encode_s32(4 + field * 4, -1)
		var header: SoundBankHeader = SoundBankReader.read(bytes, body_size, "edited.vh")
		assert_string_contains(header.error, "edited.vh sound 0 at 0x4")
	var bytes: PackedByteArray = _bytes(facts)
	bytes.encode_s32(12, 22051)
	assert_string_contains(SoundBankReader.read(bytes, body_size).error, "partial sample")
	assert_string_contains(SoundBankReader.read(_bytes(facts), 22049).error, "exceeds supplied body")
	bytes = _bytes(facts)
	bytes.resize(bytes.size() - 1)
	assert_string_contains(SoundBankReader.read(bytes, body_size).error, "invalid count")
	bytes = _bytes(facts)
	bytes.encode_s32(0, 2147483647)
	assert_string_contains(SoundBankReader.read(bytes, body_size).error, "invalid count")
