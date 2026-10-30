extends GutTest
## MusicFiles search order, naming and diagnostics on synthetic folders.

const ROOT: String = "user://test_music_files"
const DATA: String = ROOT + "/game/FROGGER"
const USER_MUSIC: String = ROOT + "/user_music"

func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(DATA)

func after_all() -> void:
	_remove_tree(ROOT)

func _write(path: String, size: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var bytes := PackedByteArray()
	bytes.resize(size)
	file.store_buffer(bytes)
	file.close()

func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)

func test_absent_track_reports_the_expected_names() -> void:
	var found: MusicFiles = MusicFiles.resolve(4, DATA, USER_MUSIC)
	assert_eq(found.path, "")
	assert_eq(found.diagnostics.size(), 1)
	assert_string_contains(found.diagnostics[0], "track_04.ogg")

func test_search_order_prefers_the_data_folder_then_its_sibling_then_user_folder() -> void:
	assert_eq(MusicFiles.folders(DATA, USER_MUSIC), PackedStringArray([DATA + "/music", ROOT + "/game/music", USER_MUSIC]))
	assert_eq(MusicFiles.folders("", USER_MUSIC), PackedStringArray([USER_MUSIC]))
	_write(USER_MUSIC + "/track_12.wav", 8)
	assert_eq(MusicFiles.resolve(12, DATA, USER_MUSIC).path, USER_MUSIC + "/track_12.wav")
	_write(ROOT + "/game/music/track_12.mp3", 8)
	assert_eq(MusicFiles.resolve(12, DATA, USER_MUSIC).path, ROOT + "/game/music/track_12.mp3")
	_write(DATA + "/music/track_12.ogg", 8)
	var found: MusicFiles = MusicFiles.resolve(12, DATA, USER_MUSIC)
	assert_eq(found.path, DATA + "/music/track_12.ogg")
	assert_eq(found.diagnostics.size(), 0)

func test_extension_order_within_a_folder() -> void:
	_write(DATA + "/music/track_02.mp3", 8)
	_write(DATA + "/music/track_02.wav", 8)
	assert_eq(MusicFiles.resolve(2, DATA, USER_MUSIC).path, DATA + "/music/track_02.wav")

func test_empty_file_is_reported_and_skipped() -> void:
	_write(DATA + "/music/track_07.ogg", 0)
	_write(USER_MUSIC + "/track_07.ogg", 8)
	var found: MusicFiles = MusicFiles.resolve(7, DATA, USER_MUSIC)
	assert_eq(found.path, USER_MUSIC + "/track_07.ogg")
	assert_eq(found.diagnostics.size(), 1)
	assert_string_contains(found.diagnostics[0], "unreadable or empty")

func test_out_of_range_track_is_reported() -> void:
	var found: MusicFiles = MusicFiles.resolve(100, DATA, USER_MUSIC)
	assert_eq(found.path, "")
	assert_eq(found.diagnostics.size(), 1)
