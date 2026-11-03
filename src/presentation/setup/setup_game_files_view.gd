class_name SetupGameFilesView
extends SetupPageView
## The game-files page: the game folder with the build found in it, and the
## optional disc image that brings the music.

var _folder: LineEdit
var _found: Label
var _disc: LineEdit
var _disc_state: Label
var _note: Label


func build() -> void:
	add_text(self, "The folder of your own copy of Frogger, version %s, holding FROGGER.EXE and FROGPSX.MWD." % AssetImporter.SUPPORTED_BUILD)
	_folder = add_path_row(self, "Game folder", _browse_folder, choose_folder)
	_found = add_text(self)
	add_child(HSeparator.new())
	add_text(self, "Music (optional) needs your Alcohol 120% disc image: the .mds file, with its .mdf beside it. Without it the game has sound effects but no music.")
	_disc = add_path_row(self, "Disc image (.mds)", _browse_disc, choose_disc)
	_disc_state = add_text(self, "", true)
	_note = add_text(self, "", true)


func refresh() -> void:
	var page: SetupGameFiles = flow.game_files
	if _folder.text != page.data_dir:
		_folder.text = page.data_dir
	if _disc.text != page.disc_path:
		_disc.text = page.disc_path
	if page.detection == null:
		_found.text = "No game folder chosen." if not page.base_usable \
			else "No game folder chosen; the game plays from %s." % flow.base_root
	elif page.detection.is_ok():
		_found.text = "Found %s." % page.detection.summary
	else:
		_found.text = page.detection.error
	if not page.disc_problem.is_empty():
		_disc_state.text = page.disc_problem
	elif page.disc_path.is_empty():
		_disc_state.text = "No disc image: no music."
	else:
		_disc_state.text = "The music is read from this disc image."
	_note.text = page.suggestion_note


## Chooses [param folder] as the game folder and detects the build in it.
func choose_folder(folder: String) -> void:
	var path: String = folder.strip_edges()
	if path == flow.game_files.data_dir and (flow.game_files.detection != null or path.is_empty()):
		return
	if path.is_empty():
		flow.game_files.clear_folder()
	else:
		flow.game_files.choose_folder(path, screen.importer.detect(path))
	refresh()
	edited.emit()


## Chooses [param path] as the disc image ("" for none).
func choose_disc(path: String) -> void:
	var disc: String = path.strip_edges()
	flow.game_files.choose_disc(disc, FileAccess.file_exists(disc), FileAccess.file_exists(SetupGameFiles.mdf_path(disc)))
	refresh()
	edited.emit()


func _browse_folder() -> void:
	SetupFileDialog.pick_folder(self, "Choose your Frogger folder", flow.game_files.data_dir, choose_folder)


func _browse_disc() -> void:
	var start: String = flow.game_files.disc_path.get_base_dir() if not flow.game_files.disc_path.is_empty() \
		else flow.game_files.data_dir
	SetupFileDialog.pick_file(self, "Choose your Frogger disc image", start,
		PackedStringArray(["*.mds ; Alcohol 120% disc image"]), choose_disc)
