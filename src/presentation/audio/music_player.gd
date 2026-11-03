class_name MusicPlayer
extends Node
## Plays the level's music track on the [constant BUS] bus, looping, from the imported track.
##
## The track number comes from the executable's music list
## ([method MusicTable.track_for_level]). The imported track under
## [member imported_dir], the [constant MUSIC_FOLDER] of the catalog's base root
## ([method folder_of]), is [code]track_NN.ogg[/code] (Ogg Vorbis, the committed
## assets) or [code]track_NN.res[/code] (an [AudioStreamWAV] saved without a loop
## by an import at runtime). It is loaded through Godot's threaded resource
## loader unless [member threaded] is false. A track is read once per selection
## and replayed from memory on each restart, from a copy that loops the whole
## track. Without the track the level is silent and [member diagnostics] says why.

## Bus the music plays on.
const BUS: StringName = &"Music"
## The music folder under an assets root.
const MUSIC_FOLDER: String = "audio/music"
## Track file extensions, in the order they are tried.
const TRACK_EXTENSIONS: PackedStringArray = ["ogg", "res"]

## Why the selected track is silent, newest last.
var diagnostics := PackedStringArray()
## Reads tracks on a loader thread; tests turn this off for deterministic loading.
var threaded: bool = true
## Selected CD track number, or -1.
var track: int = -1
## Folder of imported tracks, or "" before one is chosen ([method use_folder]).
var imported_dir: String = ""
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

## Reads tracks from [param folder]; a new folder stops and forgets the selected track.
func use_folder(folder: String) -> void:
	if folder == imported_dir:
		return
	clear()
	imported_dir = folder

## The music folder under the base root of [param catalog], or "" for a catalog
## that is not [ImportedAssets].
static func folder_of(catalog: AssetCatalog) -> String:
	var imported: ImportedAssets = catalog as ImportedAssets
	if imported == null or imported.root.is_empty():
		return ""
	return imported.root.path_join(MUSIC_FOLDER)

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

## The imported track [param number] under [param folder], trying each of
## [constant TRACK_EXTENSIONS] in turn, or "" when there is none.
static func imported_track_path(folder: String, number: int) -> String:
	if folder.is_empty() or number < 0 or number > 99:
		return ""
	for extension: String in TRACK_EXTENSIONS:
		var path: String = folder.path_join("track_%02d.%s" % [number, extension])
		if ResourceLoader.exists(path):
			return path
	return ""

## A copy of an imported track that loops the whole track, leaving the shared resource
## unchanged; null when [param loaded] is neither Ogg Vorbis nor WAV.
static func looping_copy(loaded: Resource) -> AudioStream:
	var ogg: AudioStreamOggVorbis = loaded as AudioStreamOggVorbis
	if ogg != null:
		var copy: AudioStreamOggVorbis = ogg.duplicate() as AudioStreamOggVorbis
		copy.loop = true
		return copy
	var wav: AudioStreamWAV = loaded as AudioStreamWAV
	if wav == null:
		return null
	var looped: AudioStreamWAV = wav.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = wav_frames(wav)
	return looped

## The number of sample frames in [param wav].
static func wav_frames(wav: AudioStreamWAV) -> int:
	var channels: int = 2 if wav.stereo else 1
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			return wav.data.size() / channels
		AudioStreamWAV.FORMAT_16_BITS:
			return wav.data.size() / (2 * channels)
	return roundi(wav.get_length() * wav.mix_rate)

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
