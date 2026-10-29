class_name SandboxPalette
extends PanelContainer
## Sandbox side panel: entity, form, path and speed choices, named presets, placement, teleport, reset and the zone legend.

const WIDTH: float = 200.0
const FONT_SIZE: int = 11
const PRESET_NAMES: PackedStringArray = ["Static", "Line", "Loop", "Speed"]
const DEFAULT_FORM: String = "Default form"
const KEY_HELP: String = "Arrows hop  Shift super hop  Ctrl tongue\nQ/E camera  Space pause  Esc menu\nTab palette  P place here  F place ahead\nBackspace delete last  X/Del delete here\nC clear all  [ ] entity  1-4 path\nO next preset  L load  K add\nZ go to zone  T go to cell  H reset frog\nR restart sandbox  F3 debug overlay"

var screen: SandboxScreen = null
var kinds: OptionButton = null
var forms: OptionButton = null
var presets: OptionButton = null
var layouts: OptionButton = null
var layout_description: Label = null
var speed: SpinBox = null
var zones: OptionButton = null
var cell_x: SpinBox = null
var cell_z: SpinBox = null
var debug_toggle: CheckButton = null
var status: Label = null
var legend: GridContainer = null

## Creates every control and connects them to `host_screen`'s actions.
func build(host_screen: SandboxScreen) -> void:
	screen = host_screen
	name = "SandboxPalette"
	position = Vector2(4, 4)
	custom_minimum_size = Vector2(WIDTH, 0)
	var palette_theme := Theme.new()
	palette_theme.default_font_size = FONT_SIZE
	theme = palette_theme
	var layout := VBoxContainer.new()
	add_child(layout)
	var tabs := TabContainer.new()
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.add_theme_font_size_override("font_size", 9)
	layout.add_child(tabs)
	tabs.add_child(_spawn_tab())
	tabs.add_child(_presets_tab())
	tabs.add_child(_move_tab())
	tabs.add_child(_zones_tab())
	var keys := Label.new()
	keys.name = "Keys"
	keys.text = KEY_HELP
	keys.add_theme_font_size_override("font_size", 9)
	tabs.add_child(keys)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(WIDTH - 8, 0)
	layout.add_child(status)
	refresh()

## Repopulates entity availability, forms and zones from the screen's spawner and arena.
func refresh() -> void:
	if kinds == null:
		return
	var previous: String = selected_kind()
	kinds.clear()
	for entity_name: String in SandboxSpawner.kind_names():
		kinds.add_item(entity_name)
		var index: int = kinds.item_count - 1
		var reason: String = kind_reason(entity_name)
		kinds.set_item_disabled(index, not reason.is_empty())
		kinds.set_item_tooltip(index, reason if not reason.is_empty() else "Available")
	kinds.select(-1)
	if not select_kind(previous):
		cycle_kind(1)
	zones.clear()
	if screen != null and screen.sandbox != null:
		for zone: SandboxLevel.Zone in screen.sandbox.zones:
			zones.add_item(String(zone.name))
	_build_legend()
	set_status(screen.data_status if screen != null and not screen.data_status.is_empty() else "Player data supplies entity models", false)

## Why `entity_name` cannot spawn with the screen's data, or "" when it can.
func kind_reason(entity_name: String) -> String:
	if screen == null or screen.spawner == null:
		return "The sandbox is not open"
	return screen.spawner.availability(entity_name).reason

## Whether the entity list shows `entity_name` disabled.
func is_kind_disabled(entity_name: String) -> bool:
	for index: int in kinds.item_count:
		if kinds.get_item_text(index) == entity_name:
			return kinds.is_item_disabled(index)
	return true

## Tooltip the entity list shows for `entity_name`.
func kind_tooltip(entity_name: String) -> String:
	for index: int in kinds.item_count:
		if kinds.get_item_text(index) == entity_name:
			return kinds.get_item_tooltip(index)
	return ""

## Selected FrogLord entity name, or "" when nothing can be selected.
func selected_kind() -> String:
	if kinds == null or kinds.selected < 0 or kinds.is_item_disabled(kinds.selected):
		return ""
	return kinds.get_item_text(kinds.selected)

## Selects an available `entity_name`; returns false when it is unknown or disabled.
func select_kind(entity_name: String) -> bool:
	for index: int in kinds.item_count:
		if kinds.get_item_text(index) == entity_name and not kinds.is_item_disabled(index):
			kinds.select(index)
			_refresh_forms()
			return true
	return false

