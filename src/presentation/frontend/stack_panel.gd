class_name StackPanel
extends Control
## The level-select stack's 2D sprites in the 640x480 display: title, prompt, level name,
## the subtractive fade and the LOADING image (SelectLevelStartup, SelectLevelUpdate).
##
## Sprite colours follow the source's base colours, 0x80 being the image as stored. The fade
## rectangle subtracts its shade from everything drawn before it; the sprites draw over it. The
## high-score view adds up to three score lines in [code]newfont[/code]'s 8x8 cells, white,
## centred in a box [constant StackLayout.SCORE_BOX_WIDTH] wide whose left edge is
## [member Placement.panel_x]. Each sprite is sized to its image's retail size, whatever the
## texture set's scale.

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
	## Whether the title sprite shows.
	var title_visible: bool = true
	## Left edge of the status box (Sel_status_temp_x).
	var panel_x: float = StackLayout.STATUS_START_X
	## Score lines drawn at [constant StackLayout.SCORE_LINE_Y], none outside the high-score view.
	var score_lines: PackedStringArray = PackedStringArray()

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
		result.title_visible = later.title_visible
		result.panel_x = lerpf(panel_x, later.panel_x, weight)
		result.score_lines = later.score_lines
		return result


## Base colour of the title and level name sprites.
const DIM_COLOUR: int = StackLayout.SPRITE_DIM_COLOUR
## Base colour meaning the image as stored.
const NEUTRAL_COLOUR: int = 0x80
## Right edge of the prompt sprite.
const PROMPT_RIGHT: int = StackLayout.STATUS_END_X + StackLayout.STATUS_WIDTH
## Width and height of one [code]newfont[/code] cell, and cells per row of the image.
const GLYPH_SIZE: int = 8
const GLYPHS_PER_ROW: int = 32

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
var _score_lines: PackedStringArray = PackedStringArray()
var _score_x: float = 0.0


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
	result.panel_x = selector.panel_x
	return result


## The left X of [param line] centred in the score box whose left edge is [param box_x].
static func score_line_x(line: String, box_x: float) -> float:
	return box_x + (StackLayout.SCORE_BOX_WIDTH - line.length() * GLYPH_SIZE) / 2


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
	title = _sprite(assets.texture("select_level"), assets.retail_size("select_level"), DIM_COLOUR)
	prompt = _sprite(assets.texture("select1"), assets.retail_size("select1"), NEUTRAL_COLOUR)
	level_name = _sprite(null, Vector2.ZERO, DIM_COLOUR)
	level_name.visible = false
	loading = _sprite(assets.texture("sel_loading"), assets.retail_size("sel_loading"), 0)
	loading.visible = false
	if loading.texture != null:
		loading.position = Vector2((StackLayout.DISPLAY_WIDTH >> 1) - (_width(loading) >> 1),
			(StackLayout.DISPLAY_HEIGHT >> 1) - (int(loading.size.y) >> 1))
	title.position.x = (StackLayout.DISPLAY_WIDTH >> 1) - (_width(title) >> 1)
	apply(Placement.new())


## Shows [param texture] as the level name, [param retail_size] big on the 640x480 display.
func set_level_name(texture: Texture2D, retail_size: Vector2) -> void:
	level_name.texture = texture
	_resize(level_name, retail_size)


## Moves and recolours the sprites to [param state].
func apply(state: Placement) -> void:
	title.position.y = state.title_y
	var prompt_texture: Texture2D = _assets.texture(state.prompt) if _assets != null else null
	if prompt.texture != prompt_texture:
		prompt.texture = prompt_texture
		_resize(prompt, _assets.retail_size(state.prompt))
	prompt.position = Vector2(PROMPT_RIGHT - _width(prompt), state.prompt_y)
	level_name.visible = state.name_visible
	level_name.position = Vector2(state.name_x, StackLayout.LEVEL_TITLE_Y)
	fade.visible = state.shade > 0
	var shade: float = state.shade / 255.0
	fade.color = Color(shade, shade, shade)
	loading.visible = state.loading_colour > 0
	loading.modulate = _colour(state.loading_colour)
	title.visible = state.title_visible
	if state.score_lines != _score_lines or state.panel_x != _score_x:
		_score_lines = state.score_lines
		_score_x = state.panel_x
		queue_redraw()


## The score lines drawn.
func score_lines() -> PackedStringArray:
	return _score_lines.duplicate()


func _draw() -> void:
	var font: Texture2D = _assets.texture("newfont") if _assets != null else null
	var record: VloImage = _assets.image_record("newfont") if _assets != null else null
	if font == null or record == null:
		return
	var source: Rect2 = TextureBuilder.texture_rect(record, font)
	var texels: Vector2 = TextureBuilder.texture_scale(record, font)
	for index: int in mini(_score_lines.size(), StackLayout.SCORE_LINE_Y.size()):
		var line: String = _score_lines[index]
		var at := Vector2(score_line_x(line, _score_x), StackLayout.SCORE_LINE_Y[index])
		for character: int in line.length():
			var code: int = line.unicode_at(character) - 32
			if code <= 0 or code >= GLYPHS_PER_ROW * 3:
				continue
			var cell := Vector2((code % GLYPHS_PER_ROW) * GLYPH_SIZE, (code / GLYPHS_PER_ROW) * GLYPH_SIZE)
			draw_texture_rect_region(font, Rect2(at + Vector2(character * GLYPH_SIZE, 0), Vector2(GLYPH_SIZE, GLYPH_SIZE)),
				Rect2(source.position + cell * texels, Vector2(GLYPH_SIZE, GLYPH_SIZE) * texels))


func _sprite(texture: Texture2D, retail_size: Vector2, colour: int) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.texture = texture
	sprite.modulate = _colour(colour)
	_resize(sprite, retail_size)
	add_child(sprite)
	return sprite


static func _resize(sprite: TextureRect, retail_size: Vector2) -> void:
	sprite.custom_minimum_size = retail_size
	sprite.size = retail_size


static func _width(sprite: TextureRect) -> int:
	return int(sprite.size.x) if sprite.texture != null else 0


static func _colour(colour: int) -> Color:
	var value: float = minf(float(colour) / NEUTRAL_COLOUR, 1.0)
	return Color(value, value, value)
