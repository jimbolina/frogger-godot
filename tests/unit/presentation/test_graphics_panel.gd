extends GutTest
## The GraphicsDebug autoload is inert headless; an activated panel toggles on the 0 key, edits the profile and saves.

const ROOT: String = "user://test_graphics_panel"
const AUTOLOAD: String = "autoload/GraphicsDebug"

## A panel whose game bindings are supplied directly.
class BoundPanel:
	extends GraphicsPanel
	var input: BindingInput = null

	func game_input() -> BindingInput:
		return input


var _path: String = ROOT.path_join("graphics.cfg")
var _store: ProgressStore = null
var _max_fps: int = 0


func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	_store = FrontEndSession.store
	FrontEndSession.store = ProgressStore.new()
	_max_fps = Engine.max_fps


func after_each() -> void:
	FrontEndSession.store = _store
	Engine.max_fps = _max_fps
	GraphicsProfile.reset()


func after_all() -> void:
	_remove_tree(ROOT)


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _panel() -> GraphicsPanel:
	var target := SubViewport.new()
	add_child_autofree(target)
	var panel := GraphicsPanel.new()
	add_child_autofree(panel)
	panel.activate(_path, target)
	return panel


func _toggle_key(pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = GraphicsPanel.TOGGLE_KEY
	event.pressed = pressed
	event.echo = echo
	return event


func _controls(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control:
			into.append(child as Control)
		_controls(child, into)


func test_autoload_is_registered() -> void:
	assert_true(ProjectSettings.has_setting(AUTOLOAD))
	assert_eq(str(ProjectSettings.get_setting(AUTOLOAD)), "*res://src/presentation/debug/graphics_panel.gd")


func test_autoload_is_inert_headless() -> void:
	assert_eq(DisplayServer.get_name(), "headless")
	var autoload: Node = get_tree().root.get_node_or_null("GraphicsDebug")
	assert_not_null(autoload)
	var panel: GraphicsPanel = autoload as GraphicsPanel
	assert_not_null(panel)
	assert_eq(panel.get_child_count(), 0)
	assert_null(panel.view)
	assert_eq(panel.layer, GraphicsPanel.LAYER)
	assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(FileAccess.file_exists(GraphicsStore.DEFAULT_PATH))


func test_new_instance_is_inert_headless() -> void:
	var panel := GraphicsPanel.new()
	add_child_autofree(panel)
	assert_eq(panel.get_child_count(), 0)
	assert_eq(Engine.max_fps, _max_fps)
	panel._unhandled_key_input(_toggle_key())
	assert_false(panel.is_open())
	assert_false(FileAccess.file_exists(GraphicsStore.DEFAULT_PATH))


func test_activate_loads_the_file_into_the_profile() -> void:
	var values := GraphicsSettings.new()
	values.bloom = false
	values.exposure = 1.5
	values.max_fps = _max_fps
	assert_eq(GraphicsStore.save(values, _path), "")
	var panel: GraphicsPanel = _panel()
	assert_false(GraphicsProfile.current().bloom)
	assert_almost_eq(GraphicsProfile.current().exposure, 1.5, 0.0001)
	assert_false(panel.view.settings.bloom)
	assert_false(panel.is_open())
	assert_eq(panel.last_error, "")


func test_a_missing_file_applies_nothing_and_writes_nothing() -> void:
	var panel: GraphicsPanel = _panel()
	assert_not_null(panel.view)
	assert_eq(Engine.max_fps, _max_fps)
	assert_false(FileAccess.file_exists(_path))


func test_every_view_control_refuses_focus() -> void:
	var panel: GraphicsPanel = _panel()
	var controls: Array[Control] = [panel.view]
	_controls(panel.view, controls)
	assert_gt(controls.size(), 50)
	for control: Control in controls:
		assert_eq(control.focus_mode, Control.FOCUS_NONE, str(control.get_path()))


func test_unchecked_boxes_draw_an_outlined_icon() -> void:
	var panel: GraphicsPanel = _panel()
	var bloom: CheckBox = panel.view.find_child("bloom", true, false) as CheckBox
	var icon: Texture2D = bloom.get_theme_icon("unchecked")
	assert_eq(icon.get_size(), Vector2(GraphicsPanelView.BOX_SIZE, GraphicsPanelView.BOX_SIZE))
	var image: Image = icon.get_image()
	assert_almost_eq(image.get_pixel(0, 0).r, GraphicsPanelView.BOX_OUTLINE.r, 0.01)
	assert_lt(image.get_pixel(GraphicsPanelView.BOX_SIZE / 2, GraphicsPanelView.BOX_SIZE / 2).a, 0.5)


func test_an_edit_updates_the_copy_profile_and_emits() -> void:
	var panel: GraphicsPanel = _panel()
	watch_signals(panel.view)
	var bloom: CheckBox = panel.view.find_child("bloom", true, false) as CheckBox
	assert_not_null(bloom)
	assert_true(bloom.button_pressed)
	bloom.button_pressed = false
	assert_false(panel.view.settings.bloom)
	assert_signal_emitted_with_parameters(panel.view, "edited", [panel.view.settings])
	assert_false(GraphicsProfile.current().bloom)
	assert_true(panel.save_pending())


func test_option_and_slider_edits_reach_the_copy() -> void:
	var panel: GraphicsPanel = _panel()
	var tonemapper: OptionButton = panel.view.find_child("tonemapper", true, false) as OptionButton
	tonemapper.select(2)
	tonemapper.item_selected.emit(2)
	assert_eq(panel.view.settings.tonemapper, GraphicsSettings.Tonemapper.FILMIC)
	var exposure: HSlider = panel.view.find_child("exposure", true, false) as HSlider
	exposure.value = 2.0
	assert_almost_eq(panel.view.settings.exposure, 2.0, 0.0001)
	assert_almost_eq(GraphicsProfile.current().exposure, 2.0, 0.0001)


func test_defaults_button_restores_defaults() -> void:
	var panel: GraphicsPanel = _panel()
	panel.view.set_field("ssao", true)
	assert_true(GraphicsProfile.current().ssao)
	panel.view.restore_defaults()
	assert_false(panel.view.settings.ssao)
	assert_false(GraphicsProfile.current().ssao)
	var ssao: CheckBox = panel.view.find_child("ssao", true, false) as CheckBox
	assert_false(ssao.button_pressed)


func test_the_toggle_key_toggles_the_view() -> void:
	var panel: GraphicsPanel = _panel()
	panel._unhandled_key_input(_toggle_key())
	assert_true(panel.is_open())
	panel._unhandled_key_input(_toggle_key(false))
	assert_true(panel.is_open(), "releases do nothing")
	panel._unhandled_key_input(_toggle_key())
	assert_false(panel.is_open())


func test_an_echoed_toggle_key_is_ignored() -> void:
	var panel: GraphicsPanel = _panel()
	panel._unhandled_key_input(_toggle_key(true, true))
	assert_false(panel.is_open())


func test_a_toggle_key_bound_to_a_game_action_does_not_toggle() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.CROAK, BindingInput.scancode(_toggle_key()))
	var target := SubViewport.new()
	add_child_autofree(target)
	var panel := BoundPanel.new()
	panel.input = BindingInput.new(bindings)
	add_child_autofree(panel)
	panel.activate(_path, target)
	panel._unhandled_key_input(_toggle_key())
	assert_false(panel.is_open())


func test_game_input_reads_the_saved_options() -> void:
	var free_key: int = KeyScancodes.UNKNOWN
	for scancode: int in KeyScancodes.bindable_scancodes():
		if not scancode in KeyBindings.DEFAULT_KEYS:
			free_key = scancode
			break
	var bindings := KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.CROAK, free_key)
	var store := ProgressStore.new()
	store.key_bindings = bindings.to_array()
	FrontEndSession.store = store
	var panel: GraphicsPanel = _panel()
	var event := InputEventKey.new()
	event.physical_keycode = KeyScancodes.godot_key(free_key) as Key
	event.location = KeyScancodes.godot_location(free_key) as KeyLocation
	assert_eq(panel.game_input().command(event), TickCommand.CROAK)


func test_save_goes_to_the_injected_path() -> void:
	var panel: GraphicsPanel = _panel()
	panel.view.set_field("bloom_intensity", 1.25)
	assert_false(FileAccess.file_exists(_path), "saving waits for the edit pause")
	panel.save_now()
	assert_false(panel.save_pending())
	assert_eq(panel.last_error, "")
	assert_true(FileAccess.file_exists(_path))
	assert_false(FileAccess.file_exists(GraphicsStore.DEFAULT_PATH))
	var loaded: GraphicsStore = GraphicsStore.load_from(_path)
	assert_almost_eq(loaded.settings.bloom_intensity, 1.25, 0.0001)


func test_debounced_save_writes_after_the_pause() -> void:
	var panel: GraphicsPanel = _panel()
	panel.view.set_field("vertex_tint", 0.5)
	await wait_seconds(GraphicsPanel.SAVE_DELAY + 0.3)
	assert_true(FileAccess.file_exists(_path))
	assert_almost_eq(GraphicsStore.load_from(_path).settings.vertex_tint, 0.5, 0.0001)
