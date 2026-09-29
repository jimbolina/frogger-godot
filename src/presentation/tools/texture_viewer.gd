class_name TextureViewer
extends Control
## A tool screen showing every texture in the game's texture banks (VLO files).
##
## Pick a bank on the left; its images appear in a grid with their position,
## texture id, name, size and flags. Keys: Up/Down choose a bank, F switches
## nearest/linear filtering, C switches the checkerboard shown behind
## transparent pixels, Page Up/Page Down scroll, Esc goes back.
##
## The game files are found the same way as at start-up (command line,
## [code]FROGGER_DATA_DIR[/code], or the remembered folder). Started with
## [code]-- --screenshot-dir=<folder>[/code] it saves a few screenshots there
## and quits (used to check the textures by eye).

## The scene to return to on Esc.
const BOOT_SCENE: String = "res://scenes/boot.tscn"
## Size of a grid cell: images are scaled to fit it (small ones up to 4x).
const CELL_SIZE: int = 136
## Banks shown by the screenshot mode, in order (those present are used).
const SCREENSHOT_BANKS: PackedStringArray = ["SUB_VRAM.VLO", "GEN_VRAM.VLO", "SKY_VRAM.VLO", "OPT_VRAM.VLO"]

## When false, [method _ready] does not look for the game files (tests set
## this to drive the viewer with their own data).
var auto_open: bool = true
## The game data being shown, or null.
var data: GameData
## The bank currently shown, or null.
var current_bank: VloFile
## Texture names by texture id (FrogLord's list), or null.
var image_names: NameBank

var _bank_entries: Array[MwiEntry] = []
var _bank_list: ItemList
var _grid: GridContainer
var _scroll: ScrollContainer
var _status: Label
var _filter_toggle: CheckButton
var _checker_toggle: CheckButton
var _checker_texture: ImageTexture
var _checker_rects: Array[TextureRect] = []


func _ready() -> void:
	_build_ui()
	if not auto_open:
		return
	var found: GameDataLocator.Located = GameDataLocator.new().locate(BootScreen.command_line_data_dir())
	if not found.is_ok():
		_status.text = "No Frogger files found (%s). See the start screen for how to set the folder." % found.error
		return
	open_data(GameData.open(found.source, found.version))
	var screenshot_dir: String = _user_arg("--screenshot-dir=")
	if not screenshot_dir.is_empty():
		_take_screenshots.call_deferred(screenshot_dir)
	elif not _bank_entries.is_empty():
		_bank_list.select(0)
		_show_bank(0)


func _exit_tree() -> void:
	if data != null:
		data.close()


## Shows the banks of [param game_data] in the list.
func open_data(game_data: GameData) -> void:
	data = game_data
	_bank_list.clear()
	_bank_entries.clear()
	if data == null or not data.is_valid():
		_status.text = "The game data cannot be read: %s" % (data.error if data != null else "none")
		return
	image_names = data.names.images
	_bank_entries = data.texture_bank_entries()
	for entry: MwiEntry in _bank_entries:
		_bank_list.add_item(entry.display_name())
	_status.text = "%d texture banks" % _bank_entries.size()
	_bank_list.grab_focus()


## Names of the banks in the list, in order.
func bank_names() -> PackedStringArray:
	var names := PackedStringArray()
	for entry: MwiEntry in _bank_entries:
		names.append(entry.display_name())
	return names


## Shows the bank called [param bank_name] (e.g. "SUB_VRAM.VLO"), opening the
## game files first if needed. Returns its image count, or -1 if it cannot be shown.
func load_vlo_by_name(bank_name: String) -> int:
	if data == null:
		var found: GameDataLocator.Located = GameDataLocator.new().locate(BootScreen.command_line_data_dir())
		if not found.is_ok():
			return -1
		open_data(GameData.open(found.source, found.version))
	var at: int = bank_names().find(bank_name.to_upper())
	if at < 0:
		for i: int in _bank_entries.size():
			if _bank_entries[i].display_name().to_upper() == bank_name.to_upper():
				at = i
	if at < 0:
		return -1
	_bank_list.select(at)
	return _show_bank(at)


## Shows [param bytes] (a texture bank called [param bank_name]) without any
## game files. Returns its image count, or -1 if it does not parse.
func load_vlo_bytes(bank_name: String, bytes: PackedByteArray) -> int:
	var vlo: VloFile = VloFile.parse(bytes)
	if not vlo.error.is_empty():
		_status.text = "%s: %s" % [bank_name, vlo.error]
		return -1
	_show_vlo(bank_name, vlo)
	return vlo.size()


## Number of image cells in the grid.
func cell_count() -> int:
	return _grid.get_child_count()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F:
			_filter_toggle.button_pressed = not _filter_toggle.button_pressed
		KEY_C:
			_checker_toggle.button_pressed = not _checker_toggle.button_pressed
		KEY_PAGEDOWN:
			_scroll.scroll_vertical += int(_scroll.size.y * 0.9)
		KEY_PAGEUP:
			_scroll.scroll_vertical -= int(_scroll.size.y * 0.9)
		KEY_ESCAPE:
			get_tree().change_scene_to_file(BOOT_SCENE)
		_:
			return
	get_viewport().set_input_as_handled()


