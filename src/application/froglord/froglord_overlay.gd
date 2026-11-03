class_name FrogLordOverlay
extends RefCounted
## Which catalog a level opens and whether it follows FrogLord: the base root
## alone, or the base root with the index of the overlay the [FrogLordPointer]
## names.
##
## [method choose] decides from the launch and the launcher settings, without
## files:
## [br]- an attract demo plays the base root and does not follow FrogLord,
## since the recorded demos belong to the retail levels;
## [br]- a [code]--froglord[/code] launch follows the pointer, whatever base
## the overlay was imported over;
## [br]- with FrogLord on in the launcher settings, a level follows the pointer
## when it names an overlay of the chosen save folder over this base root, and
## otherwise plays the base root until the in-game watch imports one;
## [br]- otherwise the level plays the base root.

## True when the level reloads on a pointer change and on F5.
var follows: bool = false
## The overlay index folder the level opens, or "" for the base root alone.
var index_root: String = ""
## Why a following level plays the base root, for the warnings; "" otherwise.
var note: String = ""


## The choice for a level: [param froglord_flag] is a [code]--froglord[/code]
## launch, [param launcher] the launcher settings (null for none),
## [param attract] an attract demo, [param pointer] the pointer read (null for
## none) and [param base_root] the base root [AssetLocation] chose.
static func choose(froglord_flag: bool, launcher: LauncherSettings, attract: bool,
		pointer: FrogLordPointer, base_root: String) -> FrogLordOverlay:
	var choice := FrogLordOverlay.new()
	if attract:
		return choice
	var present: bool = pointer != null and pointer.exists()
	if froglord_flag:
		choice.follows = true
		if present:
			choice.index_root = pointer.index_root
		else:
			choice.note = "No FrogLord overlay pointer; playing %s until archive/import/froglord_watch.sh writes one" % base_root
		return choice
	if launcher == null or not launcher.froglord_enabled or launcher.froglord_dir.is_empty():
		return choice
	choice.follows = true
	if present and matches(pointer, launcher.froglord_dir, base_root):
		choice.index_root = pointer.index_root
	else:
		choice.note = "No FrogLord overlay of %s over %s yet; playing the imported files until the game imports one" % [
			launcher.froglord_dir, base_root]
	return choice


## True when [param pointer] names an overlay of [param save_folder] over
## [param base_root].
static func matches(pointer: FrogLordPointer, save_folder: String, base_root: String) -> bool:
	return pointer != null and pointer.exists() and pointer.data_dir == save_folder \
		and pointer.fallback_root == base_root
