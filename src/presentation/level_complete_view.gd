class_name LevelCompleteView
extends Control
## Draws the retail level-complete page over the map: a translucent grey veil across the whole
## control, then the sprites [LevelCompleteLayout] places for the open [LevelCompletePage] on the
## 640x480 canvas, scaled and centred as [GameplayHud] draws, nearest filtered.
##
## Checkpoint icons, the gold frog and digits come from the [GameplayHudAssets]; the next level's
## name is its in-game level-select image; every other label comes from the [FrontEndAssets] in
## the chosen language. Images that do not resolve are left out. The view reads no input.

## The 640x480 canvas the page is laid out on.
const CANVAS: Vector2 = Vector2(640, 480)
## The full-screen poly (RGB 0x60) blended as PSX average, half the scene and half the grey.
const OVERLAY_COLOUR := Color(0x60 / 255.0, 0x60 / 255.0, 0x60 / 255.0, 0.5)
## Image names whose widths centre text on the page.
const CENTRED_NAMES: PackedStringArray = ["next", "press_fire", "select4", "zone_complete"]

var _hud: GameplayHudAssets = null
var _text: FrontEndAssets = null
var _page: LevelCompletePage = null
var _level_texture: Texture2D = null
var _level_size: Vector2 = Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false


## Uses [param hud] for the icons and digits and [param text] for the labels; either may be null.
func configure(hud: GameplayHudAssets, text: FrontEndAssets) -> void:
	_hud = hud
	_text = text
	_resolve_level_name()
	queue_redraw()


## Shows [param page], resolving its next level's in-game name image.
func open(page: LevelCompletePage) -> void:
	_page = page
	_resolve_level_name()
	show()
	queue_redraw()


## Draws [param page] as it is now.
func present(page: LevelCompletePage) -> void:
	_page = page
	queue_redraw()


## Hides the view and forgets the page.
func close() -> void:
	_page = null
	_level_texture = null
	_level_size = Vector2.ZERO
	hide()
	queue_redraw()


## The padded retail widths of the centred labels and the next level's name, by image name.
func widths() -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	for image_name: String in CENTRED_NAMES:
		result[image_name] = int(_text.retail_size(image_name).x) if _text != null else 0
	result[LevelCompleteLayout.LEVEL_NAME_IMAGE] = int(_level_size.x)
	return result


## The sprites [method _draw] places for the open page, resolved or not; empty when closed.
func drawn_sprites() -> Array[LevelCompleteLayout.Sprite]:
	var result: Array[LevelCompleteLayout.Sprite] = []
	if _page != null:
		result = LevelCompleteLayout.sprites(_page, widths())
	return result


## The texture drawn for [param image_name], or null when it does not resolve.
func texture_for(image_name: String) -> Texture2D:
	if image_name == LevelCompleteLayout.LEVEL_NAME_IMAGE:
		return _level_texture
	if _from_hud(image_name):
		var hud_texture: Texture2D = _hud.textures.get(image_name, null) if _hud != null else null
		return hud_texture
	return _text.texture(image_name) if _text != null else null


## The size [param image_name] is drawn at on the 640x480 canvas, or zero when it does not resolve.
func retail_size_of(image_name: String) -> Vector2:
	if image_name == LevelCompleteLayout.LEVEL_NAME_IMAGE:
		return _level_size
	if _from_hud(image_name):
		return _hud.retail_size(image_name) if _hud != null else Vector2.ZERO
	return _text.retail_size(image_name) if _text != null else Vector2.ZERO


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OVERLAY_COLOUR)
	if _page == null:
		return
	var factor: float = minf(size.x / CANVAS.x, size.y / CANVAS.y)
	if factor <= 0.0:
		return
	draw_set_transform((size - CANVAS * factor) * 0.5, 0.0, Vector2.ONE * factor)
	for sprite: LevelCompleteLayout.Sprite in drawn_sprites():
		var texture: Texture2D = texture_for(sprite.image)
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2(sprite.at), retail_size_of(sprite.image)), false)
	draw_set_transform(Vector2.ZERO)


func _resolve_level_name() -> void:
	_level_texture = null
	_level_size = Vector2.ZERO
	if _page == null or _text == null or _page.next_level < 0:
		return
	_level_texture = _text.level_texture(_page.next_level, FrontEndAssets.LevelImage.GAME_NAME)
	if _level_texture != null:
		_level_size = _text.level_retail_size(_page.next_level, FrontEndAssets.LevelImage.GAME_NAME)


static func _from_hud(image_name: String) -> bool:
	return image_name.begins_with("babyfrog") or image_name.begins_with(LevelCompleteLayout.DIGIT_PREFIX)
