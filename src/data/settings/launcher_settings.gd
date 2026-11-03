class_name LauncherSettings
extends Resource
## Where the player's game files are, where the game imported them and how the
## game starts.
##
## A plain record. The setup screen fills it, [LauncherStore] keeps it in
## [code]user://launcher.cfg[/code], and [AssetLocation] reads
## [member imported_root] to find the assets the game plays from. The defaults
## describe a game that was never set up.

## The folder holding the player's [code]FROGGER.EXE[/code] and archive, or "".
@export var game_data_dir: String = ""
## The player's disc image, which supplies the music, or "" for none.
@export var disc_image_path: String = ""
## The key of the files that were imported, which also names their folder, or "".
@export var fingerprint: String = ""
## The folder the import wrote, such as [code]user://assets/<fingerprint>[/code], or "".
@export var imported_root: String = ""
## Whether the game follows a FrogLord save folder.
@export var froglord_enabled: bool = false
## The FrogLord save folder, or "".
@export var froglord_dir: String = ""
## Whether the setup screen opens on every start, not only before the first import.
@export var show_setup_on_start: bool = false
## The folder name of the texture pack the game draws, or "" for the original textures.
@export var texture_pack: String = ""


## True when an import has been recorded.
func has_import() -> bool:
	return not imported_root.is_empty()
