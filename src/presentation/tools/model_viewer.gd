class_name ModelViewer
extends Node3D
## A tool screen showing the game's models (MOF files).
##
## Models live in WADs: one for each level, plus the GENERAL and options
## ones. Pick a WAD in the upper list and a model in the lower one. A level's
## WAD has a slot for every model of its theme; the slots the level does not
## use hold placeholders and show nothing.
##
## Keys: Tab moves between the lists, Up/Down choose; A/D and W/S turn the
## model, Q/E move closer and away (or drag and use the wheel); F switches
## nearest/linear filtering, B draws both sides of every polygon, H shows
## the parts FrogLord's settings hide, N shows the next model inside an
## animated file, L lists low-poly WADs too, Esc goes back.
##
## Models are shown unlit, in the colours their polygons store: the game
## lights them while it runs, from lights kept in each map. The parts of an
## animated model are shown where the file stores them, not posed.
##
## Started with [code]-- --screenshot-dir=<folder>[/code] it saves pictures
## of a few models there and quits (used to check the models by eye).

## The scene to return to on Esc.
const BOOT_SCENE: String = "res://scenes/boot.tscn"
## Models shown by the screenshot mode: file name, turn and tilt in degrees.
## Every third picture is taken with linear filtering.
const SCREENSHOT_MODELS: Array[Array] = [
	["SUB_STAT_DOG_KENNEL.XMR", 30.0, 20.0], ["SUB_TURTLE.XMR", 30.0, 35.0], ["SUB_STAT_DOG_KENNEL.XMR", 30.0, 20.0],
	["GEN_FROG.XAR", 30.0, 25.0], ["GEN_CHECKPOINT_1.XMR", 30.0, 25.0], ["GEN_CHECKPOINT_2.XMR", 30.0, 25.0],
	["JUN_LOG.XMR", 30.0, 25.0], ["JUN_LOG.XMR", 30.0, -35.0], ["SUB_TURTLE.XMR", 30.0, 35.0],
	["SUB_CAR_BLUE.XMR", 30.0, 25.0], ["SUB_CAR_BLUE.XMR", 210.0, 25.0], ["SUB_STAT_DOG_KENNEL.XMR", 30.0, 20.0],
	["OPT_MUSIC.XMU", 0.0, 10.0], ["JUN_SCORPION.XAR", 30.0, 35.0], ["SUB_LILLYPAD.XMR", 30.0, 50.0],
]
## The camera's field of view.
const FIELD_OF_VIEW: float = 45.0
## Width of the lists on the left, in the project's 640 by 480 screen.
const LIST_WIDTH: float = 190.0
## Width of the project's screen.
const VIEW_WIDTH: float = 640.0
## Width of the project's screen divided by its height.
const VIEW_ASPECT: float = 4.0 / 3.0

## When false, [method _ready] does not look for the game files (tests set
## this to drive the viewer with their own data).
var auto_open: bool = true
## The game data being shown, or null.
var data: GameData
## The model file being shown, or null.
var current_model: MofFile
## What was built from it, or null.
var current_mesh: ModelMesh

var _wad_entries: Array[MwiEntry] = []
var _wad_list: ItemList
var _model_list: ItemList
var _status: Label
var _facts: Label
var _filter_toggle: CheckButton
var _sides_toggle: CheckButton
var _hidden_toggle: CheckButton
var _low_poly_toggle: CheckButton
var _camera: Camera3D
var _holder: Node3D
var _banks: Dictionary[int, VloFile] = {}
var _library: TextureLibrary
var _preferred: VloFile
var _model_name: String = ""
var _static_index: int = 0
var _current_wad: int = -1
var _turn: float = 30.0
var _tilt: float = 25.0
var _distance: float = 4.0
var _dragging: bool = false


func _ready() -> void:
	_build_scene()
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
	elif not _wad_entries.is_empty():
		_wad_list.select(0)
		_show_wad(0)


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	if data != null:
		data.close()


## Lists the WADs of [param game_data] that hold models.
func open_data(game_data: GameData) -> void:
	data = game_data
	_banks.clear()
	_refresh_wads()


## Names of the WADs in the list, in order.
func wad_names() -> PackedStringArray:
	var names := PackedStringArray()
	for entry: MwiEntry in _wad_entries:
		names.append(entry.display_name())
	return names