## Moves the entity selection `step` places through the available names, wrapping around.
func cycle_kind(step: int) -> void:
	var count: int = kinds.item_count
	var start: int = kinds.selected if kinds.selected >= 0 else (count - 1 if step > 0 else 0)
	for offset: int in range(1, count + 1):
		var index: int = posmod(start + offset * signi(step), count)
		if not kinds.is_item_disabled(index):
			kinds.select(index)
			break
	_refresh_forms()

## Selected form variant name, or "" for the template's first form.
func selected_form() -> String:
	if forms == null or forms.selected <= 0:
		return ""
	return forms.get_item_text(forms.selected)

## Selects the form variant `form_name`; returns false when the selected entity has none.
func select_form(form_name: String) -> bool:
	for index: int in forms.item_count:
		if forms.get_item_text(index) == form_name:
			forms.select(index)
			return true
	return false

## Selected path preset.
func selected_preset() -> SandboxSpawner.Preset:
	return maxi(presets.selected, 0) as SandboxSpawner.Preset

## Selects the path preset `preset`.
func select_preset(preset: SandboxSpawner.Preset) -> void:
	presets.select(preset)

## Selected named preset, or "" when the list is empty.
func selected_layout() -> String:
	if layouts == null or layouts.selected < 0:
		return ""
	return layouts.get_item_text(layouts.selected)

## Selects the named preset `layout_name`; returns false when there is none.
func select_layout(layout_name: String) -> bool:
	for index: int in layouts.item_count:
		if layouts.get_item_text(index) == layout_name:
			layouts.select(index)
			_show_layout_description()
			return true
	return false

## Moves the preset selection `step` places, wrapping around.
func cycle_layout(step: int) -> void:
	if layouts.item_count == 0:
		return
	layouts.select(posmod(maxi(layouts.selected, 0) + step, layouts.item_count))
	_show_layout_description()

## Selected path speed; -1 keeps the authored or default speed.
func selected_speed() -> int:
	return int(speed.value)

## Selected teleport zone name.
func selected_zone() -> StringName:
	if zones.selected < 0:
		return &"plain"
	return StringName(zones.get_item_text(zones.selected))

## Selects the teleport zone `zone_name`; returns false when the arena has none.
func select_zone(zone_name: StringName) -> bool:
	for index: int in zones.item_count:
		if StringName(zones.get_item_text(index)) == zone_name:
			zones.select(index)
			return true
	return false

## Selected teleport cell.
func selected_cell() -> Vector2i:
	return Vector2i(int(cell_x.value), int(cell_z.value))

## Sets the teleport cell controls.
func select_cell(cell: Vector2i) -> void:
	cell_x.value = cell.x
	cell_z.value = cell.y

## Shows the latest action result, in red for an error.
func set_status(text: String, error: bool) -> void:
	if status == null:
		return
	status.text = text
	status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if error else Color(0.85, 0.95, 0.85))

## Mirrors the debug overlay state without re-entering the screen.
func sync_debug(shown: bool) -> void:
	if debug_toggle != null:
		debug_toggle.set_pressed_no_signal(shown)

func _spawn_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Spawn"
	kinds = _option(tab, "Entity: unavailable kinds are disabled; hover for the reason")
	kinds.item_selected.connect(_on_kind_selected)
	forms = _option(tab, "Form variant from the supplied levels")
	presets = _option(tab, "Path preset for path-following entities")
	for preset_name: String in PRESET_NAMES:
		presets.add_item(preset_name)
	speed = _spin(tab, "Speed ", -1, 1024, -1)
	speed.tooltip_text = "Path speed; -1 keeps the authored or default speed"
	var place_row := HBoxContainer.new()
	tab.add_child(place_row)
	_button(place_row, "Place here", "P", func() -> void: screen.place_at_frog())
	_button(place_row, "Place ahead", "F", func() -> void: screen.place_ahead())
	var delete_row := HBoxContainer.new()
	tab.add_child(delete_row)
	_button(delete_row, "Delete last", "Backspace", func() -> void: screen.remove_last())
	_button(delete_row, "Delete here", "X or Delete", func() -> void: screen.remove_at_frog())
	_button(tab, "Clear all", "C", func() -> void: screen.clear_entities())
	return tab

