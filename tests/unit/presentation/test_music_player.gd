extends GutTest
## MusicPlayer plays the imported Ogg or WAV track of its folder once per selection, loops a copy of the
## whole track or, for a once-only selection, plays it without a loop, and stays silent with
## diagnostics otherwise.

const TRACK: int = 2
## A folder holding a silent synthetic track 2 as an imported Ogg.
const FIXTURE: String = "res://tests/fixtures/music"

var _player: MusicPlayer

func before_each() -> void:
	_player = MusicPlayer.new()
	_player.threaded = false
	_player.use_folder(FIXTURE)
	add_child_autofree(_player)

func test_imported_track_paths_exist_only_for_imported_tracks() -> void:
	assert_eq(MusicPlayer.imported_track_path(FIXTURE, TRACK), "res://tests/fixtures/music/track_02.ogg")
	assert_eq(MusicPlayer.imported_track_path(FIXTURE, 99), "")
	assert_eq(MusicPlayer.imported_track_path("", TRACK), "")

func test_the_imported_ogg_is_read_once_and_loops_a_copy() -> void:
	var path: String = MusicPlayer.imported_track_path(FIXTURE, TRACK)
	for threaded: bool in [false, true]:
		_player.clear()
		_player.threaded = threaded
		_player.select(TRACK)
		_player.restart()
		_player.finish_loading()
		assert_false(_player.is_loading())
		var stream: AudioStreamOggVorbis = _player.stream() as AudioStreamOggVorbis
		assert_not_null(stream, "threaded %s" % threaded)
		assert_true(stream.loop)
		assert_true(_player.is_playing())
		var shared: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis
		assert_ne(stream, shared)
		assert_false(shared.loop, "the shared import keeps its settings")
		_player.collapse()
		assert_false(_player.is_playing())
		_player.restart()
		assert_same(_player.stream(), stream, "a restart replays the read track")
		assert_true(_player.is_playing())
	assert_eq(_player.diagnostics, PackedStringArray())

func test_a_once_only_selection_plays_without_a_loop_and_a_looping_reselection_replaces_it() -> void:
	_player.select(TRACK, false)
	assert_false(_player.looping)
	_player.restart()
	var once: AudioStreamOggVorbis = _player.stream() as AudioStreamOggVorbis
	assert_not_null(once)
	assert_false(once.loop)
	assert_true(_player.is_playing())
	_player.select(TRACK, false)
	assert_same(_player.stream(), once, "the same once-only selection keeps the read track")
	_player.select(TRACK)
	assert_true(_player.looping)
	assert_null(_player.stream(), "a change of looping is a new selection")
	assert_false(_player.is_playing())
	_player.restart()
	var looped: AudioStreamOggVorbis = _player.stream() as AudioStreamOggVorbis
	assert_not_null(looped)
	assert_true(looped.loop)
	assert_ne(looped, once)
	assert_eq(_player.diagnostics, PackedStringArray())

