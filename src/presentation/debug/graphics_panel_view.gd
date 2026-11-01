class_name GraphicsPanelView
extends ScrollContainer
## Scrolling side panel of graphics controls bound to a working [GraphicsSettings] copy.
##
## Every control takes no keyboard focus, so game keys keep reaching the game
## while the panel is open; it is driven by the mouse. Each change updates the
## copy and emits [signal edited] with it.

## Emitted after any control changes [member settings].
signal edited(settings: GraphicsSettings)

## Panel width in base-viewport pixels.
const WIDTH: float = 232.0
## Font size of every control.
const FONT_SIZE: int = 10
## Width of the row titles.
const TITLE_WIDTH: float = 78.0
## Width of the slider value readouts.
const VALUE_WIDTH: float = 34.0
## Panel background.
const BACKGROUND: Color = Color(0.04, 0.05, 0.08, 0.78)
## Section heading colour.
const HEADING: Color = Color(1.0, 0.84, 0.36)
## Window size presets; zero keeps the launch size.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(640, 480), Vector2i(960, 720), Vector2i(1280, 960), Vector2i(1600, 1200),
	Vector2i(1920, 1440), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
]
## Frame cap presets; zero is uncapped.
const FRAME_CAPS: Array[int] = [0, 30, 60, 120, 144, 240]
## Directional shadow atlas presets.
const ATLAS_SIZES: Array[int] = [1024, 2048, 4096, 8192]
## Directional shadow split presets.
const SPLITS: Array[int] = [1, 2, 4]
## Scaler names in [enum GraphicsSettings.Scaler] order.
const SCALER_NAMES: PackedStringArray = ["Bilinear", "FSR 1.0", "FSR 2.2", "MetalFX spatial", "MetalFX temporal"]

## The working copy the controls edit.
var settings: GraphicsSettings = GraphicsSettings.new()
## Frame statistics at the top of the panel.
var stats: FrameStatsLabel = null
## How the current quality choices interact.
var notes: Label = null

var _rows: VBoxContainer = null
var _refreshers: Array[Callable] = []