func _show_bank(index: int) -> int:
	var entry: MwiEntry = _bank_entries[index]
	var problems := PackedStringArray()
	var started: int = Time.get_ticks_usec()
	var vlo: VloFile = data.read_texture_bank(entry.index, problems)
	if vlo == null:
		_clear_grid()
		_status.text = "%s: %s" % [entry.display_name(), ", ".join(problems)]
		return -1
	_show_vlo(entry.display_name(), vlo)
	_status.text += "  (read in %d ms)" % ((Time.get_ticks_usec() - started) / 1000)
	return vlo.size()


func _show_vlo(bank_name: String, vlo: VloFile) -> void:
	current_bank = vlo
	_clear_grid()
	for image: VloImage in vlo.images:
		_grid.add_child(_make_cell(image))
	_status.text = "%s: %d images" % [bank_name, vlo.size()]
	_scroll.scroll_vertical = 0


func _clear_grid() -> void:
	_checker_rects.clear()
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


func _make_cell(image: VloImage) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(CELL_SIZE, 0)
	var frame := Control.new()
	var zoom: float = minf(4.0, float(CELL_SIZE) / maxf(image.padded_width, image.padded_height))
	var shown := Vector2(image.padded_width, image.padded_height) * zoom
	frame.custom_minimum_size = Vector2(CELL_SIZE, shown.y)
	var checker := TextureRect.new()
	checker.texture = _checker_texture
	checker.stretch_mode = TextureRect.STRETCH_TILE
	checker.position = Vector2((CELL_SIZE - shown.x) / 2.0, 0)
	checker.size = shown
	checker.visible = _checker_toggle.button_pressed
	_checker_rects.append(checker)
	frame.add_child(checker)
	var picture := TextureRect.new()
	picture.texture = TextureBuilder.build_texture(image)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.position = checker.position
	picture.size = shown
	frame.add_child(picture)
	cell.add_child(frame)
	var caption := Label.new()
	var texture_name: String = image.custom_name
	if texture_name.is_empty() and image_names != null and image_names.has_name(image.texture_id):
		texture_name = image_names.get_name(image.texture_id)
	caption.text = "#%d  id %d\n%s\n%dx%d (%dx%d)  0x%04X" % [image.index, image.texture_id, texture_name,
		image.width, image.height, image.padded_width, image.padded_height, image.flags]
	caption.add_theme_font_size_override("font_size", 10)
	caption.clip_text = true
	caption.custom_minimum_size = Vector2(CELL_SIZE, 0)
	cell.add_child(caption)
	return cell


func _build_ui() -> void:
	_checker_texture = ImageTexture.create_from_image(_checker_image())
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(170, 0)
	split.add_child(left)
	var heading := Label.new()
	heading.text = "Texture banks"
	left.add_child(heading)
	_bank_list = ItemList.new()
	_bank_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bank_list.item_selected.connect(_show_bank)
	left.add_child(_bank_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bar.add_child(_status)
	_filter_toggle = CheckButton.new()
	_filter_toggle.text = "Linear (F)"
	_filter_toggle.focus_mode = Control.FOCUS_NONE
	_filter_toggle.toggled.connect(_on_filter_toggled)
	bar.add_child(_filter_toggle)
	_checker_toggle = CheckButton.new()
	_checker_toggle.text = "Checker (C)"
	_checker_toggle.focus_mode = Control.FOCUS_NONE
	_checker_toggle.button_pressed = true
	_checker_toggle.toggled.connect(_on_checker_toggled)
	bar.add_child(_checker_toggle)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_scroll.add_child(_grid)
	_scroll.resized.connect(_on_scroll_resized)


func _on_scroll_resized() -> void:
	_grid.columns = maxi(1, int(_scroll.size.x) / (CELL_SIZE + 4))


func _on_filter_toggled(linear: bool) -> void:
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if linear else CanvasItem.TEXTURE_FILTER_NEAREST


func _on_checker_toggled(shown: bool) -> void:
	for rect: TextureRect in _checker_rects:
		rect.visible = shown


static func _checker_image() -> Image:
	var image: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			var light: bool = (x < 8) == (y < 8)
			image.set_pixel(x, y, Color(0.75, 0.75, 0.75) if light else Color(0.45, 0.45, 0.45))
	return image


static func _user_arg(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _take_screenshots(folder: String) -> void:
	get_window().size = Vector2i(1280, 960)
	DirAccess.make_dir_recursive_absolute(folder)
	var shot: int = 0
	for bank_name: String in SCREENSHOT_BANKS:
		if load_vlo_by_name(bank_name) < 0:
			continue
		_filter_toggle.button_pressed = shot == 2
		_checker_toggle.button_pressed = shot != 3
		for _frame: int in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = folder.path_join("texture_viewer_%d_%s.png" % [shot, bank_name.get_basename().to_lower()])
		var err: Error = get_viewport().get_texture().get_image().save_png(path)
		print("screenshot %s: %s" % [path, error_string(err)])
		shot += 1
	get_tree().quit()
