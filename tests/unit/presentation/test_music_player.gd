extends GutTest
## MusicPlayer plays the imported Ogg once per selection, loops a copy and stays silent with diagnostics otherwise.

const TRACK: int = 2

var _player: MusicPlayer

func before_each() -> void:
	_player = MusicPlayer.new()
	_player.threaded = false
	add_child_autofree(_player)

func test_imported_track_paths_exist_only_for_imported_tracks() -> void:
	assert_eq(MusicPlayer.imported_track_path(MusicPlayer.IMPORTED_DIR, TRACK), "res://assets/audio/music/track_02.ogg")
	assert_eq(MusicPlayer.imported_track_path(MusicPlayer.IMPORTED_DIR, 99), "")
	assert_eq(MusicPlayer.imported_track_path("", TRACK), "")

func test_the_imported_ogg_is_read_once_and_loops_a_copy() -> void:
	var path: String = MusicPlayer.imported_track_path(MusicPlayer.IMPORTED_DIR, TRACK)
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
