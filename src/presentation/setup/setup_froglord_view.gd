class_name SetupFrogLordView
extends SetupPageView
## The FrogLord page: turn following a FrogLord save folder on or off, and choose the folder.

var _enabled: CheckButton
var _folder: LineEdit
var _state: Label


func build() -> void:
	add_text(self, "FrogLord is the Frogger level editor. While you play, the game watches FrogLord's save in the folder below and reopens the level when you save a change.")
	_enabled = CheckButton.new()
	_enabled.text = "Follow a FrogLord save folder"
	_enabled.toggled.connect(func(on: bool) -> void:
		flow.froglord.enabled = on
		refresh()
		edited.emit())
	add_child(_enabled)
	_folder = add_path_row(self, "FrogLord save folder", _browse, choose_folder)
	_state = add_text(self, "", true)


func refresh() -> void:
	var page: SetupFrogLord = flow.froglord
	_enabled.set_pressed_no_signal(page.enabled)
	if _folder.text != page.folder:
		_folder.text = page.folder
	_folder.editable = page.enabled
	if not page.enabled:
		_state.text = "FrogLord is off; the game plays the imported files."
	elif page.blocker().is_empty():
		_state.text = "The game follows %s." % page.folder
	else:
		_state.text = page.blocker()


## Chooses [param folder] as FrogLord's save folder.
func choose_folder(folder: String) -> void:
	var path: String = folder.strip_edges()
	flow.froglord.choose_folder(path, not path.is_empty() and DirAccess.dir_exists_absolute(path))
	refresh()
	edited.emit()


func _browse() -> void:
	if not flow.froglord.enabled:
		return
	SetupFileDialog.pick_folder(self, "Choose FrogLord's save folder", flow.froglord.folder, choose_folder)
