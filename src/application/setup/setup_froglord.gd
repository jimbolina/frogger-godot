class_name SetupFrogLord
extends SetupPage
## The FrogLord page: whether the game follows a FrogLord save folder, and
## which one, with what [method AssetImporter.detect_froglord] found there.
## The page records the choice in the launcher settings; the game's
## [FrogLordWatcher] watches the folder while it plays.

## Whether FrogLord is on.
var enabled: bool = false
## FrogLord's save folder, or "".
var folder: String = ""
## Whether [member folder] exists, as the view found it.
var folder_exists: bool = false
## What detection found in [member folder], or null before it was looked at.
var detection: AssetImporter.Detection = null


func title() -> String:
	return "FrogLord"


func blocker() -> String:
	if not enabled:
		return ""
	if folder.is_empty():
		return "Choose FrogLord's save folder, or turn FrogLord off."
	if not folder_exists:
		return "There is no folder %s." % folder
	if detection != null and not detection.fingerprint.is_empty() and not detection.is_ok():
		return "%s Choose a save of %s, or turn FrogLord off." % [_sentence(detection.error), AssetImporter.SUPPORTED_BUILD]
	return ""


## One line for people on what [member folder] holds; "" when FrogLord is
## off or nothing was detected yet.
func found() -> String:
	if not enabled or detection == null or not folder_exists:
		return ""
	if detection.fingerprint.is_empty():
		return "No FrogLord save yet: the folder holds neither modded_FROGGER.EXE and modded_FROGPSX.MWD nor the retail files. The game starts following it once FrogLord saves there."
	if not detection.is_ok():
		return _sentence(detection.error)
	if detection.froglord:
		var version: String = " %d" % detection.froglord_version if detection.froglord_version >= 0 else ""
		return "Found a FrogLord%s save of %s: %s." % [version, detection.build, detection.files]
	return "Found the retail files (%s, %s), not a FrogLord save yet; the game plays them as an overlay until FrogLord saves modded_FROGGER.EXE and modded_FROGPSX.MWD here." % [detection.files, detection.build]


## Takes the choice saved in [param launcher]; [param exists] says whether its folder exists.
func read(launcher: LauncherSettings, exists: bool) -> void:
	enabled = launcher.froglord_enabled
	folder = launcher.froglord_dir
	folder_exists = exists
	detection = null


## Chooses [param path] as the save folder; [param exists] says whether it
## exists and [param found_there] is what detection found there (null when it was
## not looked at).
func choose_folder(path: String, exists: bool, found_there: AssetImporter.Detection = null) -> void:
	folder = path
	folder_exists = exists
	detection = found_there


## Puts the choice into [param launcher].
func write_launcher(launcher: LauncherSettings) -> void:
	launcher.froglord_enabled = enabled
	launcher.froglord_dir = folder


static func _sentence(text: String) -> String:
	if text.is_empty():
		return text
	var line: String = text.substr(0, 1).to_upper() + text.substr(1)
	return line if line.ends_with(".") else line + "."
