class_name ScorePopupView
extends Control
## Draws rising score sprites on the HUD's 640x480 canvas.
##
## AddFrogScore (score.C:281-460) creates a sprite for every Score_library
## entry with an image, centred on the screen point of the owner's origin at
## the award. [ScorePopupState] moves and fades it; the sprite multiplies its
## image by grey / 0x80. The image's own translucency flag and page rate pick
## the blend.

## One prepared score image.
class ScoreImage extends RefCounted:
	var texture: Texture2D
	var region := Rect2()
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE

## One blend's canvas item and the sprites it draws.
class Layer extends Control:
	var entries: Array[ScorePopupState] = []
	var images: Dictionary[int, ScoreImage] = {}
	var alpha: float = 1.0
	var level: float = 1.0

	func _draw() -> void:
		for popup: ScorePopupState in entries:
			var image: ScoreImage = images.get(popup.slot)
			if image == null:
				continue
			var at: Vector2i = popup.screen() - Vector2i(int(image.region.size.x) >> 1, int(image.region.size.y) >> 1)
			var grey: float = float(popup.grey) / ScorePopupState.BASE_GREY * level
			draw_texture_rect_region(image.texture, Rect2(Vector2(at), image.region.size), image.region, Color(grey, grey, grey, alpha))

var _images: Dictionary[int, ScoreImage] = {}
var _popups: Array[ScorePopupState] = []
var _layers: Dictionary[int, Layer] = {}


## Prepares the score images of [param effects] by Score_library slot.
func configure(effects: EffectResources) -> String:
	clear()
	_images.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if effects == null:
		return "Score sprites require the level's effect resources"
	var problems := PackedStringArray()
	for slot: int in mini(effects.score_texture_ids.size(), EffectResources.SCORE_SYMBOLS.size()):
		var symbol: String = EffectResources.SCORE_SYMBOLS[slot]
		if symbol.is_empty() or effects.score_texture_ids[slot] < 0:
			continue
		var image: VloImage = effects.images.get(symbol)
		if image == null:
			problems.append("Score image %s is unavailable" % symbol)
			continue
		add_image(slot, image.texture, Rect2(TextureBuilder.pixel_rect(image)), EffectSpriteMaterial.image_blend(image))
	return "; ".join(problems)


## Prepares one score image directly.
func add_image(slot: int, texture: Texture2D, region: Rect2, blend: ModelShaders.Blend) -> void:
	var image := ScoreImage.new()
	image.texture = texture
	image.region = region
	image.blend = blend
	_images[slot] = image
	for layer_blend: int in _layers:
		_layers[layer_blend].images = _images


## True when Score_library [param slot] has an image, so AddFrogScore would make a sprite.
func has_image(slot: int) -> bool:
	return _images.has(slot)


## Removes every sprite.
func clear() -> void:
	_popups.clear()
	_refresh()


## Releases images and sprites.
func release() -> void:
	_images.clear()
	clear()


## Creates a sprite for [param slot] centred on canvas point [param at]; false without an image.
func spawn(slot: int, at: Vector2i) -> bool:
	if not _images.has(slot):
		return false
	_popups.append(ScorePopupState.new(slot, at))
	return true


## Runs one UpdateScoreSprites step over every sprite.
func step() -> void:
	var kept: Array[ScorePopupState] = []
	for popup: ScorePopupState in _popups:
		popup.update()
		if not popup.killed:
			kept.append(popup)
	_popups = kept
	_refresh()


## The live sprites, oldest first.
func popups() -> Array[ScorePopupState]:
	return _popups


func _refresh() -> void:
	for blend: int in _layers:
		_layers[blend].entries.clear()
	for popup: ScorePopupState in _popups:
		var blend: int = _images[popup.slot].blend
		_layer(blend).entries.append(popup)
	for blend: int in _layers:
		_layers[blend].queue_redraw()


func _layer(blend: int) -> Layer:
	if _layers.has(blend):
		return _layers[blend]
	var layer := Layer.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.images = _images
	var ink := CanvasItemMaterial.new()
	match blend:
		ModelShaders.Blend.AVERAGE:
			layer.alpha = 0.5
		ModelShaders.Blend.ADD:
			ink.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ModelShaders.Blend.ADD_QUARTER:
			ink.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			layer.level = 0.25
		ModelShaders.Blend.SUBTRACT:
			ink.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	layer.material = ink
	add_child(layer)
	_layers[blend] = layer
	return layer
