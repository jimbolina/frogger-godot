extends GutTest
## SoundBankHeader survives a resource save and load with its rows.

const PATH: String = "user://test_sound_bank_resources.tres"


func after_all() -> void:
	DirAccess.remove_absolute(PATH)


func test_header_round_trip() -> void:
	var header := SoundBankHeader.new()
	var entry := SoundBankEntry.new()
	entry.sound_id = 3
	entry.source_offset = 88
	entry.audio_present = true
	entry.data_offset = 16
	entry.data_size = 8
	entry.sample_rate = 22050
	entry.sample_bits = 16
	header.entries.append(entry)
	assert_eq(ResourceSaver.save(header, PATH), OK)
	var loaded := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SoundBankHeader
	assert_not_null(loaded)
	var row: SoundBankEntry = loaded.entries[0]
	assert_eq([row.sound_id, row.source_offset, row.audio_present, row.data_offset, row.data_size,
		row.sample_rate, row.sample_bits], [3, 88, true, 16, 8, 22050, 16])
	assert_eq(row.frame_count(), 4)
	assert_null(row.stream)
