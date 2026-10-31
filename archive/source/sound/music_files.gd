class_name MusicFiles
extends RefCounted
## Locates optional player-supplied level music named [code]track_NN[/code] in a [code]music[/code] folder.

const EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]
const USER_FOLDER: String = "user://music"

var path: String = ""
var diagnostics: PackedStringArray = PackedStringArray()

## Searches the data folder's [code]music[/code], its sibling [code]music[/code], then [param user_folder].
static func resolve(track: int, data_dir: String, user_folder: String = USER_FOLDER) -> MusicFiles:
	var result := MusicFiles.new()
	if track < 0 or track > 99:
		result.diagnostics.append("Music track %d is outside track_00 to track_99" % track)
		return result
	for folder: String in folders(data_dir, user_folder):
		for extension: String in EXTENSIONS:
			var candidate: String = folder.path_join("track_%02d.%s" % [track, extension])
			if not FileAccess.file_exists(candidate):
				continue
			var file: FileAccess = FileAccess.open(candidate, FileAccess.READ)
			if file == null or file.get_length() == 0:
				result.diagnostics.append("Music file %s is unreadable or empty" % candidate)
				continue
			file.close()
			result.path = candidate
			return result
	result.diagnostics.append("No music file track_%02d.ogg, .wav or .mp3 was supplied" % track)
	return result

## Returns the folders searched in order, omitting the data-relative ones when [param data_dir] is empty.
static func folders(data_dir: String, user_folder: String = USER_FOLDER) -> PackedStringArray:
	var result := PackedStringArray()
	if not data_dir.is_empty():
		var trimmed: String = data_dir.trim_suffix("/").trim_suffix("\\")
		result.append(trimmed.path_join("music"))
		if not trimmed.get_base_dir().is_empty() and trimmed.get_base_dir() != trimmed:
			result.append(trimmed.get_base_dir().path_join("music"))
	if not user_folder.is_empty():
		result.append(user_folder)
	return result
