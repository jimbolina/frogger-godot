class_name SetupFileDialog
extends RefCounted
## Opens a folder or file picker for the setup screen: the system's own dialog
## through [method DisplayServer.file_dialog_show] where the display server has
## one, otherwise a [FileDialog] that asks for the native dialog and falls back
## to Godot's. The chosen path reaches the callback on a later frame; nothing
## is called when the player cancels.


## Asks for a folder, starting in [param start_dir], and calls
## [param on_chosen] with it. [param host] holds the fallback dialog.
static func pick_folder(host: Node, title: String, start_dir: String, on_chosen: Callable) -> void:
	_pick(host, title, start_dir, PackedStringArray(), true, on_chosen)


## Asks for an existing file matching [param filters] (such as
## [code]"*.mds ; Disc image"[/code]), starting in [param start_dir], and calls
## [param on_chosen] with it.
static func pick_file(host: Node, title: String, start_dir: String, filters: PackedStringArray,
		on_chosen: Callable) -> void:
	_pick(host, title, start_dir, filters, false, on_chosen)


static func _pick(host: Node, title: String, start_dir: String, filters: PackedStringArray,
		folder: bool, on_chosen: Callable) -> void:
	var start: String = start_dir if not start_dir.is_empty() and DirAccess.dir_exists_absolute(start_dir) \
		else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode: DisplayServer.FileDialogMode = DisplayServer.FILE_DIALOG_MODE_OPEN_DIR if folder \
			else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		var answered: Callable = func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			if status and not paths.is_empty():
				on_chosen.call_deferred(paths[0])
		DisplayServer.file_dialog_show(title, start, "", false, mode, filters, answered)
		return
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if folder else FileDialog.FILE_MODE_OPEN_FILE
	dialog.use_native_dialog = true
	dialog.filters = filters
	dialog.current_dir = start
	var chosen: Callable = func(path: String) -> void:
		on_chosen.call_deferred(path)
		dialog.queue_free()
	if folder:
		dialog.dir_selected.connect(chosen)
	else:
		dialog.file_selected.connect(chosen)
	dialog.canceled.connect(dialog.queue_free)
	host.add_child(dialog)
	dialog.popup_centered_ratio(0.8)