func _presets_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Presets"
	layouts = _option(tab, "Named layout; entries without player data are skipped and reported")
	for layout_name: String in SandboxPresets.names():
		layouts.add_item(layout_name)
	layouts.item_selected.connect(func(_index: int) -> void: _show_layout_description())
	layout_description = Label.new()
	layout_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout_description.custom_minimum_size = Vector2(WIDTH - 12, 0)
	tab.add_child(layout_description)
	var row := HBoxContainer.new()
	tab.add_child(row)
	_button(row, "Load", "L: replace the layout and move the frog to its start", func() -> void: screen.load_preset(selected_layout(), true))
	_button(row, "Add", "K: append to the current layout", func() -> void: screen.load_preset(selected_layout(), false))
	if layouts.item_count > 0:
		layouts.select(0)
	_show_layout_description()
	return tab

func _show_layout_description() -> void:
	var layout: SandboxPresets.Layout = SandboxPresets.named(selected_layout())
	layout_description.text = layout.description if layout != null else ""

func _move_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Move"
	zones = _option(tab, "Teleport zone: hazard zones teleport to the cell south of them")
	_button(tab, "Go to zone", "Z", func() -> void: screen.teleport_to_zone(selected_zone()))
	var cell_row := HBoxContainer.new()
	tab.add_child(cell_row)
	cell_x = _spin(cell_row, "X ", 0, SandboxLevel.DIMENSIONS.x - 1, SandboxLevel.SPAWN_CELL.x)
	cell_z = _spin(cell_row, "Z ", 0, SandboxLevel.DIMENSIONS.y - 1, SandboxLevel.SPAWN_CELL.y)
	var go_row := HBoxContainer.new()
	tab.add_child(go_row)
	_button(go_row, "Go to cell", "T", func() -> void: screen.teleport_to_cell(selected_cell()))
	_button(go_row, "Frog cell", "", func() -> void: select_cell(screen.frog_cell()))
	var reset_row := HBoxContainer.new()
	tab.add_child(reset_row)
	_button(reset_row, "Reset frog", "H", func() -> void: screen.reset_frog())
	_button(reset_row, "Restart", "R", func() -> void: screen.restart())
	debug_toggle = CheckButton.new()
	debug_toggle.text = "Debug overlay (F3)"
	debug_toggle.focus_mode = Control.FOCUS_NONE
	debug_toggle.toggled.connect(func(shown: bool) -> void: screen.set_debug_visible(shown))
	tab.add_child(debug_toggle)
	return tab

func _zones_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Zones"
	legend = GridContainer.new()
	legend.columns = 2
	tab.add_child(legend)
	return tab

func _build_legend() -> void:
	for child: Node in legend.get_children():
		legend.remove_child(child)
		child.queue_free()
	if screen == null or screen.sandbox == null:
		return
	for zone: SandboxLevel.Zone in screen.sandbox.zones:
		var swatch := ColorRect.new()
		swatch.color = SandboxScreen.ZONE_COLOURS.get(zone.name, SandboxScreen.UNKNOWN_ZONE_COLOUR)
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		var label := Label.new()
		label.text = "%s  x%d-%d z%d-%d" % [zone.name, zone.cells.position.x, zone.cells.end.x - 1, zone.cells.position.y, zone.cells.end.y - 1]
		legend.add_child(label)

func _refresh_forms() -> void:
	forms.clear()
	forms.add_item(DEFAULT_FORM)
	var entity_name: String = selected_kind()
	if screen != null and screen.templates != null and not entity_name.is_empty():
		for form_name: String in screen.templates.form_names(entity_name):
			forms.add_item(form_name)
	forms.select(0)
	forms.disabled = forms.item_count < 2

func _on_kind_selected(_index: int) -> void:
	_refresh_forms()

func _option(parent: Control, tip: String) -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.tooltip_text = tip
	option.fit_to_longest_item = false
	option.clip_text = true
	option.custom_minimum_size = Vector2(WIDTH - 12, 0)
	parent.add_child(option)
	return option

func _spin(parent: Control, prefix: String, minimum: int, maximum: int, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.prefix = prefix
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = initial
	spin.focus_mode = Control.FOCUS_NONE
	spin.get_line_edit().focus_mode = Control.FOCUS_NONE
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin

func _button(parent: Control, text: String, key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = key
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button
