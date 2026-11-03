class_name GameOverView
extends Control
## Draws retail PC's game-over page over the world: the display clear colour, black for every
## level (Game_back_colour, gamesys.C:85), around the shrinking game viewport, then the
## opt_gameover sprite centred on the 640x480 canvas, scaled and centred as [GameplayHud] draws,
## nearest filtered.
##
## The mask is the 640x480 canvas less the page's [method GameOverPage.view_rect], drawn as up to
## four rectangles behind the sprite. The sprite shows once the page's predelay is over
## ([method GameOverPage.overlay_visible]) at its retail size, modulated by
## [method PauseView.glow_modulate] of [member GameOverPage.sprite_grey], where 0x80 would be the
## image's own colours. After the page ends in a direct launch, [method finish] keeps the last mask
## and drops the sprite, as retail's shutdown hides the sprite and leaves the viewport. The view
## reads no input.

## The 640x480 canvas the page is laid out on.
const CANVAS: Vector2i = Vector2i(640, 480)
## The display clear colour around the game viewport.
const MASK_COLOUR: Color = Color.BLACK

var _assets: FrontEndAssets = null
var _page: GameOverPage = null
var _rect: Rect2i = Rect2i(Vector2i.ZERO, CANVAS)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false


## The parts of the 640x480 canvas outside [param view]: none for the whole canvas, the whole
## canvas for an empty view, else the bands above and below it and the sides beside it.
static func mask_rects(view: Rect2i) -> Array[Rect2i]:
	var canvas := Rect2i(Vector2i.ZERO, CANVAS)
	var result: Array[Rect2i] = []
	var inside: Rect2i = view.intersection(canvas) if view.has_area() else Rect2i()
	if not inside.has_area():
		result.append(canvas)
		return result
	var bands: Array[Rect2i] = [
		Rect2i(0, 0, CANVAS.x, inside.position.y),
		Rect2i(0, inside.end.y, CANVAS.x, CANVAS.y - inside.end.y),
		Rect2i(0, inside.position.y, inside.position.x, inside.size.y),
		Rect2i(inside.end.x, inside.position.y, CANVAS.x - inside.end.x, inside.size.y),
	]
	for band: Rect2i in bands:
		if band.has_area():
			result.append(band)
	return result


## The top-left corner of a sprite of [param sprite_size] centred on the canvas as the startup
## places it: [code]((640 - w) >> 1, (480 - h) >> 1)[/code].
static func sprite_position(sprite_size: Vector2) -> Vector2:
	return Vector2((CANVAS.x - int(sprite_size.x)) >> 1, (CANVAS.y - int(sprite_size.y)) >> 1)


## Uses [param assets] for the opt_gameover image; null draws the mask alone.
func configure(assets: FrontEndAssets) -> void:
	_assets = assets
	queue_redraw()


## Shows [param page] from its startup.
func open(page: GameOverPage) -> void:
	present(page)
	show()


## Draws [param page] as it is now.
func present(page: GameOverPage) -> void:
	_page = page
	_rect = page.view_rect()
	queue_redraw()


## Drops the sprite and keeps the last mask, as the page's end leaves a direct launch.
func finish() -> void:
	_page = null
	queue_redraw()


## Hides the view and forgets the page and its mask.
func close() -> void:
	_page = null
	_rect = Rect2i(Vector2i.ZERO, CANVAS)
	hide()
	queue_redraw()


## The game viewport the mask leaves open on the canvas.
func view_rect() -> Rect2i:
	return _rect


## Whether the sprite is drawn now.
func shows_sprite() -> bool:
	return _page != null and _page.overlay_visible()


func _draw() -> void:
	var factor: float = minf(size.x / CANVAS.x, size.y / CANVAS.y)
	if factor <= 0.0:
		return
	draw_set_transform((size - Vector2(CANVAS) * factor) * 0.5, 0.0, Vector2.ONE * factor)
	for band: Rect2i in mask_rects(_rect):
		draw_rect(Rect2(band), MASK_COLOUR)
	if shows_sprite() and _assets != null:
		var texture: Texture2D = _assets.texture(GameOverPage.IMAGE)
		if texture != null:
			var sprite_size: Vector2 = _assets.retail_size(GameOverPage.IMAGE)
			draw_texture_rect(texture, Rect2(sprite_position(sprite_size), sprite_size), false,
				PauseView.glow_modulate(_page.sprite_grey))
	draw_set_transform(Vector2.ZERO)