## Creates every control over a copy of [param values].
func build(values: GraphicsSettings) -> void:
	name = "GraphicsPanelView"
	settings = values.copy()
	var panel_theme := Theme.new()
	panel_theme.default_font_size = FONT_SIZE
	theme = panel_theme
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -WIDTH
	offset_right = 0.0
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_NONE
	get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.set_content_margin_all(5.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.focus_mode = Control.FOCUS_NONE
	add_child(panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.focus_mode = Control.FOCUS_NONE
	panel.add_child(_rows)
	stats = FrameStatsLabel.new()
	stats.focus_mode = Control.FOCUS_NONE
	_rows.add_child(stats)
	_display_section()
	_quality_section()
	_shadow_section()
	_post_section()
	_effects_section()
	_look_section()
	var defaults := Button.new()
	defaults.text = "Defaults"
	defaults.focus_mode = Control.FOCUS_NONE
	defaults.pressed.connect(restore_defaults)
	_rows.add_child(defaults)
	refresh()


## Shows [member settings] in every control without emitting [signal edited].
func refresh() -> void:
	for refresher: Callable in _refreshers:
		refresher.call()
	_show_notes()


## Replaces [member settings] with the defaults, shows them and emits [signal edited].
func restore_defaults() -> void:
	settings.assign(GraphicsSettings.new())
	refresh()
	edited.emit(settings)


## Sets [param field] of [member settings] to [param value] as a control would.
func set_field(field: String, value: Variant) -> void:
	settings.set(field, value)
	_show_notes()
	edited.emit(settings)


func _display_section() -> void:
	_heading("Display")
	_choice("Window", "window_mode", ["Windowed", "Borderless full", "Exclusive full"], [
		GraphicsSettings.WindowMode.WINDOWED, GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN,
		GraphicsSettings.WindowMode.EXCLUSIVE_FULLSCREEN,
	])
	var size_names := PackedStringArray()
	var size_values: Array = []
	for window_size: Vector2i in WINDOW_SIZES:
		size_names.append("Launch size" if window_size == Vector2i.ZERO else "%dx%d" % [window_size.x, window_size.y])
		size_values.append(window_size)
	_choice("Resolution", "window_size", size_names, size_values)
	_choice("Vsync", "vsync", ["Off", "On", "Adaptive", "Mailbox"], [
		GraphicsSettings.Vsync.DISABLED, GraphicsSettings.Vsync.ENABLED,
		GraphicsSettings.Vsync.ADAPTIVE, GraphicsSettings.Vsync.MAILBOX,
	])
	var cap_names := PackedStringArray()
	var cap_values: Array = []
	for cap: int in FRAME_CAPS:
		cap_names.append("Uncapped" if cap == 0 else str(cap))
		cap_values.append(cap)
	_choice("Max FPS", "max_fps", cap_names, cap_values)


func _quality_section() -> void:
	_heading("Quality")
	_slider("Render scale", "render_scale", GraphicsSettings.MIN_RENDER_SCALE, GraphicsSettings.MAX_RENDER_SCALE, 0.05)
	var scaler_names := PackedStringArray()
	var scaler_values: Array = []
	for scaler: int in GraphicsSettings.Scaler.values():
		if GraphicsApplier.scaler_available(scaler as GraphicsSettings.Scaler):
			scaler_names.append(SCALER_NAMES[scaler])
			scaler_values.append(scaler)
	_choice("Scaler", "scaler", scaler_names, scaler_values)
	_slider("FSR sharpness", "fsr_sharpness", 0.0, GraphicsSettings.MAX_FSR_SHARPNESS, 0.05)
	_choice("MSAA", "msaa", ["Off", "2x", "4x", "8x"], [
		GraphicsSettings.Msaa.OFF, GraphicsSettings.Msaa.X2, GraphicsSettings.Msaa.X4, GraphicsSettings.Msaa.X8,
	])
	_choice("Screen AA", "screen_aa", ["Off", "FXAA", "SMAA"], [
		GraphicsSettings.ScreenAa.OFF, GraphicsSettings.ScreenAa.FXAA, GraphicsSettings.ScreenAa.SMAA,
	])
	_check("TAA", "taa")
	notes = Label.new()
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.custom_minimum_size = Vector2(WIDTH - 24.0, 0.0)
	notes.modulate = Color(0.8, 0.85, 0.95)
	notes.focus_mode = Control.FOCUS_NONE
	_rows.add_child(notes)


func _shadow_section() -> void:
	_heading("Shadows")
	_check("Real shadows", "real_shadows")
	var atlas_names := PackedStringArray()
	var atlas_values: Array = []
	for atlas: int in ATLAS_SIZES:
		atlas_names.append(str(atlas))
		atlas_values.append(atlas)
	_choice("Atlas size", "shadow_atlas_size", atlas_names, atlas_values)
	_choice("Soft quality", "soft_shadow_quality", ["Hard", "Very low", "Low", "Medium", "High", "Ultra"], [
		GraphicsSettings.SoftShadow.HARD, GraphicsSettings.SoftShadow.VERY_LOW, GraphicsSettings.SoftShadow.LOW,
		GraphicsSettings.SoftShadow.MEDIUM, GraphicsSettings.SoftShadow.HIGH, GraphicsSettings.SoftShadow.ULTRA,
	])
	var split_names := PackedStringArray()
	var split_values: Array = []
	for split: int in SPLITS:
		split_names.append(str(split))
		split_values.append(split)
	_choice("Splits", "shadow_splits", split_names, split_values)
	_slider("First split", "shadow_split_1", 0.05, 0.95, 0.05)
	_slider("Max distance", "shadow_max_distance", 4.0, 128.0, 1.0)
	_slider("Bias", "shadow_bias", 0.0, 0.5, 0.005)
	_slider("Normal bias", "shadow_normal_bias", 0.0, 4.0, 0.05)


func _post_section() -> void:
	_heading("Post")
	_check("Bloom", "bloom")
	_slider("Intensity", "bloom_intensity", 0.0, 4.0, 0.05)
	_slider("Threshold", "bloom_threshold", 0.0, 4.0, 0.05)
	_choice("Tonemapper", "tonemapper", ["Linear", "Reinhard", "Filmic", "ACES", "AgX"], [
		GraphicsSettings.Tonemapper.LINEAR, GraphicsSettings.Tonemapper.REINHARD,
		GraphicsSettings.Tonemapper.FILMIC, GraphicsSettings.Tonemapper.ACES, GraphicsSettings.Tonemapper.AGX,
	])
	_slider("Exposure", "exposure", 0.1, 4.0, 0.05)
	_check("SSAO", "ssao")


func _effects_section() -> void:
	_heading("Effects")
	_slider("Halo strength", "glow_halo_strength", 0.0, 8.0, 0.1)
	_check("Glow lights", "glow_lights")
	_check("Glow lights in caves", "glow_lights_in_caves")
	_slider("Light energy", "glow_light_energy", 0.0, 4.0, 0.05)
	_slider("Lava emission", "lava_emission", 0.0, 4.0, 0.05)
	_check("Lava lights", "lava_lights")


func _look_section() -> void:
	_heading("Look")
	_slider("Water reflect", "water_reflection", 0.0, 1.0, 0.01)
	_slider("Water specular", "water_specular", 0.0, 1.0, 0.01)
	_slider("Shininess", "water_shininess", 1.0, 1024.0, 1.0)
	_slider("Vertex tint", "vertex_tint", 0.0, 2.0, 0.05)
	_choice("Cave light", "cave_light_mode", ["Exact edge", "Fitted range"], [
		GraphicsSettings.CaveMode.EXACT_EDGE, GraphicsSettings.CaveMode.FITTED_RANGE,
	])


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING)
	label.focus_mode = Control.FOCUS_NONE
	_rows.add_child(label)


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.focus_mode = Control.FOCUS_NONE
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(TITLE_WIDTH, 0.0)
	label.clip_text = true
	label.focus_mode = Control.FOCUS_NONE
	row.add_child(label)
	_rows.add_child(row)
	return row


func _choice(title: String, field: String, names: PackedStringArray, values: Array) -> OptionButton:
	var option := OptionButton.new()
	option.name = field
	option.focus_mode = Control.FOCUS_NONE
	option.fit_to_longest_item = false
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in names:
		option.add_item(item)
	option.item_selected.connect(func(index: int) -> void: set_field(field, values[index]))
	_refreshers.append(func() -> void: _select(option, values, settings.get(field)))
	_row(title).add_child(option)
	return option


func _select(option: OptionButton, values: Array, value: Variant) -> void:
	var index: int = values.find(value)
	if index < 0:
		option.add_item(str(value))
		values.append(value)
		index = values.size() - 1
	option.select(index)


func _check(title: String, field: String) -> CheckBox:
	var box := CheckBox.new()
	box.name = field
	box.text = title
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(pressed: bool) -> void: set_field(field, pressed))
	_refreshers.append(func() -> void:
		var pressed: bool = settings.get(field)
		box.set_pressed_no_signal(pressed))
	_rows.add_child(box)
	return box


func _slider(title: String, field: String, low: float, high: float, step: float) -> HSlider:
	var row: HBoxContainer = _row(title)
	var slider := HSlider.new()
	slider.name = field
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.focus_mode = Control.FOCUS_NONE
	row.add_child(readout)
	var digits: String = "%.0f" if step >= 1.0 else ("%.3f" if step < 0.01 else "%.2f")
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = digits % value
		set_field(field, value))
	_refreshers.append(func() -> void:
		var stored: float = settings.get(field)
		slider.set_value_no_signal(stored)
		readout.text = digits % stored)
	return slider


func _show_notes() -> void:
	if notes != null:
		notes.text = "\n".join(GraphicsApplier.quality_notes(settings))