## Shows the model at [param position] of the WAD called [param wad_name].
## Returns the number of triangles drawn (0 for a placeholder), or -1 if it
## cannot be shown.
func load_wad_model(wad_name: String, position_in_wad: int) -> int:
	if data == null or not data.is_valid():
		return -1
	var entry: MwiEntry = data.find_resource(wad_name)
	if entry == null or not entry.is_wad():
		return -1
	if _wad_entries.find(entry) < 0 and not _low_poly_toggle.button_pressed:
		_low_poly_toggle.button_pressed = true
	var at: int = _wad_entries.find(entry)
	if at < 0:
		return -1
	_wad_list.select(at)
	_show_wad(at)
	if position_in_wad < 0 or position_in_wad >= _model_list.item_count:
		return -1
	_model_list.select(position_in_wad)
	return _show_model(position_in_wad)


## Shows the model file called [param file_name] (e.g. "GEN_FROG.XAR") from
## the first WAD that holds it. Returns the number of triangles drawn, or -1.
func load_model_by_name(file_name: String) -> int:
	if data == null or not data.is_valid():
		return -1
	var entry: MwiEntry = data.find_resource(file_name)
	if entry == null or not GameData.is_model_entry(entry):
		return -1
	var wad_id: int = data.wad_holding(entry.index)
	var wad: WadFile = data.read_wad(wad_id)
	if wad == null:
		return -1
	for i: int in wad.children.size():
		if wad.children[i].resource_id == entry.index:
			return load_wad_model(data.mwi.get_entry(wad_id).display_name(), i)
	return -1


## Shows [param bytes] (a model file called [param model_name]) without any
## game files, textured from [param bank] if given. An incomplete model
## takes its shape from [param counterpart]. Returns the number of triangles
## drawn, or -1 if the bytes do not parse.
func load_model_bytes(model_name: String, bytes: PackedByteArray, bank: VloFile = null, counterpart: MofFile = null) -> int:
	var model: MofFile = MofFile.parse(bytes, counterpart)
	if not model.is_valid():
		_clear_model()
		_status.text = "%s: %s" % [model_name, model.error]
		return -1
	_library = TextureLibrary.new()
	_preferred = bank
	if bank != null:
		_library.add_bank(bank, "bank")
	_model_name = model_name
	_static_index = 0
	return _show(model)


## Number of part meshes on screen.
func part_node_count() -> int:
	return _holder.get_child_count()


## Number of those that are visible.
func visible_part_count() -> int:
	var shown: int = 0
	for child: Node in _holder.get_children():
		if (child as MeshInstance3D).visible:
			shown += 1
	return shown


## The text under the lists: what the model holds.
func facts_text() -> String:
	return _facts.text


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 0.9)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_turn_by(-motion.relative.x * 0.5, motion.relative.y * 0.5)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_A:
			_turn_by(-5.0, 0.0)
		KEY_D:
			_turn_by(5.0, 0.0)
		KEY_W:
			_turn_by(0.0, 5.0)
		KEY_S:
			_turn_by(0.0, -5.0)
		KEY_Q:
			_zoom(0.9)
		KEY_E:
			_zoom(1.0 / 0.9)
		_:
			if key.echo or not _toggle_key(key.keycode):
				return
	get_viewport().set_input_as_handled()


func _toggle_key(keycode: Key) -> bool:
	match keycode:
		KEY_F:
			_filter_toggle.button_pressed = not _filter_toggle.button_pressed
		KEY_B:
			_sides_toggle.button_pressed = not _sides_toggle.button_pressed
		KEY_H:
			_hidden_toggle.button_pressed = not _hidden_toggle.button_pressed
		KEY_L:
			_low_poly_toggle.button_pressed = not _low_poly_toggle.button_pressed
		KEY_N:
			if current_model != null and current_model.static_models.size() > 1:
				_static_index = (_static_index + 1) % current_model.static_models.size()
				_show(current_model)
		KEY_ESCAPE:
			get_tree().change_scene_to_file(BOOT_SCENE)
		_:
			return false
	return true


func _turn_by(turn: float, tilt: float) -> void:
	_turn = fposmod(_turn + turn, 360.0)
	_tilt = clampf(_tilt + tilt, -89.0, 89.0)
	_place_camera()


func _zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, 0.05, 500.0)
	_place_camera()


func _place_camera() -> void:
	var centre: Vector3 = current_mesh.bounds.get_center() if current_mesh != null else Vector3.ZERO
	var direction: Vector3 = Vector3.BACK.rotated(Vector3.RIGHT, deg_to_rad(-_tilt)).rotated(Vector3.UP, deg_to_rad(_turn))
	_camera.position = centre + direction * _distance
	_camera.look_at(centre, Vector3.UP)
	# Shift the picture to the middle of the space right of the lists.
	var half_width: float = _distance * tan(deg_to_rad(FIELD_OF_VIEW * 0.5)) * VIEW_ASPECT
	_camera.h_offset = -half_width * LIST_WIDTH / VIEW_WIDTH


