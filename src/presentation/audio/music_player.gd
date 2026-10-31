class_name MusicPlayer
extends Node
## Plays the level's music track on the [constant BUS] bus, looping, from the imported Ogg, the player's disc image or a supplied track file.
##
## The track number comes from the executable's music list
## ([method MusicTable.track_for_level]). The imported
## [code]track_NN.ogg[/code] under [member imported_dir] is used when it
## exists, loaded through Godot's threaded resource loader. Otherwise a
## readable disc image supplies the Redbook track, and failing that a
## [MusicFiles] file named after the same track is used. Without either the level is silent and [member diagnostics] says why.
## A track is read once per selection, off the main thread unless
## [member threaded] is false, and replayed from memory on each restart.

## Bus the music plays on.
const BUS: StringName = &"Music"
## Where the importer writes the level music.
const IMPORTED_DIR: String = "res://assets/audio/music"

## Why the selected track is silent, newest last.
var diagnostics := PackedStringArray()
## Reads tracks on a worker thread; tests turn this off for deterministic loading.
var threaded: bool = true
## Selected disc track number, or -1.
var track: int = -1
## Folder of imported [code]track_NN.ogg[/code] files tried first; empty skips them.
var imported_dir: String = IMPORTED_DIR
var _player: AudioStreamPlayer = null
var _disc: DiscAudio = null
var _files_dir: String = ""
var _stream: AudioStream = null
var _task: int = -1
var _loaded: AudioStream = null
var _load_issues := PackedStringArray()
var _wanted: bool = false
var _request: String = ""

func _init() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	add_child(_player)

func _ready() -> void:
	SoundVoiceView.ensure_bus(BUS, &"Master")
	_player.bus = BUS

func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		finish_loading()
	elif not _request.is_empty() and ResourceLoader.load_threaded_get_status(_request) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		finish_loading()

func _exit_tree() -> void:
	clear()

## Selects track [param number] from [param disc] or, failing that, a file found by [MusicFiles] beside [param files_dir]; a new selection stops the old one.
func select(disc: DiscAudio, number: int, files_dir: String = "") -> void:
	if disc == _disc and number == track and files_dir == _files_dir:
		return
	clear()
	_disc = disc
	track = number
	_files_dir = files_dir

## Plays the selected track from its start, reading it first when needed.
func restart() -> void:
	_player.stop()
	if track < 0:
		return
	_wanted = true
	if _stream != null:
		_play()
		return
	if _task >= 0 or not _request.is_empty():
		return
	_loaded = null
	_load_issues = PackedStringArray()
	var imported: String = imported_track_path(imported_dir, track)
	if not imported.is_empty():
		if threaded and ResourceLoader.load_threaded_request(imported) == OK:
			_request = imported
			return
		_accept_imported(imported, ResourceLoader.load(imported))
		return
	if threaded:
		_task = WorkerThreadPool.add_task(_load.bind(_disc, track, _files_dir), false, "Frogger music track")
	else:
		_load(_disc, track, _files_dir)
		_accept_load()

## Waits for a pending read, then starts playback if a restart asked for it.
func finish_loading() -> void:
	if not _request.is_empty():
		var requested: String = _request
		_request = ""
		_accept_imported(requested, ResourceLoader.load_threaded_get(requested))
		return
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_accept_load()

## Whether a track read is still pending.
func is_loading() -> bool:
	return _task >= 0 or not _request.is_empty()

## Whether the track is audible now.
func is_playing() -> bool:
	return _player.playing

## The stream read for the selected track, or null.
func stream() -> AudioStream:
	return _stream

## Holds or resumes the track where it is.
func pause(paused: bool) -> void:
	_player.stream_paused = paused

## Stops playback, keeping the read track for the next restart.
func collapse() -> void:
	_wanted = false
	_player.stop()
	_player.stream_paused = false

## Stops playback and forgets the selection and its read track.
func clear() -> void:
	collapse()
	finish_loading()
	_player.stream = null
	_stream = null
	_disc = null
	track = -1
	_files_dir = ""

## The imported Ogg of track [param number] under [param folder], or "" when there is none.
static func imported_track_path(folder: String, number: int) -> String:
	if folder.is_empty() or number < 0 or number > 99:
		return ""
	var path: String = folder.path_join("track_%02d.ogg" % number)
	return path if ResourceLoader.exists(path) else ""

## A looping copy of an imported track, leaving the shared resource unchanged; null when [param loaded] is not Ogg Vorbis.
static func looping_copy(loaded: Resource) -> AudioStream:
	var ogg: AudioStreamOggVorbis = loaded as AudioStreamOggVorbis
	if ogg == null:
		return null
	var copy: AudioStreamOggVorbis = ogg.duplicate() as AudioStreamOggVorbis
	copy.loop = true
	return copy

## Reads track [param number] from [param disc], else a supplied file; null with [param issues] appended when neither plays.
static func load_stream(disc: DiscAudio, number: int, files_dir: String, issues: PackedStringArray) -> AudioStream:
	if number < 0:
		issues.append("The level has no music track")
		return null
	if disc != null and disc.error.is_empty():
		var pcm: PackedByteArray = disc.read_track(number)
		if not pcm.is_empty():
			return AudioResources.music_stream(pcm, true)
	if disc != null:
		issues.append(disc.error)
	var found: MusicFiles = MusicFiles.resolve(number, files_dir)
	if found.path.is_empty():
		issues.append_array(found.diagnostics)
		return null
	var loaded: AudioStream = load_file(found.path)
	if loaded == null:
		issues.append("Music file %s could not be decoded" % found.path)
	return loaded

## Decodes an Ogg Vorbis, WAV or MP3 file as a looping stream, or null.
static func load_file(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			var ogg: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file(path)
			if ogg != null:
				ogg.loop = true
			return ogg
		"mp3":
			var mp3: AudioStreamMP3 = AudioStreamMP3.load_from_file(path)
			if mp3 != null:
				mp3.loop = true
			return mp3
		"wav":
			var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
			if wav != null:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
			return wav
	return null

func _load(disc: DiscAudio, number: int, files_dir: String) -> void:
	var issues := PackedStringArray()
	_loaded = load_stream(disc, number, files_dir, issues)
	_load_issues = issues

func _accept_imported(path: String, loaded: Resource) -> void:
	_loaded = looping_copy(loaded)
	_load_issues = PackedStringArray()
	if _loaded == null:
		_load_issues.append("Imported music %s could not be loaded" % path)
	_accept_load()

func _accept_load() -> void:
	_stream = _loaded
	_loaded = null
	diagnostics.append_array(_load_issues)
	_load_issues = PackedStringArray()
	if _stream != null and _wanted:
		_play()

func _play() -> void:
	_player.stream = _stream
	if _player.is_inside_tree():
		_player.play()
