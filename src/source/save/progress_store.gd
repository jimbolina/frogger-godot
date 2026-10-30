class_name ProgressStore
extends RefCounted
## The port's own save file: level progress, gold frogs, volumes, key bindings and language.
##
## Retail keeps these values in the Windows registry; the port never touches
## it and keeps them in a versioned settings file instead. The store holds
## plain data only and knows nothing about the rules that produce it.
## A missing file gives the defaults without an error. An unreadable,
## malformed or other-version file gives the defaults and sets [member error].
## Saving writes a temporary file beside the target and renames it over the
## target, so an interrupted save leaves the previous file intact.

## Default save file.
const DEFAULT_PATH: String = "user://progress.cfg"
## Version written to and expected in the file.
const FORMAT_VERSION: int = 1
## Highest volume step (the original options use 0 to 8).
const MAX_VOLUME: int = 8
## Default music volume step.
const DEFAULT_MUSIC_VOLUME: int = 3
## Default sound-effect volume step.
const DEFAULT_SOUND_VOLUME: int = 5
## Length of a saved set of controller records (four records of eleven integers).
const KEY_BINDINGS_LENGTH: int = 44
const _TEMP_SUFFIX: String = ".tmp"
const _META: String = "meta"
const _PROGRESS: String = "progress"
const _OPTIONS: String = "options"

## One flag byte per level-stack row, in stack order (empty means none saved).
var level_flags: PackedByteArray = PackedByteArray()
## Collected gold frogs, one bit per theme.
var gold_frogs: int = 0
## Music volume step, 0 to [constant MAX_VOLUME].
var music_volume: int = DEFAULT_MUSIC_VOLUME
## Sound-effect volume step, 0 to [constant MAX_VOLUME].
var sound_volume: int = DEFAULT_SOUND_VOLUME
## The four controller records in [KeyBindings]' serialised layout: empty for the shipped
## defaults, otherwise [constant KEY_BINDINGS_LENGTH] integers (per record: device, valid flag
## and nine DirectInput scancodes). The store checks the length only;
## [method KeyBindings.from_array] checks the values.
var key_bindings: PackedInt32Array = PackedInt32Array()
## Chosen [enum GameLanguage.Id], or [constant GameLanguage.AUTO] to follow the locale.
var language: int = GameLanguage.AUTO
## Why the last load fell back to defaults, or "".
var error: String = ""


## Reads [param path]; any problem yields the defaults (see the class notes).
static func load_from(path: String = DEFAULT_PATH) -> ProgressStore:
	var store := ProgressStore.new()
	if not FileAccess.file_exists(path):
		return store
	var file := ConfigFile.new()
	var status: Error = file.load(path)
	if status != OK:
		store.error = "progress file %s could not be read (%s); using defaults" % [path, error_string(status)]
		return store
	var problem: String = store._read(file)
	if not problem.is_empty():
		var defaults := ProgressStore.new()
		defaults.error = "progress file %s %s; using defaults" % [path, problem]
		return defaults
	return store


## Writes these values to [param path]; returns "" or why saving failed.
func save(path: String = DEFAULT_PATH) -> String:
	var problem: String = _validate()
	if not problem.is_empty():
		return "progress not saved: " + problem
	var directory: String = path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return "progress folder %s could not be created (%s)" % [directory, error_string(made)]
	var file := ConfigFile.new()
	file.set_value(_META, "format_version", FORMAT_VERSION)
	file.set_value(_PROGRESS, "level_flags", level_flags)
	file.set_value(_PROGRESS, "gold_frogs", gold_frogs)
	file.set_value(_OPTIONS, "music_volume", music_volume)
	file.set_value(_OPTIONS, "sound_volume", sound_volume)
	file.set_value(_OPTIONS, "key_bindings", key_bindings)
	file.set_value(_OPTIONS, "language", language)
	var temporary: String = path + _TEMP_SUFFIX
	var written: Error = file.save(temporary)
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return "progress file %s could not be written (%s)" % [temporary, error_string(written)]
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return "progress file %s could not replace %s (%s)" % [temporary, path, error_string(renamed)]
	return ""


func _read(file: ConfigFile) -> String:
	if not file.has_section_key(_META, "format_version"):
		return "has no format version"
	var version: Variant = file.get_value(_META, "format_version")
	if typeof(version) != TYPE_INT:
		return "has a non-integer format version"
	if version != FORMAT_VERSION:
		return "has format version %d, expected %d" % [version, FORMAT_VERSION]
	var flags: Variant = file.get_value(_PROGRESS, "level_flags", PackedByteArray())
	var gold: Variant = file.get_value(_PROGRESS, "gold_frogs", 0)
	var music: Variant = file.get_value(_OPTIONS, "music_volume", DEFAULT_MUSIC_VOLUME)
	var sound: Variant = file.get_value(_OPTIONS, "sound_volume", DEFAULT_SOUND_VOLUME)
	var keys: Variant = file.get_value(_OPTIONS, "key_bindings", PackedInt32Array())
	var chosen: Variant = file.get_value(_OPTIONS, "language", GameLanguage.AUTO)
	if typeof(flags) != TYPE_PACKED_BYTE_ARRAY:
		return "has malformed level_flags"
	if typeof(gold) != TYPE_INT or typeof(music) != TYPE_INT or typeof(sound) != TYPE_INT:
		return "has a non-integer gold_frogs or volume"
	if typeof(keys) != TYPE_PACKED_INT32_ARRAY:
		return "has malformed key_bindings"
	if typeof(chosen) != TYPE_INT:
		return "has a non-integer language"
	level_flags = flags
	gold_frogs = gold
	music_volume = music
	sound_volume = sound
	key_bindings = keys
	language = chosen
	var problem: String = _validate()
	return "" if problem.is_empty() else "has " + problem


func _validate() -> String:
	if gold_frogs < 0:
		return "negative gold_frogs %d" % gold_frogs
	if music_volume < 0 or music_volume > MAX_VOLUME:
		return "music_volume %d outside 0..%d" % [music_volume, MAX_VOLUME]
	if sound_volume < 0 or sound_volume > MAX_VOLUME:
		return "sound_volume %d outside 0..%d" % [sound_volume, MAX_VOLUME]
	if not key_bindings.is_empty() and key_bindings.size() != KEY_BINDINGS_LENGTH:
		return "%d key_bindings values, expected 0 or %d" % [key_bindings.size(), KEY_BINDINGS_LENGTH]
	if not GameLanguage.is_setting(language):
		return "language %d outside %d..%d" % [language, GameLanguage.AUTO, GameLanguage.COUNT - 1]
	return ""