func _refresh_wads() -> void:
	_wad_list.clear()
	_model_list.clear()
	_wad_entries.clear()
	_clear_model()
	if data == null or not data.is_valid():
		_status.text = "The game data cannot be read: %s" % (data.error if data != null else "none")
		return
	for entry: MwiEntry in data.mwi.wad_entries():
		var low_poly: bool = entry.display_name().contains("_WIN95") or entry.display_name() == "OPTIONSL.WAD" \
			or _is_low_poly_general(entry.index)
		if low_poly and not _low_poly_toggle.button_pressed:
			continue
		_wad_entries.append(entry)
		_wad_list.add_item(entry.display_name())
	_status.text = "%d WADs" % _wad_entries.size()
	_wad_list.grab_focus()


func _is_low_poly_general(wad_id: int) -> bool:
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	return general != null and (general.wad_id(false, true) == wad_id or general.wad_id(true, true) == wad_id)


func _show_wad(index: int) -> void:
	var entry: MwiEntry = _wad_entries[index]
	_model_list.clear()
	_clear_model()
	_current_wad = entry.index
	var wad: WadFile = data.read_wad(entry.index)
	if wad == null:
		_status.text = "%s cannot be read" % entry.display_name()
		return
	var used: int = 0
	for i: int in wad.children.size():
		var child_entry: MwiEntry = data.mwi.get_entry(wad.children[i].resource_id)
		var placeholder: bool = MofFile.kind_of(wad.child_contents(wad.children[i])) == MofFile.Kind.DUMMY
		if not placeholder:
			used += 1
		_model_list.add_item("%d  %s" % [i, "(placeholder)" if placeholder else child_entry.display_name()])
	_status.text = "%s: %d slots, %d models" % [entry.display_name(), wad.children.size(), used]
	_use_banks_of(entry.index)


func _bank(resource_id: int) -> VloFile:
	if resource_id <= 0:
		return null
	if not _banks.has(resource_id):
		_banks[resource_id] = data.read_texture_bank(resource_id)
	return _banks[resource_id]


# The textures a WAD's models can use: the GENERAL bank, then the WAD's own.
func _use_banks_of(wad_id: int) -> void:
	_library = TextureLibrary.new()
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	var general_bank: VloFile = _bank(general.vlo_id()) if general != null else null
	if general_bank != null:
		_library.add_bank(general_bank, "general")
	_preferred = _bank(data.texture_bank_for_wad(wad_id))
	if _preferred != null:
		_library.add_bank(_preferred, "own")


func _show_model(position_in_wad: int) -> int:
	var resource_id: int = data.model_resource_at(_current_wad, position_in_wad)
	var problems := PackedStringArray()
	var model: MofFile = data.read_model(resource_id, problems) if resource_id >= 0 else null
	if model == null:
		_clear_model()
		_status.text = "slot %d: %s" % [position_in_wad, ", ".join(problems)]
		return -1
	_model_name = data.mwi.get_entry(resource_id).display_name()
	_static_index = 0
	return _show(model)


func _show(model: MofFile) -> int:
	_clear_model()
	current_model = model
	if model.static_models.is_empty():
		_status.text = "%s: a placeholder" % _model_name
		_facts.text = "placeholder"
		return 0
	var builder := ModelMeshBuilder.new(_library, _preferred)
	builder.linear_filter = _filter_toggle.button_pressed
	builder.two_sided = _sides_toggle.button_pressed
	var shape: MofStatic = model.static_models[_static_index]
	current_mesh = builder.build(shape)
	var hidden: PackedInt64Array = _hidden_parts()
	for i: int in current_mesh.part_meshes.size():
		var node := MeshInstance3D.new()
		node.name = "Part%d" % i
		node.mesh = current_mesh.part_meshes[i]
		node.visible = _hidden_toggle.button_pressed or not hidden.has(i)
		_holder.add_child(node)
	var size: float = maxf(current_mesh.bounds.size.length(), 0.05)
	_distance = size * 0.5 / tan(deg_to_rad(FIELD_OF_VIEW * 0.5)) * 1.3
	_place_camera()
	_status.text = "%s: %s" % [_model_name, model.kind_name()]
	if model.static_models.size() > 1:
		_status.text += ", model %d of %d inside (N)" % [_static_index + 1, model.static_models.size()]
	if model.is_incomplete:
		_status.text += ", shape taken from another model"
	_facts.text = _describe(shape)
	return current_mesh.triangle_count


