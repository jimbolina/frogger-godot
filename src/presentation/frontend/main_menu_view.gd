class_name MainMenuView
extends Control
## The main menu's Start, Options and Exit sprites on their 16-pixel rows over the subtractive
## cloud poly (MainOptionsStartup, tempopt.c:1209-1290).
##
## Up and Down hop between the rows and wrap (:1712-1744); a focus move asks for the hop sound
## except the menu's first focus. Fire croaks and reports the focused row's [enum Kind] (:1811-1820)
## unless the host has closed [member fire_allowed], when the press is ignored silently. The host
## slides the sprites and the cloud below their rest rows during the fly-on and fly-off
## (:1484-1490, :1648-1652), and the same view serves the main menu and the attract demo.

enum Kind { START, OPTIONS, EXIT }

## FrogLord name of the generic hop sound (SFX_GEN_FROG_HOP).
const HOP_SOUND: String = "GEN_FROG_HOP"
## FrogLord name of the generic croak sound (SFX_GEN_FROG_CROAK).
const CROAK_SOUND: String = "GEN_FROG_CROAK"
## The menu image of each [enum Kind], top to bottom.
const IMAGES: PackedStringArray = ["opt_start", "opt_options", "opt_exit"]
## The first sprite row, MAIN_MENU_Y_OFFSET above the bottom once the fly-on has lifted it 8 a
## tick for 10 ticks (tempopt.c:1222-1226, :1486-1488); the rows are 16 apart.
const MENU_ROW_Y: int = StackLayout.DISPLAY_HEIGHT - 80
const MENU_ROW_PITCH: int = 16
## The cloud poly's border around the widest sprite and its subtractive colour (tempopt.c:1237-1266).
const CLOUD_BORDER: int = 8
const CLOUD_COLOUR: Color = Color(0.25, 0.25, 0.25)
## Modulate of the focused sprite.
const FOCUS_COLOUR: Color = Color(1.0, 1.0, 0.6)

## A row's [enum Kind] was fired.
signal menu_event(kind: int)
## The view asks the host to play the sound called [param sound_name].
signal sound_requested(sound_name: String)

## The focused row, 0..2 (Option_number).
var option_number: int = 0
## Whether fire is read; the host closes it during fly-ons, fly-offs and loading (:1811-1817).
var fire_allowed: bool = true
## The sprites top to bottom.
var sprites: Array[TextureButton] = []
## The subtractive cloud behind the sprites.
var cloud: TextureRect

var _slide: int = 0
var _focused: bool = false
var _quiet: bool = false


## A menu drawn from [param assets]' images over [param cloud_texture]; either may lack a
## texture, which leaves that sprite or the cloud blank.
static func create(assets: FrontEndAssets, cloud_texture: Texture2D) -> MainMenuView:
	var view := MainMenuView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view._build(assets, cloud_texture)
	return view


## Places the sprites and the cloud [param pixels] below their rest rows.
func set_slide(pixels: int) -> void:
	_slide = pixels
	_place()


## The current slide below the rest rows.
func slide() -> int:
	return _slide


## Focuses row [param index] without the hop sound; the row is kept for the deferred first focus
## when the view is not yet in the tree.
func focus_row(index: int) -> void:
	option_number = clampi(index, 0, sprites.size() - 1)
	if not is_inside_tree():
		return
	_quiet = true
	sprites[option_number].grab_focus()
	_quiet = false


## Focuses [member option_number] once the frame's tree changes have settled.
func grab_first_focus() -> void:
	_grab_current.call_deferred()


func _grab_current() -> void:
	if is_inside_tree():
		focus_row(option_number)


func _build(assets: FrontEndAssets, cloud_texture: Texture2D) -> void:
	for index: int in IMAGES.size():
		sprites.append(_sprite(assets, IMAGES[index], index))
	var width: int = 0
	var last_height: int = 0
	for sprite: TextureButton in sprites:
		if sprite.texture_normal != null:
			width = maxi(width, int(sprite.custom_minimum_size.x))
			last_height = int(sprite.custom_minimum_size.y)
	width += CLOUD_BORDER << 1
	cloud = TextureRect.new()
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloud.texture = cloud_texture
	cloud.stretch_mode = TextureRect.STRETCH_SCALE
	cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloud.modulate = CLOUD_COLOUR
	var cloud_material := CanvasItemMaterial.new()
	cloud_material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	cloud.material = cloud_material
	cloud.size = Vector2(width, MENU_ROW_PITCH * 2 + last_height + 16 + CLOUD_BORDER)
	add_child(cloud)
	for sprite: TextureButton in sprites:
		add_child(sprite)
	var count: int = sprites.size()
	for index: int in count:
		var sprite: TextureButton = sprites[index]
		sprite.focus_neighbor_top = sprite.get_path_to(sprites[(index + count - 1) % count])
		sprite.focus_neighbor_bottom = sprite.get_path_to(sprites[(index + 1) % count])
	_place()


func _sprite(assets: FrontEndAssets, image_name: String, index: int) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = assets.texture(image_name) if assets != null else null
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.custom_minimum_size = assets.retail_size(image_name) if assets != null else Vector2.ZERO
	button.size = button.custom_minimum_size
	button.pressed.connect(_on_pressed.bind(index))
	button.focus_entered.connect(_on_focus.bind(index))
	button.focus_exited.connect(button.set_modulate.bind(Color.WHITE))
	return button


func _on_focus(index: int) -> void:
	sprites[index].modulate = FOCUS_COLOUR
	option_number = index
	if _focused and not _quiet:
		sound_requested.emit(HOP_SOUND)
	_focused = true


func _on_pressed(index: int) -> void:
	if not fire_allowed:
		return
	option_number = index
	sound_requested.emit(CROAK_SOUND)
	menu_event.emit(index)


func _place() -> void:
	for index: int in sprites.size():
		var sprite: TextureButton = sprites[index]
		var sprite_width: int = int(sprite.custom_minimum_size.x) if sprite.texture_normal != null else 0
		sprite.position = Vector2((StackLayout.DISPLAY_WIDTH - sprite_width) >> 1, MENU_ROW_Y + index * MENU_ROW_PITCH + _slide)
	if cloud != null:
		cloud.position = Vector2((StackLayout.DISPLAY_WIDTH - int(cloud.size.x)) >> 1, MENU_ROW_Y - CLOUD_BORDER + _slide)
