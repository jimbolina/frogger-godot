class_name StackPanel
extends Control
## The level-select stack's 2D sprites in the 640x480 display: title, prompt, level name,
## the subtractive fade and the LOADING image (SelectLevelStartup, SelectLevelUpdate).
##
## Sprite colours follow the source's base colours, 0x80 being the image as stored. The fade
## rectangle subtracts its shade from everything drawn before it; the sprites draw over it.

## One frame's sprite state, interpolated between two ticks.
class Placement:
	extends RefCounted
	## Title sprite Y.
	var title_y: float = StackLayout.TITLE_Y
	## Prompt sprite Y.
	var prompt_y: float = StackLayout.PROMPT_Y
	## Level name sprite X.
	var name_x: float = StackLayout.STATUS_START_X
	## Whether the level name sprite shows.
	var name_visible: bool = false
	## The prompt image name in [constant FrontEndAssets.NAMES].
	var prompt: String = "select1"
	## Fade shade 0..255 subtracted from the stack.
	var shade: int = 0
	## LOADING sprite colour, 0 hiding it.
	var loading_colour: int = 0

	## This placement moved toward [param later] by [param weight]; discrete fields take [param later]'s.
	func toward(later: Placement, weight: float) -> Placement:
		var result := Placement.new()
		result.title_y = lerpf(title_y, later.title_y, weight)
		result.prompt_y = lerpf(prompt_y, later.prompt_y, weight)
		result.name_x = lerpf(name_x, later.name_x, weight) if name_visible == later.name_visible else later.name_x
		result.name_visible = later.name_visible
		result.prompt = later.prompt
		result.shade = later.shade
		result.loading_colour = later.loading_colour
		return result


## Base colour of the title and level name sprites.
const DIM_COLOUR: int = StackLayout.SPRITE_DIM_COLOUR
## Base colour meaning the image as stored.
const NEUTRAL_COLOUR: int = 0x80
## Right edge of the prompt sprite.
const PROMPT_RIGHT: int = StackLayout.STATUS_END_X + StackLayout.STATUS_WIDTH

## Fade rectangle over the 3D stack.
var fade: ColorRect
## Title sprite.
var title: TextureRect
## Prompt sprite.
var prompt: TextureRect
## Level name sprite.
var level_name: TextureRect
## LOADING sprite.
var loading: TextureRect

var _assets: FrontEndAssets


## The prompt image while in selector [param mode]: SELECT2 in the info view and fade, otherwise
## SELECT1 until the first level is chosen and SELECT5 after.
static func prompt_name(mode: int, first_time: bool) -> String:
	if mode != StackSelector.Mode.SELECTING:
		return "select2"
	return "select1" if first_time else "select5"


## The sprite placement for [param selector]'s committed state.
static func placement(selector: StackSelector) -> Placement:
	var result := Placement.new()
	var fading: bool = selector.mode == StackSelector.Mode.START_FADE or selector.mode == StackSelector.Mode.UPDATE_FADE
	result.prompt = prompt_name(selector.mode, selector.first_time)
	result.name_visible = selector.mode != StackSelector.Mode.SELECTING
	if fading and selector.fade_count > 0:
		result.title_y = selector.fade_title_y
		result.prompt_y = selector.fade_prompt_y
		result.name_x = selector.fade_name_x
		result.loading_colour = selector.fade_loading_colour()
	else:
		result.name_x = selector.title_x
	result.shade = selector.fade_shade()
	return result


## Builds the sprites from [param assets]; the level name is set per level with [method set_level_name].
func setup(assets: FrontEndAssets) -> void:
	_assets = assets
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade = ColorRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.position = Vector2.ZERO
	fade.size = Vector2(StackLayout.DISPLAY_WIDTH, StackLayout.DISPLAY_HEIGHT)
	var subtract := CanvasItemMaterial.new()
	subtract.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	fade.material = subtract
	fade.visible = false
	add_child(fade)
	title = _sprite(assets.texture("select_level"), DIM_COLOUR)
	prompt = _sprite(assets.texture("select1"), NEUTRAL_COLOUR)
	level_name = _sprite(null, DIM_COLOUR)
	level_name.visible = false
	loading = _sprite(assets.texture("sel_loading"), 0)
	loading.visible = false
	if loading.texture != null:
		loading.position = Vector2((StackLayout.DISPLAY_WIDTH >> 1) - (loading.texture.get_width() >> 1),
			(StackLayout.DISPLAY_HEIGHT >> 1) - (loading.texture.get_height() >> 1))
	title.position.x = (StackLayout.DISPLAY_WIDTH >> 1) - (_width(title) >> 1)
	apply(Placement.new())


## Shows [param texture] as the level name.
func set_level_name(texture: Texture2D) -> void:
	level_name.texture = texture
	level_name.size = Vector2.ZERO


## Moves and recolours the sprites to [param state].
func apply(state: Placement) -> void:
	title.position.y = state.title_y
	var prompt_texture: Texture2D = _assets.texture(state.prompt) if _assets != null else null
	if prompt.texture != prompt_texture:
		prompt.texture = prompt_texture
		prompt.size = Vector2.ZERO
	prompt.position = Vector2(PROMPT_RIGHT - _width(prompt), state.prompt_y)
	level_name.visible = state.name_visible
	level_name.position = Vector2(state.name_x, StackLayout.LEVEL_TITLE_Y)
	fade.visible = state.shade > 0
	var shade: float = state.shade / 255.0
	fade.color = Color(shade, shade, shade)
	loading.visible = state.loading_colour > 0
	loading.modulate = _colour(state.loading_colour)


func _sprite(texture: Texture2D, colour: int) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.texture = texture
	sprite.modulate = _colour(colour)
	add_child(sprite)
	return sprite


static func _width(sprite: TextureRect) -> int:
	return sprite.texture.get_width() if sprite.texture != null else 0


static func _colour(colour: int) -> Color:
	var value: float = minf(float(colour) / NEUTRAL_COLOUR, 1.0)
	return Color(value, value, value)
