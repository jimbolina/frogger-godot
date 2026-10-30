class_name FrontEndScreen
extends Control
## Single-player main menu and level list driven by [FrontEndFlow], drawn from the player's menu images.

## The front-end scene.
const SCENE: String = "res://scenes/front_end.tscn"
## The inspection tools' start screen.
const TOOLS_SCENE: String = "res://scenes/boot.tscn"
## The dedicated game scene.
const GAME_SCENE: String = "res://scenes/game/gameplay.tscn"
## Side margin of the page content.
const MARGIN: int = 24

var page: int = FrontEndPage.Page.MAIN_MENU
var assets: FrontEndAssets

var _content: Control
var _first_focus: Control


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.12, 0.05)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		_show_message("No usable Frogger files were found (%s).\nSet FROGGER_DATA_DIR or use --data-dir=<folder>." % found.error)
		return
	var data: GameData = GameData.open(found.source, found.version)
	if not data.is_valid():
		_show_message("Game tables are unreadable: %s" % data.error)
		return
	assets = FrontEndAssets.from_data(data)
	var issue: String = assets.error if not assets.error.is_empty() else FrontEndSession.load_progress(data)
	data.close()
	if not issue.is_empty():
		_show_message(issue)
		return
	page = FrontEndSession.start_page
	_show_page()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	if page == FrontEndPage.Page.LEVEL_SELECT and not FrontEndSession.level_chosen:
		_send(FrontEndFlow.Event.BACK)


## Applies [param event] to the current page and shows the result.
func _send(event: int) -> void:
	var problems := PackedStringArray()
	var next: int = FrontEndFlow.next_page(page, event, problems)
	for problem: String in problems:
		push_warning(problem)
	if next == FrontEndPage.Page.GAME:
		FrontEndSession.level_chosen = true
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	page = next
	_show_page()


func _show_page() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_first_focus = null
	match page:
		FrontEndPage.Page.LEVEL_SELECT:
			_build_level_select()
		_:
			page = FrontEndPage.Page.MAIN_MENU
			_build_main_menu()
	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func _build_main_menu() -> void:
	var column := _column()
	var logo := TextureRect.new()
	logo.texture = assets.texture("froglogo")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	column.add_child(logo)
	var start := _image_button("opt_start", _start_game)
	column.add_child(start)
	_first_focus = start
	column.add_child(_image_button("opt_exit", get_tree().quit))
	var tools := Button.new()
	tools.text = "Inspection tools"
	tools.pressed.connect(open_tools)
	column.add_child(tools)
	if not FrontEndSession.diagnostics.is_empty():
		var notes := Label.new()
		notes.text = "\n".join(FrontEndSession.diagnostics)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(notes)


func _build_level_select() -> void:
	var column := _column()
	var title := TextureRect.new()
	title.texture = assets.texture("select_level")
	title.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var progress: LevelProgress = FrontEndSession.progress
	for index: int in progress.arcade_levels.size():
		var level: int = progress.arcade_levels[index]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		list.add_child(row)
		var open: bool = progress.is_selectable(level)
		var button := TextureButton.new()
		button.texture_normal = assets.level_texture(level, FrontEndAssets.LevelImage.STACK_NAME)
		button.disabled = not open
		button.modulate = Color.WHITE if open else Color(1, 1, 1, 0.3)
		button.focus_mode = Control.FOCUS_ALL if open else Control.FOCUS_NONE
		button.pressed.connect(_select_level.bind(level))
		row.add_child(button)
		if progress.is_completed(level):
			var mark := Label.new()
			mark.text = "  done"
			row.add_child(mark)
		if open and _first_focus == null:
			_first_focus = button
	if not FrontEndSession.level_chosen:
		var back := Button.new()
		back.text = "Back"
		back.pressed.connect(_send.bind(FrontEndFlow.Event.BACK))
		column.add_child(back)


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = MARGIN
	column.offset_top = MARGIN
	column.offset_right = -MARGIN
	column.offset_bottom = -MARGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(column)
	return column


func _image_button(image_name: String, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = assets.texture(image_name)
	button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	button.pressed.connect(action)
	button.focus_entered.connect(button.set_modulate.bind(Color(1.0, 1.0, 0.6)))
	button.focus_exited.connect(button.set_modulate.bind(Color.WHITE))
	return button


func _show_message(text: String) -> void:
	var column := _column()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	var tools := Button.new()
	tools.text = "Inspection tools"
	tools.pressed.connect(open_tools)
	column.add_child(tools)


func _start_game() -> void:
	FrontEndSession.begin_game()
	FrontEndSession.level_chosen = false
	FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
	_send(FrontEndFlow.Event.START)


func _select_level(level: int) -> void:
	FrontEndSession.level = level
	GameplayScreen.selected_level = FroggerIds.level_code(level)
	_send(FrontEndFlow.Event.SELECT_LEVEL)


## Switches to the inspection tools' start screen.
func open_tools() -> void:
	get_tree().change_scene_to_file(TOOLS_SCENE)