func _describe(shape: MofStatic) -> String:
	var vertices: int = 0
	var poses: int = 0
	var by_type := PackedInt32Array()
	by_type.resize(MofPolygonType.COUNT)
	for part: MofPart in shape.parts:
		vertices += part.vertex_count
		poses += part.partcel_count
		var counts: PackedInt32Array = part.polygons_by_type()
		for kind: int in MofPolygonType.COUNT:
			by_type[kind] += counts[kind]
	var kinds := PackedStringArray()
	for kind: int in MofPolygonType.COUNT:
		if by_type[kind] > 0:
			kinds.append("%s %d" % [MofPolygonType.type_name(kind), by_type[kind]])
	var lines := PackedStringArray([
		"%d parts, %d poses, %d vertices" % [shape.parts.size(), poses, vertices],
		"%d polygons: %s" % [shape.polygon_count(), ", ".join(kinds)],
		"%d triangles in %d surfaces" % [current_mesh.triangle_count, current_mesh.surface_count],
		"%d textures, %d flipbook animations, %d animated polygons" % [shape.image_ids().size(),
			shape.flipbook_action_count(), shape.texture_animation_target_count()]])
	if not current_mesh.missing_image_ids.is_empty():
		lines.append("textures not found: %s" % str(current_mesh.missing_image_ids))
	var hidden: PackedInt64Array = _hidden_parts()
	if not hidden.is_empty():
		lines.append("parts hidden by FrogLord's settings: %s" % str(hidden))
	return "\n".join(lines)


func _hidden_parts() -> PackedInt64Array:
	if data == null or data.version == null or not data.version.hidden_parts.has(_model_name):
		return PackedInt64Array()
	return data.version.hidden_parts[_model_name]


func _clear_model() -> void:
	current_model = null
	current_mesh = null
	_facts.text = ""
	for child: Node in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	if current_model != null:
		var turn: float = _turn
		var tilt: float = _tilt
		var distance: float = _distance
		_show(current_model)
		_turn = turn
		_tilt = tilt
		_distance = distance
		_place_camera()


func _on_option_toggled(_pressed: bool) -> void:
	_rebuild()


func _on_low_poly_toggled(_pressed: bool) -> void:
	if data != null:
		_refresh_wads()


func _build_scene() -> void:
	_camera = Camera3D.new()
	_camera.fov = FIELD_OF_VIEW
	_camera.near = 0.01
	_camera.far = 1000.0
	add_child(_camera)
	_holder = Node3D.new()
	_holder.name = "Model"
	add_child(_holder)
	var layer := CanvasLayer.new()
	add_child(layer)
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.offset_right = LIST_WIDTH
	layer.add_child(left)
	_wad_list = ItemList.new()
	_wad_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wad_list.item_selected.connect(_show_wad)
	left.add_child(_wad_list)
	_model_list = ItemList.new()
	_model_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_list.size_flags_stretch_ratio = 1.6
	_model_list.item_selected.connect(_show_model)
	left.add_child(_model_list)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.offset_left = LIST_WIDTH + 6
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(right)
	_status = Label.new()
	_status.clip_text = true
	right.add_child(_status)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_filter_toggle = _add_toggle(bar, "Linear (F)", _on_option_toggled)
	_sides_toggle = _add_toggle(bar, "Both sides (B)", _on_option_toggled)
	_hidden_toggle = _add_toggle(bar, "Hidden parts (H)", _on_option_toggled)
	_low_poly_toggle = _add_toggle(bar, "Low-poly (L)", _on_low_poly_toggled)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(gap)
	_facts = Label.new()
	_facts.add_theme_font_size_override("font_size", 11)
	right.add_child(_facts)
	RenderingServer.set_default_clear_color(Color(0.22, 0.24, 0.30))
	_place_camera()


func _add_toggle(bar: HBoxContainer, text: String, handler: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.toggled.connect(handler)
	bar.add_child(toggle)
	return toggle


static func _user_arg(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _take_screenshots(folder: String) -> void:
	get_window().size = Vector2i(1280, 960)
	DirAccess.make_dir_recursive_absolute(folder)
	var shot: int = 0
	for entry: Array in SCREENSHOT_MODELS:
		var file_name: String = entry[0]
		var turn: float = entry[1]
		var tilt: float = entry[2]
		_filter_toggle.button_pressed = shot % 3 == 2
		var triangles: int = load_model_by_name(file_name)
		if triangles < 0:
			print("screenshot: %s cannot be shown: %s" % [file_name, _status.text])
			continue
		_turn = turn
		_tilt = tilt
		_place_camera()
		for _frame: int in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = folder.path_join("model_viewer_%02d_%s.png" % [shot, file_name.get_basename().to_lower()])
		var err: Error = get_viewport().get_texture().get_image().save_png(path)
		print("screenshot %s: %s, %d triangles; %s" % [path, error_string(err), triangles, _facts.text.replace("\n", "; ")])
		shot += 1
	get_tree().quit()
