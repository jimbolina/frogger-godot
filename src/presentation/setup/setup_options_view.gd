class_name SetupOptionsView
extends SetupPageView
## The settings page: language, window mode and size, vsync, the music and
## effects volumes and the texture pack.

## Where the note says texture packs are installed.
const TEXTURE_PACKS_FOLDER: String = "texture_packs in the game's user folder"

var _language: OptionButton
var _mode: OptionButton
var _size: OptionButton
var _vsync: CheckBox
var _music: HSlider
var _music_value: Label
var _sound: HSlider
var _sound_value: Label
var _textures: OptionButton
var _textures_note: Label


func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	_language = _option_row(grid, "Language")
	_language.add_item("Automatic (system language)")
	_language.set_item_metadata(0, GameLanguage.AUTO)
	for id: int in range(GameLanguage.COUNT):
		_language.add_item(GameLanguage.NAMES[id])
		_language.set_item_metadata(id + 1, id)
	_language.item_selected.connect(func(index: int) -> void:
		var value: int = _language.get_item_metadata(index)
		flow.options.set_language(value)
		edited.emit())
	_mode = _option_row(grid, "Window")
	_mode.add_item("Windowed")
	_mode.add_item("Fullscreen")
	_mode.item_selected.connect(func(index: int) -> void:
		flow.options.set_fullscreen(index == 1)
		refresh()
		edited.emit())
	_size = _option_row(grid, "Window size")
	_size.item_selected.connect(func(index: int) -> void:
		var chosen: Vector2i = _size.get_item_metadata(index)
		flow.options.set_window_size(chosen)
		edited.emit())
	_label(grid, "Vsync")
	_vsync = CheckBox.new()
	_vsync.text = "Wait for the display"
	_vsync.toggled.connect(func(on: bool) -> void:
		flow.options.set_vsync(on)
		edited.emit())
	grid.add_child(_vsync)
	var music: Array = _slider_row(grid, "Music volume")
	_music = music[0]
	_music_value = music[1]
	_music.value_changed.connect(func(value: float) -> void:
		flow.options.set_music_volume(roundi(value))
		refresh()
		edited.emit())
	var sound: Array = _slider_row(grid, "Effects volume")
	_sound = sound[0]
	_sound_value = sound[1]
	_sound.value_changed.connect(func(value: float) -> void:
		flow.options.set_sound_volume(roundi(value))
		refresh()
		edited.emit())
	_textures = _option_row(grid, "Textures")
	_textures.item_selected.connect(func(index: int) -> void:
		var chosen: String = _textures.get_item_metadata(index)
		flow.options.set_texture_pack(chosen)
		edited.emit())
	_textures_note = add_text(self, "", true)


func refresh() -> void:
	var options: SetupOptions = flow.options
	for index: int in range(_language.item_count):
		var value: int = _language.get_item_metadata(index)
		if value == options.language:
			_language.select(index)
	_mode.select(1 if options.is_fullscreen() else 0)
	_size.clear()
	for offered: Vector2i in options.window_sizes():
		_size.add_item("Default (640 × 480)" if offered == Vector2i.ZERO else "%d × %d" % [offered.x, offered.y])
		_size.set_item_metadata(_size.item_count - 1, offered)
		if offered == options.window_size:
			_size.select(_size.item_count - 1)
	_size.disabled = options.is_fullscreen()
	_vsync.set_pressed_no_signal(options.is_vsync())
	_music.set_value_no_signal(options.music_volume)
	_music_value.text = str(options.music_volume)
	_sound.set_value_no_signal(options.sound_volume)
	_sound_value.text = str(options.sound_volume)
	_textures.clear()
	_textures.add_item(SetupOptions.pack_label(null))
	_textures.set_item_metadata(0, "")
	for pack: TexturePack in options.texture_packs:
		_textures.add_item(SetupOptions.pack_label(pack))
		_textures.set_item_metadata(_textures.item_count - 1, pack.pack_name)
		if pack.pack_name == options.texture_pack:
			_textures.select(_textures.item_count - 1)
	if options.texture_pack.is_empty():
		_textures.select(0)
	_textures_note.text = "Volumes run from 0 (off) to 8. No texture packs are installed in %s." \
		% TEXTURE_PACKS_FOLDER if options.texture_packs.is_empty() \
		else "Volumes run from 0 (off) to 8. A texture pack draws its own images; the rest stay original."


func shown() -> void:
	screen.offer_texture_packs()
	refresh()


func _label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)


func _option_row(grid: GridContainer, text: String) -> OptionButton:
	_label(grid, text)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(option)
	return option


func _slider_row(grid: GridContainer, text: String) -> Array:
	_label(grid, text)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = ProgressStore.MAX_VOLUME
	slider.step = 1
	slider.tick_count = ProgressStore.MAX_VOLUME + 1
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 24
	row.add_child(value)
	return [slider, value]