func test_a_once_only_copy_drops_a_baked_loop() -> void:
	var wav: AudioStreamWAV = _wav(100, AudioStreamWAV.FORMAT_16_BITS, false)
	assert_same(MusicPlayer.once_copy(wav), wav, "a track without a loop is played as it is")
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var once: AudioStreamWAV = MusicPlayer.once_copy(wav) as AudioStreamWAV
	assert_ne(once, wav)
	assert_eq(once.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the shared track keeps its settings")
	var ogg: AudioStreamOggVorbis = load(MusicPlayer.imported_track_path(FIXTURE, TRACK)) as AudioStreamOggVorbis
	assert_same(MusicPlayer.once_copy(ogg), ogg)
	assert_null(MusicPlayer.once_copy(Resource.new()))

func test_a_collapse_while_loading_cancels_the_pending_start() -> void:
	_player.threaded = true
	_player.select(TRACK)
	_player.restart()
	_player.collapse()
	_player.finish_loading()
	assert_not_null(_player.stream())
	assert_false(_player.is_playing())
	_player.restart()
	_player.select(TRACK)
	assert_true(_player.is_playing(), "reselecting the same track keeps it")

func test_a_missing_track_is_silent_with_a_diagnostic() -> void:
	_player.select(99)
	_player.restart()
	assert_null(_player.stream())
	assert_false(_player.is_playing())
	assert_eq(_player.diagnostics.size(), 1)
	assert_string_contains(_player.diagnostics[0], "track 99")
	_player.clear()
	_player.imported_dir = "res://no_such_folder"
	_player.select(TRACK)
	_player.restart()
	assert_false(_player.is_playing())
	assert_eq(_player.diagnostics.size(), 2)

func test_no_track_plays_nothing_and_clear_forgets_the_selection() -> void:
	_player.select(-1)
	_player.restart()
	assert_false(_player.is_playing())
	assert_eq(_player.diagnostics, PackedStringArray())
	_player.select(TRACK)
	_player.restart()
	assert_true(_player.is_playing())
	_player.pause(true)
	_player.clear()
	assert_false(_player.is_playing())
	assert_null(_player.stream())
	assert_eq(_player.track, -1)
	_player.restart()
	assert_false(_player.is_playing())

func _wav(frames: int, format: AudioStreamWAV.Format, stereo: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = format
	wav.stereo = stereo
	wav.mix_rate = 22050
	var bytes: int = frames * (2 if stereo else 1) * (2 if format == AudioStreamWAV.FORMAT_16_BITS else 1)
	var data := PackedByteArray()
	data.resize(bytes)
	wav.data = data
	return wav

func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_a_wav_track_loops_the_whole_track_from_a_copy() -> void:
	for sample: Array in [[1000, AudioStreamWAV.FORMAT_16_BITS, false], [1000, AudioStreamWAV.FORMAT_16_BITS, true],
			[750, AudioStreamWAV.FORMAT_8_BITS, true]]:
		var frames: int = sample[0]
		var format: AudioStreamWAV.Format = sample[1]
		var stereo: bool = sample[2]
		var wav: AudioStreamWAV = _wav(frames, format, stereo)
		assert_eq(MusicPlayer.wav_frames(wav), frames)
		var looped: AudioStreamWAV = MusicPlayer.looping_copy(wav) as AudioStreamWAV
		assert_not_null(looped)
		assert_ne(looped, wav)
		assert_eq(looped.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_eq(looped.loop_begin, 0)
		assert_eq(looped.loop_end, frames)
		assert_eq(looped.data.size(), wav.data.size())
		assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_DISABLED, "the shared track keeps its settings")
	assert_null(MusicPlayer.looping_copy(Resource.new()))

func test_a_runtime_imported_wav_track_is_found_and_played_looping() -> void:
	var folder: String = "user://music_player_test/audio/music"
	_remove(folder)
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	var path: String = folder.path_join("track_05.res")
	assert_eq(ResourceSaver.save(_wav(2205, AudioStreamWAV.FORMAT_16_BITS, true), path), OK)
	assert_eq(MusicPlayer.imported_track_path(folder, 5), path)
	assert_eq(MusicPlayer.imported_track_path(folder, TRACK), "")
	_player.use_folder(folder)
	assert_eq(_player.imported_dir, folder)
	_player.select(5)
	_player.restart()
	var stream: AudioStreamWAV = _player.stream() as AudioStreamWAV
	assert_not_null(stream)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, 2205)
	assert_true(_player.is_playing())
	_player.use_folder(FIXTURE)
	assert_eq(_player.track, -1, "a new folder forgets the selected track")
	assert_null(_player.stream())
	_player.clear()
	_remove(folder)
	_remove("user://music_player_test/audio")
	_remove("user://music_player_test")

func test_the_music_folder_follows_the_catalog_base_root() -> void:
	var catalog := ImportedAssets.new()
	catalog.root = "user://assets/0123456789abcdef"
	assert_eq(MusicPlayer.folder_of(catalog), "user://assets/0123456789abcdef/audio/music")
	assert_eq(MusicPlayer.folder_of(AssetCatalog.new()), "")
	assert_eq(MusicPlayer.folder_of(null), "")
	var fresh := MusicPlayer.new()
	fresh.threaded = false
	add_child_autofree(fresh)
	fresh.select(TRACK)
	fresh.restart()
	assert_false(fresh.is_playing())
	assert_eq(fresh.diagnostics.size(), 1, "no folder chosen is silent with a diagnostic")
