extends RetailTest
## Supplied executable table identities, edited records and independent bank durations.

func _data() -> GameData:
	return GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func test_retail_sound_tables_and_durations_match_independent_facts() -> void:
	var data: GameData = _data()
	assert_eq(data.error, "")
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/sound_tables.json"))
	var tables: SoundTables = SoundTablesReader.read(data.exe)
	assert_eq(tables.error, "")
	assert_eq(tables.samples.size(), 174)
	for index: int in tables.banks.size():
		var row: Array = facts.banks[index]
		var x: int = row[0]
		var y: int = row[1]
		assert_eq(tables.banks[index], Vector2i(x, y))
	for index: int in tables.groups.size():
		var row: Array = facts.groups[index]
		var x: int = row[0]
		var y: int = row[1]
		assert_eq(tables.groups[index], Vector2i(x, y))
	for index: int in tables.music_pitches.size():
		var row: Array = facts.music_pitches[index]
		var x: int = row[0]
		var y: int = row[1]
		assert_eq(tables.music_pitches[index], Vector2i(x, y))
	for sample: SoundSampleEntry in tables.samples:
		var observed: Array[int] = [sample.flags, sample.bank_id, sample.group_id, sample.program, sample.tone, sample.note, sample.pitch_mod, sample.minimum_volume, sample.maximum_volume]
		var expected: Array[int] = []
		var expected_row: Array = facts.samples[sample.sound_id]
		expected.assign(expected_row)
		assert_eq(observed, expected)
	var code: Dictionary = facts.initialization
	var offset: int = code.file_offset
	var length: int = code.length
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(data.exe.bytes.slice(offset, offset + length))
	var expected_hash: String = code.sha256
	assert_eq(hash_context.finish().hex_encode(), expected_hash)
	for bank: Dictionary in facts.headers:
		var header_id: int = bank.header_id
		var body_id: int = bank.body_id
		var problems := PackedStringArray()
		var body_size: int = data.read_resource(body_id, problems).size()
		var header: SoundBankHeader = SoundBankReader.read(data.read_resource(header_id, problems), body_size, data.mwi.get_entry(header_id).display_name())
		assert_eq(problems, PackedStringArray())
		assert_eq(header.error, "")
		var count: int = bank.count
		assert_eq(header.entries.size(), count)
		for row: Array in bank.rows:
			var entry: SoundBankEntry = header.entries[row[0]]
			var observed: Array[int] = [entry.sound_id, entry.data_offset, entry.data_size, entry.sample_rate, entry.sample_bits, entry.frame_count()]
			var expected: Array[int] = []
			expected.assign(row)
			assert_eq(observed, expected)
			assert_true(entry.audio_present)
	var logical: LogicalSoundSetup = LogicalSoundSetup.from_data(data, PackedInt32Array([0, 5]))
	assert_eq(logical.error, "")
	assert_gt(logical.definitions.size(), 32)
	assert_eq(LogicalSoundState.create(logical.definitions).error, "")

func test_saved_sound_table_edits_are_resolved_and_unknown_groups_diagnosed() -> void:
	var data: GameData = _data()
	var bytes: PackedByteArray = data.exe.bytes.duplicate()
	var offset: int = data.exe.pointer_to_offset(SoundTables.SAMPLE_ADDRESS)
	bytes.encode_u16(offset + 12, 72)
	bytes.encode_u16(offset + 14, 512)
	bytes.encode_u32(offset, LogicalSoundDefinition.LOOPED)
	var edited: ExeImage = ExeImage.create(bytes, data.version)
	var tables: SoundTables = SoundTablesReader.read(edited)
	assert_eq(tables.error, "")
	assert_eq(tables.samples[0].note, 72)
	assert_eq(tables.samples[0].pitch_mod, 512)
	assert_eq(tables.samples[0].flags, LogicalSoundDefinition.LOOPED)
	bytes.encode_u16(offset + 6, 4)
	tables = SoundTablesReader.read(ExeImage.create(bytes, data.version))
	assert_string_contains(tables.error, "Sound sample 0 at 0x46F938")
