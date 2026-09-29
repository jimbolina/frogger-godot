class_name GameDataLocator
extends RefCounted
## Finds the player's Frogger files and identifies which build they are.
##
## Folders are tried in this order, and the first one holding a complete set
## of files wins:
## [br]1. a folder given explicitly (for example on the command line),
## [br]2. the [code]FROGGER_DATA_DIR[/code] environment variable,
## [br]3. the folder saved in the game's settings ([method remember_directory]).
##
## In a folder, FrogLord's modded files are preferred over retail ones when
## both are present, since FrogLord saves next to the originals.

## Environment variable naming the data folder.
const ENV_VAR: String = "FROGGER_DATA_DIR"
## Default settings file holding the remembered folder.
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const _SETTINGS_SECTION: String = "game_data"
const _SETTINGS_KEY: String = "directory"

## Where the remembered folder is stored.
var settings_path: String = DEFAULT_SETTINGS_PATH
## Whether [constant ENV_VAR] is consulted (tests switch it off).
var use_environment: bool = true

var _library: FrogLordConfigLibrary


## The result of a search.
class Located:
	extends RefCounted
	## The files found, or null.
	var source: GameDataSource
	## Their build, or null.
	var version: GameVersionConfig
	## How the folder was found: "argument", "FROGGER_DATA_DIR" or "saved setting".
	var origin: String = ""
	## How the build was recognised, see [GameVersionDetector].
	var detection_method: String = ""
	## CRC-32 of the executable.
	var exe_crc32: int = 0
	## One line per folder tried, with why it was or was not used.
	var attempts: PackedStringArray = PackedStringArray()
	## Why nothing usable was found, or "".
	var error: String = ""

	## True when files were found and their build identified.
	func is_ok() -> bool:
		return source != null and version != null and error.is_empty()


## A locator identifying builds with [param library] (the shipped FrogLord files by default).
func _init(library: FrogLordConfigLibrary = null) -> void:
	_library = library if library != null else FrogLordConfigLibrary.new()


## Searches the folders in order; [param explicit_dir] may be "".
func locate(explicit_dir: String = "") -> Located:
	var found := Located.new()
	var candidates: Array[PackedStringArray] = [
		PackedStringArray(["argument", explicit_dir]),
		PackedStringArray([ENV_VAR, OS.get_environment(ENV_VAR) if use_environment else ""]),
		PackedStringArray(["saved setting", saved_directory()]),
	]
	for candidate: PackedStringArray in candidates:
		var origin: String = candidate[0]
		var dir: String = candidate[1]
		if dir.is_empty():
			found.attempts.append("%s: not set" % origin)
			continue
		var source: GameDataSource = open_directory(dir)
		if source == null:
			found.attempts.append("%s: %s has neither %s + %s nor %s + %s" % [origin, dir,
				RetailDirSource.EXE_NAME, RetailDirSource.MWD_NAME,
				FrogLordModSource.EXE_NAME, FrogLordModSource.MWD_NAME])
			continue
		var detection: GameVersionDetector.Result = GameVersionDetector.new(_library).detect(source.get_exe_bytes())
		found.exe_crc32 = detection.exe_crc32
		if not detection.is_ok():
			found.attempts.append("%s: %s: %s" % [origin, source.describe(), detection.error])
			if found.error.is_empty():
				found.error = detection.error
			continue
		found.source = source
		found.version = detection.version
		found.origin = origin
		found.detection_method = detection.method
		found.error = ""
		found.attempts.append("%s: %s, %s" % [origin, source.describe(), detection.version.internal_name])
		return found
	if found.error.is_empty():
		found.error = "no Frogger files found"
	return found


## The data source for the files in [param dir] (FrogLord's modded files
## preferred), or null if the folder has no complete set.
static func open_directory(dir: String) -> GameDataSource:
	if FrogLordModSource.looks_like(dir):
		return FrogLordModSource.new(dir)
	if RetailDirSource.looks_like(dir):
		return RetailDirSource.new(dir)
	return null


## The folder saved by [method remember_directory], or "".
func saved_directory() -> String:
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return ""
	var value: Variant = settings.get_value(_SETTINGS_SECTION, _SETTINGS_KEY, "")
	return value if value is String else ""


## Saves [param dir] as the folder to use when nothing else is given.
func remember_directory(dir: String) -> Error:
	var settings := ConfigFile.new()
	settings.load(settings_path) # A missing file just starts empty.
	settings.set_value(_SETTINGS_SECTION, _SETTINGS_KEY, dir)
	return settings.save(settings_path)
