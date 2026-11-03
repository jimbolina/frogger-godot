class_name PauseView
extends Control
## Draws retail's in-game pause page over the world: the subtractive fade, then the PAUSED,
## CONTINUE and QUIT sprites and, in the quit menu, YES and NO, on the 640x480 canvas scaled and
## centred as [GameplayHud] draws, nearest filtered.
##
## The fade is pause.c's full-screen black-based poly at ABR 2 (GamePauseCreateFadePoly,
## :792-824) whose grey rises [constant PausePage.FADE_STEP] a tick to
## [constant PausePage.FADE_END]; ABR 2 subtracts that grey from the frame, drawn here as a
## [constant CanvasItemMaterial.BLEND_MODE_SUB] rectangle of [method fade_colour], as the attract
## fade does. Sprite top-left corners come from [method PausePage.sprite_x] and
## [method PausePage.sprite_y] with each label's retail width (pause.c:205-207, :556-606). The
## glowing sprite's base colour is [method PausePage.glow], where 0x80 is neutral
## (OPTIONS.C:381-414), so it is modulated by that grey over 0x80, capped at white; the others are
## drawn white.
##
## Port note: retail adds the fade to the options viewport's ordering table, and whether it also
## darkens retail's HUD is unverified; this view sits above the HUD, so the HUD dims with the
## world. The PC executable's ABR for the fade's carrier primitives is also unconfirmed.

## The 640x480 canvas the page is laid out on.
const CANVAS: Vector2 = Vector2(640, 480)
## The sprites in drawing order.
const SPRITES: Array[PausePage.Sprite] = [
	PausePage.Sprite.PAUSED, PausePage.Sprite.CONTINUE, PausePage.Sprite.QUIT, PausePage.Sprite.YES,
	PausePage.Sprite.NO,
]
## The image of each sprite, by [enum PausePage.Sprite].
const IMAGES: Dictionary[PausePage.Sprite, String] = {
	PausePage.Sprite.PAUSED: PausePage.PAUSED_IMAGE,
	PausePage.Sprite.CONTINUE: PausePage.CONTINUE_IMAGE,
	PausePage.Sprite.QUIT: PausePage.QUIT_IMAGE,
	PausePage.Sprite.YES: PausePage.YES_IMAGE,
	PausePage.Sprite.NO: PausePage.NO_IMAGE,
}


## One sprite as [method PauseView._draw] places it on the 640x480 canvas.
class PlacedSprite:
	extends RefCounted
	## The [FrontEndAssets] image name.
	var image: String = ""
	## The left edge on the canvas.
	var x: int = 0
	## The top edge on the canvas.
	var y: int = 0
	## The colour the image is modulated by.
	var modulate: Color = Color.WHITE


## The labels' images, or null before [method configure].
var _assets: FrontEndAssets = null
## The page drawn, or null when none is shown.
var _page: PausePage = null
## The subtractive fade, drawn behind this control's sprites.
var _fade: ColorRect = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.show_behind_parent = true
	var subtract := CanvasItemMaterial.new()
	subtract.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_fade.material = subtract
	_fade.visible = false
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The grey ABR 2 subtracts from the frame at fade colour [param level] (0..0x80 of 255).
static func fade_colour(level: int) -> Color:
	var grey: float = clampi(level, 0, 255) / 255.0
	return Color(grey, grey, grey)


## The modulate of a sprite whose base colour is [param grey], 0x80 being the image's own colours.
static func glow_modulate(grey: int) -> Color:
	var value: float = minf(grey / 128.0, 1.0)
	return Color(value, value, value)


## Uses [param assets] for the labels; returns why a label cannot be drawn, or "".
func configure(assets: FrontEndAssets) -> String:
	_assets = assets
	queue_redraw()
	if assets == null:
		return "Pause page requires the front-end images"
	if not assets.error.is_empty():
		return "Pause page: " + assets.error
	var missing := PackedStringArray()
	for sprite: PausePage.Sprite in SPRITES:
		if assets.texture(IMAGES[sprite]) == null:
			missing.append(IMAGES[sprite])
	return "" if missing.is_empty() else "Pause page images are missing: " + ", ".join(missing)


## Draws [param page] as it is now.
func present(page: PausePage) -> void:
	_page = page
	_update_fade()
	queue_redraw()


## Forgets the page and draws nothing.
func clear() -> void:
	_page = null
	_update_fade()
	queue_redraw()


## The fade grey drawn now, or 0 when no fade shows.
func fade_level() -> int:
	return _page.fade_level if _page != null else 0


## The sprites [method _draw] places for the page as it is now; empty when none show.
func sprites() -> Array[PlacedSprite]:
	var result: Array[PlacedSprite] = []
	if _page == null or not _page.shows_sprites():
		return result
	var glowing: PausePage.Sprite = _page.glowing_sprite()
	for sprite: PausePage.Sprite in SPRITES:
		if (sprite == PausePage.Sprite.YES or sprite == PausePage.Sprite.NO) and not _page.shows_quit():
			continue
		var placed := PlacedSprite.new()
		placed.image = IMAGES[sprite]
		placed.x = PausePage.sprite_x(_width(placed.image), sprite)
		placed.y = PausePage.sprite_y(sprite)
		if sprite == glowing:
			placed.modulate = glow_modulate(PausePage.glow(_page.frame))
		result.append(placed)
	return result


func _draw() -> void:
	if _assets == null:
		return
	var factor: float = minf(size.x / CANVAS.x, size.y / CANVAS.y)
	if factor <= 0.0:
		return
	draw_set_transform((size - CANVAS * factor) * 0.5, 0.0, Vector2.ONE * factor)
	for placed: PlacedSprite in sprites():
		var texture: Texture2D = _assets.texture(placed.image)
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2(placed.x, placed.y), _assets.retail_size(placed.image)), false, placed.modulate)
	draw_set_transform(Vector2.ZERO)


func _update_fade() -> void:
	var level: int = fade_level()
	_fade.visible = level > 0
	_fade.color = fade_colour(level)


func _width(image_name: String) -> int:
	return int(_assets.retail_size(image_name).x) if _assets != null else 0
