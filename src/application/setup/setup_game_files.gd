class_name SetupGameFiles
extends SetupPage
## The game-files page: the folder holding the player's copy of the game, the
## build found there, and the optional disc image that supplies the music.
##
## The view picks the folder and asks the [AssetImporter] what it holds; this
## page only keeps the answer. The player may move on with an importable
## build, or without one when the game already plays from a usable assets
## root (a source checkout's committed assets or an earlier import).

## The disc image extension the importer reads (with its [code].mdf[/code] beside it).
const DISC_EXTENSION: String = "mds"

## The chosen game folder, or "".
var data_dir: String = ""
## What detection found in [member data_dir], or null before a folder is chosen.
var detection: AssetImporter.Detection = null
## The chosen disc image, or "" for none (no music).
var disc_path: String = ""
## Why [member disc_path] cannot be used, or "".
var disc_problem: String = ""
## Whether the game can already play from an assets root without an import.
var base_usable: bool = false
## A remark about the game folder suggested at the start, or "".
var suggestion_note: String = ""


func title() -> String:
	return "Game files"


func blocker() -> String:
	if detection != null and not detection.is_ok():
		return detection.error
	if detection == null and not base_usable:
		return "Choose the folder holding your Frogger files (FROGGER.EXE and FROGPSX.MWD)."
	return disc_problem


## Records [param folder] and what [param found] in it.
func choose_folder(folder: String, found: AssetImporter.Detection) -> void:
	data_dir = folder
	detection = found


## Forgets the chosen folder and its detection.
func clear_folder() -> void:
	data_dir = ""
	detection = null


## Records the disc image [param path]; [param exists] and [param data_exists]
## say whether the [code].mds[/code] file and the [code].mdf[/code] beside it
## exist. An empty path chooses no music.
func choose_disc(path: String, exists: bool, data_exists: bool) -> void:
	disc_path = path
	disc_problem = ""
	if path.is_empty():
		return
	if path.get_extension().to_lower() != DISC_EXTENSION:
		disc_problem = "%s is not an Alcohol 120%% disc image (.mds)." % path.get_file()
	elif not exists:
		disc_problem = "There is no disc image %s." % path
	elif not data_exists:
		disc_problem = "The disc image %s has no %s beside it." % [path.get_file(), mdf_path(path).get_file()]


## The [code].mdf[/code] file the disc image [param path] reads its sectors from.
static func mdf_path(path: String) -> String:
	return path.get_basename() + ".mdf"


## True when the chosen folder holds a build the importer accepts.
func has_game_files() -> bool:
	return detection != null and detection.is_ok()


## The fingerprint of the chosen files, or "".
func fingerprint() -> String:
	return detection.fingerprint if has_game_files() else ""
