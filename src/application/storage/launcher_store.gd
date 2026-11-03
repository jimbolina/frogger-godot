class_name LauncherStore
extends RefCounted
## The launcher's settings file: the player's game files, the import made from
## them, FrogLord and whether the setup screen opens on start.
##
## A missing file gives the defaults without an error, and a missing key takes
## its default. A file of an earlier version from [constant OLDEST_FORMAT_VERSION]
## on is read the same way, so the keys it lacks take their defaults, and the
## next save writes [constant FORMAT_VERSION]. Version 2's
## [code]textures/texture_set[/code] ([code]retail[/code] or the removed
## [code]x4[/code]) names no texture pack, so it is dropped and the game draws
## the original textures. An unreadable, malformed or
## unknown-version file, or any value of the wrong type, gives all the defaults
## and sets [member error]. Saving writes a temporary file beside the target and
## renames it over the target, so an interrupted save leaves the previous file
## intact.

## Default settings file.
const DEFAULT_PATH: String = "user://launcher.cfg"
## Version written to and expected in the file.
const FORMAT_VERSION: int = 3
## The earliest version still read: version 1 had no [code]textures[/code] section.
const OLDEST_FORMAT_VERSION: int = 1
## The settings file of the archive's [code]GameDataLocator[/code], whose
## remembered game folder [method legacy_game_folder] reads.
const LEGACY_SETTINGS_PATH: String = "user://settings.cfg"
## [LauncherSettings] fields by file section.
const LAYOUT: Dictionary[String, Array] = {
	"game_data": ["game_data_dir", "disc_image_path"],
	"import": ["fingerprint", "imported_root"],
	"froglord": ["froglord_enabled", "froglord_dir"],
	"start": ["show_setup_on_start"],
	"textures": ["texture_pack"],
}
const _TEMP_SUFFIX: String = ".tmp"
const _META: String = "meta"
const _LEGACY_SECTION: String = "game_data"
const _LEGACY_KEY: String = "directory"

## The loaded settings, or the defaults.
var settings: LauncherSettings = LauncherSettings.new()
## Why the last load fell back to defaults, or "".
var error: String = ""
## Whether the file existed when it was read.
var found: bool = false
## The format version of the file read, or 0 when none was read.
var read_version: int = 0


## Reads [param path]; any problem yields the defaults (see the class notes).
static func load_from(path: String = DEFAULT_PATH) -> LauncherStore:
	var store := LauncherStore.new()
	if not FileAccess.file_exists(path):
		return store
	var file := ConfigFile.new()
	var status: Error = file.load(path)
	if status != OK:
		store.error = "launcher file %s could not be read (%s); using defaults" % [path, error_string(status)]
		return store
	var problem: String = store._read(file)
	if not problem.is_empty():
		var defaults := LauncherStore.new()
		defaults.error = "launcher file %s %s; using defaults" % [path, problem]
		return defaults
	store.found = true
	return store


## Writes [param values] to [param path]; returns "" or why saving failed.
static func save(values: LauncherSettings, path: String = DEFAULT_PATH) -> String:
	var directory: String = path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return "launcher folder %s could not be created (%s)" % [directory, error_string(made)]
	var file := ConfigFile.new()
	file.set_value(_META, "format_version", FORMAT_VERSION)
	for section: String in LAYOUT:
		for field: String in LAYOUT[section]:
			file.set_value(section, field, values.get(field))
	var temporary: String = path + _TEMP_SUFFIX
	var written: Error = file.save(temporary)
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return "launcher file %s could not be written (%s)" % [temporary, error_string(written)]
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return "launcher file %s could not replace %s (%s)" % [temporary, path, error_string(renamed)]
	return ""


## The game folder the archive's locator remembered in [param path]
## ([constant LEGACY_SETTINGS_PATH]), or "" when there is none. The setup
## screen offers it once when the launcher records no game folder.
static func legacy_game_folder(path: String = LEGACY_SETTINGS_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return ""
	var value: Variant = file.get_value(_LEGACY_SECTION, _LEGACY_KEY, "")
	return value if value is String else ""


func _read(file: ConfigFile) -> String:
	if not file.has_section_key(_META, "format_version"):
		return "has no format version"
	var version: Variant = file.get_value(_META, "format_version")
	if typeof(version) != TYPE_INT:
		return "has a non-integer format version"
	if version < OLDEST_FORMAT_VERSION or version > FORMAT_VERSION:
		return "has format version %d, expected %d" % [version, FORMAT_VERSION]
	read_version = version
	for section: String in LAYOUT:
		for field: String in LAYOUT[section]:
			if not file.has_section_key(section, field):
				continue
			var value: Variant = file.get_value(section, field)
			var expected: int = typeof(settings.get(field))
			if typeof(value) != expected:
				return "has %s/%s of type %s, expected %s" % [
					section, field, type_string(typeof(value)), type_string(expected)]
			settings.set(field, value)
	return ""
