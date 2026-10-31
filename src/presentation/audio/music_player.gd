class_name MusicPlayer
extends Node
## Plays the level's music track on the [constant BUS] bus, looping, from the imported Ogg.
##
## The track number comes from the executable's music list
## ([method MusicTable.track_for_level]). The imported
## [code]track_NN.ogg[/code] under [member imported_dir] is loaded through
## Godot's threaded resource loader unless [member threaded] is false. A track
## is read once per selection and replayed from memory on each restart.
## Without the track the level is silent and [member diagnostics] says why.

## Bus the music plays on.
const BUS: StringName = &"Music"
## Where the importer writes the level music.
const IMPORTED_DIR: String = "res://assets/audio/music"

## Why the selected track is silent, newest last.
var diagnostics := PackedStringArray()
## Reads tracks on a loader thread; tests turn this off for deterministic loading.
var threaded: bool = true
## Selected CD track number, or -1.
var track: int = -1
## Folder of imported [code]track_NN.ogg[/code] files.
var imported_dir: String = IMPORTED_DIR
var _player: AudioStreamPlayer = null
var _stream: AudioStream = null
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
	if not _request.is_empty() and ResourceLoader.load_threaded_get_status(_request) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		finish_loading()

func _exit_tree() -> void:
	clear()

## Selects track [param number]; a new selection stops the old one.
func select(number: int) -> void:
	if number == track:
		return
	clear()
	track = number

## Plays the selected track from its start, reading it first when needed.
func restart() -> void:
	_player.stop()
	if track < 0:
		return
	_wanted = true
	if _stream != null:
		_play()
		return
	if not _request.is_empty():
		return
	var imported: String = imported_track_path(imported_dir, track)
	if imported.is_empty():
		diagnostics.append("No imported music for track %d under %s" % [track, imported_dir])
		return
	if threaded and ResourceLoader.load_threaded_request(imported) == OK:
		_request = imported
		return
	_accept(imported, ResourceLoader.load(imported))

## Waits for a pending read, then starts playback if a restart asked for it.
func finish_loading() -> void:
	if _request.is_empty():
		return
	var requested: String = _request
	_request = ""
	_accept(requested, ResourceLoader.load_threaded_get(requested))

## Whether a track read is still pending.
func is_loading() -> bool:
	return not _request.is_empty()

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
	track = -1

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

func _accept(path: String, loaded: Resource) -> void:
	_stream = looping_copy(loaded)
	if _stream == null:
		diagnostics.append("Imported music %s could not be loaded" % path)
	elif _wanted:
		_play()

func _play() -> void:
	_player.stream = _stream
	if _player.is_inside_tree():
		_player.play()
