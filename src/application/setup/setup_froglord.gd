class_name SetupFrogLord
extends SetupPage
## The FrogLord page: whether the game follows a FrogLord save folder, and
## which one. The game watches that save while it plays; this page only
## records the choice in the launcher settings.

## Whether FrogLord is on.
var enabled: bool = false
## FrogLord's save folder, or "".
var folder: String = ""
## Whether [member folder] exists, as the view found it.
var folder_exists: bool = false


func title() -> String:
	return "FrogLord"


func blocker() -> String:
	if not enabled:
		return ""
	if folder.is_empty():
		return "Choose FrogLord's save folder, or turn FrogLord off."
	if not folder_exists:
		return "There is no folder %s." % folder
	return ""


## Takes the choice saved in [param launcher]; [param exists] says whether its folder exists.
func read(launcher: LauncherSettings, exists: bool) -> void:
	enabled = launcher.froglord_enabled
	folder = launcher.froglord_dir
	folder_exists = exists


## Chooses [param path] as the save folder; [param exists] says whether it exists.
func choose_folder(path: String, exists: bool) -> void:
	folder = path
	folder_exists = exists


## Puts the choice into [param launcher].
func write_launcher(launcher: LauncherSettings) -> void:
	launcher.froglord_enabled = enabled
	launcher.froglord_dir = folder
