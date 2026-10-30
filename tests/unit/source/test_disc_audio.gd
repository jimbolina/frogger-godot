extends GutTest
## DiscAudio table parsing, validation, location and per-track reads on synthetic disc images.

const ROOT: String = "user://test_disc_audio"

func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)

func after_all() -> void:
	_remove_tree(ROOT)

func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)

func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

## Builds a table with three lead-in rows, then [param lengths] tracks (track 1 data), contiguous unless edited.
func _mds(lengths: Array[int]) -> PackedByteArray:
	var leadins: int = 3
	var session: int = 0x58
	var blocks: int = session + 24
	var extras: int = blocks + (leadins + lengths.size()) * 80
	var bytes := PackedByteArray()
	bytes.resize(extras + lengths.size() * 8)
	for index: int in 16:
		bytes[index] = "MEDIA DESCRIPTOR".unicode_at(index)
	bytes[0x10] = 1
	bytes[0x11] = 5
	bytes.encode_u16(0x12, 1)
	bytes.encode_u16(0x14, 1)
	bytes.encode_u32(0x50, session)
	bytes[session + 0x0A] = leadins + lengths.size()
	bytes.encode_u16(session + 0x0C, 1)
	bytes.encode_u16(session + 0x0E, lengths.size())
	bytes.encode_u32(session + 0x14, blocks)
	for index: int in leadins:
		bytes[blocks + index * 80 + 4] = 0xA0 + index
	var offset: int = 0
	for index: int in lengths.size():
		var block: int = blocks + (leadins + index) * 80
		bytes[block] = 0xEC if index == 0 else 0xA9
		bytes[block + 4] = index + 1
		bytes.encode_u32(block + 0x0C, extras + index * 8)
		bytes.encode_u16(block + 0x10, 2352)
		bytes.encode_s32(block + 0x24, offset / 2352 + (150 if index > 0 else 0))
		bytes.encode_u64(block + 0x28, offset)
		bytes.encode_u32(extras + index * 8, 150 if index > 0 else 0)
		bytes.encode_u32(extras + index * 8 + 4, lengths[index])
		offset += lengths[index] * 2352
	return bytes

func _mdf(lengths: Array[int]) -> PackedByteArray:
	var bytes := PackedByteArray()
	for index: int in lengths.size():
		for byte: int in lengths[index] * 2352:
			bytes.append((index * 64 + byte) & 255)
	return bytes

func test_valid_table_lists_tracks_by_offset() -> void:
	var disc: DiscAudio = DiscAudio.parse_mds(_mds([2, 1, 3]))
	assert_eq(disc.error, "")
	assert_eq(disc.tracks.size(), 3)
	assert_eq(disc.track(1).mode, DiscAudio.MODE_DATA)
	assert_eq(disc.track(2).start_offset, 2 * 2352)
	assert_eq(disc.track(2).start_sector, 152)
	assert_eq(disc.track(2).pregap, 150)
	assert_eq(disc.track(3).start_offset, 3 * 2352)
	assert_eq(disc.track(3).byte_length(), 3 * 2352)
	assert_null(disc.track(4))
	assert_null(disc.track(0))

func test_invalid_tables_are_rejected_by_name() -> void:
	var cases: Dictionary[String, PackedByteArray] = {}
	var bytes: PackedByteArray = _mds([2, 1])
	bytes[0] = 0x58
	cases["not a Media Descriptor"] = bytes
	bytes = _mds([2, 1])
	bytes[0x11] = 4
	cases["version"] = bytes
	bytes = _mds([2, 1])
	bytes.encode_u16(0x14, 2)
	cases["one session"] = bytes
	bytes = _mds([2, 1])
	bytes[0x58 + 24 + 4 * 80] = 0xEC
	cases["mode"] = bytes
	bytes = _mds([2, 1])
	bytes.encode_u16(0x58 + 24 + 4 * 80 + 0x10, 2048)
	cases["sectors"] = bytes
	bytes = _mds([2, 1])
	bytes.encode_u64(0x58 + 24 + 4 * 80 + 0x28, 3 * 2352)
	cases["contiguously"] = bytes
	bytes = _mds([2, 1])
	bytes.encode_u16(0x58 + 0x0E, 3)
	cases["session range"] = bytes
	cases["at least one audio"] = _mds([2])
	cases["outside the table"] = _mds([2, 1]).slice(0, 0x60)
	for expected: String in cases:
		var disc: DiscAudio = DiscAudio.parse_mds(cases[expected])
		assert_string_contains(disc.error, expected)
		assert_eq(disc.tracks.size(), 0)

func test_open_reads_one_track_from_the_image() -> void:
	var lengths: Array[int] = [2, 1, 3]
	_write(ROOT.path_join("GAME.mds"), _mds(lengths))
	var image: PackedByteArray = _mdf(lengths)
	_write(ROOT.path_join("GAME.mdf"), image)
	for path: String in [ROOT, ROOT.path_join("GAME.mds"), ROOT.path_join("GAME.mdf")]:
		var disc: DiscAudio = DiscAudio.open(path)
		assert_eq(disc.error, "")
		assert_eq(disc.mdf_path, ROOT.path_join("GAME.mdf"))
	var opened: DiscAudio = DiscAudio.open(ROOT)
	assert_eq(opened.read_track(3), image.slice(3 * 2352, 6 * 2352))
	assert_eq(opened.read_track(2), image.slice(2 * 2352, 3 * 2352))
	assert_eq(opened.read_track(1).size(), 0)
	assert_string_contains(opened.error, "not an audio track")

func test_image_size_must_match_the_table() -> void:
	var lengths: Array[int] = [2, 1]
	_write(ROOT.path_join("GAME.mds"), _mds(lengths))
	_write(ROOT.path_join("GAME.mdf"), _mdf(lengths).slice(0, 2 * 2352))
	assert_string_contains(DiscAudio.open(ROOT).error, "table ends at")

func test_locate_prefers_the_argument_and_reports_absence() -> void:
	assert_string_contains(DiscAudio.locate(PackedStringArray(), "").error, "No disc image supplied")
	assert_string_contains(DiscAudio.locate(PackedStringArray(["--disc=" + ROOT.path_join("none")]), ROOT).error, "No .mds")
	var lengths: Array[int] = [1, 1]
	_write(ROOT.path_join("GAME.mds"), _mds(lengths))
	_write(ROOT.path_join("GAME.mdf"), _mdf(lengths))
	assert_eq(DiscAudio.locate(PackedStringArray(["--level", "--disc=" + ROOT]), "").error, "")
	assert_eq(DiscAudio.locate(PackedStringArray(), ROOT).mds_path, ROOT.path_join("GAME.mds"))
