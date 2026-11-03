class_name SetupFrogLordView
extends SetupPageView
## The FrogLord page: turn following a FrogLord save folder on or off, choose
## the folder, see what [method AssetImporter.detect_froglord] finds there and
## what the game does with it while it plays.

## What the game does with the save while it plays.
const WHILE_PLAYING: String = "While the game runs it checks this folder every second. When FrogLord saves modded_FROGGER.EXE and modded_FROGPSX.MWD there and they stop changing, the game imports the save's name lists, tables, demos and maps over your imported files (textures, models and sounds stay those of your copy), and a level you are playing reopens from its start with the change; F5 reopens it by hand. Levels started from the menu play the save; the menus and the attract demos keep your imported files. Forms or entities the port cannot play are listed as a warning, and a missing folder only shows a message."

var _enabled: CheckButton
var _folder: LineEdit
var _found: Label
var _state: Label


func build() -> void:
	add_text(self, "FrogLord is the Frogger level editor. Point the game at the folder FrogLord saves your edited copy into.")
	_enabled = CheckButton.new()
	_enabled.text = "Follow a FrogLord save folder"
	_enabled.toggled.connect(func(on: bool) -> void:
		flow.froglord.enabled = on
		refresh()
		edited.emit())
	add_child(_enabled)
	_folder = add_path_row(self, "FrogLord save folder", _browse, choose_folder)
	_found = add_text(self)
	_state = add_text(self, "", true)


func refresh() -> void:
	var page: SetupFrogLord = flow.froglord
	if page.enabled and page.folder_exists and page.detection == null and not page.folder.is_empty():
		page.detection = screen.importer.detect_froglord(page.folder) if screen != null else null
	_enabled.set_pressed_no_signal(page.enabled)
	if _folder.text != page.folder:
		_folder.text = page.folder
	_folder.editable = page.enabled
	_found.text = page.found()
	if not page.enabled:
		_state.text = "FrogLord is off; the game plays your imported files."
	elif page.blocker().is_empty():
		_state.text = WHILE_PLAYING
	else:
		_state.text = page.blocker()


## Chooses [param folder] as FrogLord's save folder and detects what it holds.
func choose_folder(folder: String) -> void:
	var path: String = folder.strip_edges()
	var exists: bool = not path.is_empty() and DirAccess.dir_exists_absolute(path)
	var found: AssetImporter.Detection = screen.importer.detect_froglord(path) if exists and screen != null else null
	flow.froglord.choose_folder(path, exists, found)
	refresh()
	edited.emit()


func _browse() -> void:
	if not flow.froglord.enabled:
		return
	SetupFileDialog.pick_folder(self, "Choose FrogLord's save folder", flow.froglord.folder, choose_folder)
