extends GutTest
## MusicPlayer plays the imported Ogg, else reads the level's disc track or a supplied file once, loops it and stays silent with diagnostics otherwise.

const ROOT: String = "user://test_music_player"

var _player: MusicPlayer

func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("data"))
	_player = MusicPlayer.new()
	_player.threaded = false
	_player.imported_dir = ""
	add_child_autofree(_player)

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

## Writes an image whose track 1 is data and later tracks are audio, each [param lengths] sectors long.
func _disc(lengths: Array[int]) -> DiscAudio:
	var leadins: int = 3
	var session: int = 0x58
	var blocks: int = session + 24
	var extras: int = blocks + (leadins + lengths.size()) * 80
	var table := PackedByteArray()
	table.resize(extras + lengths.size() * 8)
	for index: int in 16:
		table[index] = DiscAudio.SIGNATURE.unicode_at(index)
	table[0x10] = 1
	table[0x11] = 5
	table.encode_u16(0x12, 1)
	table.encode_u16(0x14, 1)
	table.encode_u32(0x50, session)
	table[session + 0x0A] = leadins + lengths.size()
	table.encode_u16(session + 0x0C, 1)
	table.encode_u16(session + 0x0E, lengths.size())
	table.encode_u32(session + 0x14, blocks)
	for index: int in leadins:
		table[blocks + index * 80 + 4] = 0xA0 + index
	var offset: int = 0
	for index: int in lengths.size():
		var block: int = blocks + (leadins + index) * 80
		table[block] = DiscAudio.MODE_DATA if index == 0 else DiscAudio.MODE_AUDIO
		table[block + 4] = index + 1
		table.encode_u32(block + 0x0C, extras + index * 8)
		table.encode_u16(block + 0x10, DiscAudio.SECTOR_BYTES)
		table.encode_u64(block + 0x28, offset)
		table.encode_u32(extras + index * 8 + 4, lengths[index])
		offset += lengths[index] * DiscAudio.SECTOR_BYTES
	var image := PackedByteArray()
	image.resize(offset)
	_write(ROOT.path_join("game.mds"), table)
	_write(ROOT.path_join("game.mdf"), image)
	return DiscAudio.open(ROOT.path_join("game.mds"))

func _music_file(track: int) -> String:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("data/music"))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(2000)
	wav.data = data
	var path: String = ROOT.path_join("data/music/track_%02d.wav" % track)
	assert_eq(wav.save_to_wav(path), OK)
	return path

func test_the_disc_track_is_read_once_and_loops_from_memory() -> void:
	var disc: DiscAudio = _disc([2, 3, 1])
	assert_eq(disc.error, "")
	_player.select(disc, 2)
	_player.restart()
	var stream: AudioStreamWAV = _player.stream() as AudioStreamWAV
	assert_not_null(stream)
	assert_true(_player.is_playing())
	assert_true(stream.stereo)
	assert_eq(stream.mix_rate, DiscAudio.SAMPLE_RATE)
	assert_eq(stream.data.size(), 3 * DiscAudio.SECTOR_BYTES)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	_player.collapse()
	assert_false(_player.is_playing())
	_player.restart()
	assert_same(_player.stream(), stream, "a restart replays the read track")
	assert_true(_player.is_playing())
	assert_eq(_player.diagnostics, PackedStringArray())

func test_a_threaded_read_plays_once_finished_unless_collapsed_meanwhile() -> void:
	var disc: DiscAudio = _disc([2, 1])
	_player.threaded = true
	_player.select(disc, 2)
	_player.restart()
	_player.finish_loading()
	assert_false(_player.is_loading())
	assert_true(_player.is_playing())
	_player.select(disc, 2)
	assert_true(_player.is_playing(), "reselecting the same track keeps it")
	_player.clear()
	_player.select(disc, 2)
	_player.restart()
	_player.collapse()
	_player.finish_loading()
	assert_not_null(_player.stream())
	assert_false(_player.is_playing(), "the collapse cancels the pending start")

func test_a_supplied_file_stands_in_when_the_disc_is_absent() -> void:
	var absent: DiscAudio = DiscAudio.locate(PackedStringArray(), "")
	_music_file(4)
	_player.select(absent, 4, ProjectSettings.globalize_path(ROOT.path_join("data")))
	_player.restart()
	var stream: AudioStreamWAV = _player.stream() as AudioStreamWAV
	assert_not_null(stream)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, 1000)
	assert_true(_player.is_playing())
	assert_eq(_player.diagnostics, PackedStringArray([absent.error]))

func test_without_a_disc_or_file_the_level_is_silent_with_diagnostics() -> void:
	var absent: DiscAudio = DiscAudio.locate(PackedStringArray(), "")
	_player.select(absent, 7, ProjectSettings.globalize_path(ROOT.path_join("data")))
	_player.restart()
	assert_null(_player.stream())
	assert_false(_player.is_playing())
	assert_eq(_player.diagnostics.size(), 2)
	assert_string_contains(_player.diagnostics[0], DiscAudio.ENVIRONMENT_VARIABLE)
	assert_string_contains(_player.diagnostics[1], "track_07")
	var data_track: DiscAudio = _disc([2, 1])
	_player.select(data_track, 1)
	_player.restart()
	assert_false(_player.is_playing())
	assert_string_contains(_player.diagnostics[2], "not an audio track")

func test_no_track_plays_nothing_and_clear_forgets_the_selection() -> void:
	_player.select(null, -1)
	_player.restart()
	assert_false(_player.is_playing())
	assert_eq(_player.diagnostics, PackedStringArray())
	_player.select(_disc([2, 1]), 2)
	_player.restart()
	assert_true(_player.is_playing())
	_player.pause(true)
	_player.clear()
	assert_false(_player.is_playing())
	assert_null(_player.stream())
	assert_eq(_player.track, -1)
	_player.restart()
	assert_false(_player.is_playing())

func test_the_imported_ogg_comes_first_and_loops_a_copy() -> void:
	var path: String = MusicPlayer.imported_track_path(MusicPlayer.IMPORTED_DIR, 2)
	assert_eq(path, "res://assets/audio/music/track_02.ogg")
	assert_eq(MusicPlayer.imported_track_path(MusicPlayer.IMPORTED_DIR, 99), "")
	assert_eq(MusicPlayer.imported_track_path("", 2), "")
	for threaded: bool in [false, true]:
		_player.clear()
		_player.threaded = threaded
		_player.imported_dir = MusicPlayer.IMPORTED_DIR
		_player.select(_disc([2, 1]), 2)
		_player.restart()
		_player.finish_loading()
		var stream: AudioStreamOggVorbis = _player.stream() as AudioStreamOggVorbis
		assert_not_null(stream, "threaded %s" % threaded)
		assert_true(stream.loop)
		assert_true(_player.is_playing())
		var shared: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis
		assert_ne(stream, shared)
		assert_false(shared.loop, "the shared import keeps its settings")
	assert_eq(_player.diagnostics, PackedStringArray())
