class_name BootScreen
extends Control
## The tools launcher: plays a chosen level and opens the texture, model and map
## inspection tools and the sandbox, all reading the imported assets.
##
## [code]--sandbox[/code] or [code]--level=SANDBOX[/code] opens the sandbox directly.

## The texture viewer's scene.
const TEXTURE_VIEWER_SCENE: String = "res://scenes/tools/texture_viewer.tscn"
## The model viewer's scene.
const MODEL_VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"
## The map inspection tool.
const MAP_VIEWER_SCENE: String = "res://scenes/tools/map_viewer.tscn"
## The sandbox play-check scene.
const SANDBOX_SCENE: String = "res://scenes/game/sandbox.tscn"

## Whether the command-line sandbox request was already honoured, so returning to this menu stays here.
static var sandbox_requested: bool = false

var _label: Label
var _level_picker: OptionButton


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16
	layout.offset_top = 16
	layout.offset_right = -16
	layout.offset_bottom = -16
	add_child(layout)
	var menu := HBoxContainer.new()
	layout.add_child(menu)
	var data: ImportedAssets = ImportedAssets.open("res://assets", ViewerArguments.texture_set(OS.get_cmdline_user_args()), ViewerArguments.rendering_profile(OS.get_cmdline_user_args()))
	data.note_renderer(RenderingServer.get_current_rendering_method())
	for warning: String in data.warnings:
		push_warning(warning)
	var codes: PackedStringArray = data.playable_level_codes() if data.is_valid() else PackedStringArray()
	_level_picker = OptionButton.new()
	for code: String in codes:
		_level_picker.add_item(code)
	var requested_level: String = ViewerArguments.value(OS.get_cmdline_user_args(), "--level=").to_upper()
	var requested_index: int = codes.find(requested_level)
	if requested_index >= 0:
		_level_picker.select(requested_index)
	menu.add_child(_level_picker)
	var play_button := Button.new()
	play_button.text = "Play"
	play_button.pressed.connect(open_game)
	menu.add_child(play_button)
	var sandbox_button := Button.new()
	sandbox_button.text = "Sandbox"
	sandbox_button.pressed.connect(open_sandbox)
	menu.add_child(sandbox_button)
	var viewer_button := Button.new()
	viewer_button.text = "Texture viewer"
	viewer_button.pressed.connect(open_texture_viewer)
	menu.add_child(viewer_button)
	var model_button := Button.new()
	model_button.text = "Model viewer"
	model_button.pressed.connect(open_model_viewer)
	menu.add_child(model_button)
	var map_button := Button.new()
	map_button.text = "Map viewer"
	map_button.pressed.connect(open_map_viewer)
	menu.add_child(map_button)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_label)
	_label.text = status(data)
	viewer_button.grab_focus()
	if wants_sandbox(OS.get_cmdline_user_args()) and not sandbox_requested:
		sandbox_requested = true
		open_sandbox.call_deferred()


## Opens a fresh game in the selected supported level.
func open_game() -> void:
	if _level_picker.selected < 0:
		return
	FrontEndSession.selected_level = _level_picker.get_item_text(_level_picker.selected)
	get_tree().change_scene_to_file("res://scenes/game/gameplay.tscn")


## Opens the sandbox arena.
func open_sandbox() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE)


## Whether the command line asks for the sandbox with [code]--sandbox[/code] or [code]--level=SANDBOX[/code].
static func wants_sandbox(arguments: PackedStringArray) -> bool:
	return ViewerArguments.has_flag(arguments, "--sandbox") or ViewerArguments.value(arguments, "--level=").to_upper() == SandboxScreen.LEVEL_CODE


## Switches to the texture viewer.
func open_texture_viewer() -> void:
	get_tree().change_scene_to_file(TEXTURE_VIEWER_SCENE)


## Switches to the model viewer.
func open_model_viewer() -> void:
	get_tree().change_scene_to_file(MODEL_VIEWER_SCENE)


## A line naming the build of the imported assets in [param data], or why they cannot be used.
static func status(data: AssetCatalog) -> String:
	if data == null or not data.is_valid():
		return "Frogger: the imported assets cannot be opened (%s)." % (data.error if data != null else "none")
	return "Frogger: imported assets of %s." % data.version_name


## Switches to the map inspection tool.
func open_map_viewer() -> void:
	get_tree().change_scene_to_file(MAP_VIEWER_SCENE)
