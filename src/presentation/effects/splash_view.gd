class_name SplashView
extends MeshInstance3D
## Draws water splash sprites: ripple images in the XZ plane at their origins.
##
## A splash is a 3D sprite created with MR_SPF_IN_XZ_PLANE and OT offset
## -0x10 (COLLIDE.C, scripter.c) whose [SplashTimeline] supplies image, scale
## and colour. Corners are the image size times the scale, halved
## (MR_SPRT.C:704-737); the base colour is lit by the map's ambient and
## parallel lights on the upward quad normal, as a lit 3D sprite is
## (MR_SPRT.C:916-932). Translucency follows the image's own flag.

## Game units splashes move toward the camera: sc_ot_offset -0x10.
const DEPTH_BIAS: float = 32.0

## One active splash: its timeline and fixed origin.
class Splash extends RefCounted:
	var timeline: SplashTimeline
	var origin := Vector3i.ZERO

	func _init(at: Vector3i = Vector3i.ZERO, list: Array[SplashTimeline.Command] = []) -> void:
		origin = at
		timeline = SplashTimeline.new(list)

var _splashes := ImmediateMesh.new()
var _sprites: Dictionary[String, EffectSpriteMaterial.Sprite] = {}
var _lighting: MapLighting = null
var _projection_scale := Vector2.ONE


## Prepares the ripple images and map lights of [param scene].
func configure(scene: MapSceneData) -> String:
	clear()
	if scene == null or scene.effects == null:
		return "Splashes require the level's effect resources"
	var problems := PackedStringArray()
	for symbol: String in EffectResources.RIPPLE_SYMBOLS:
		var image: VloImage = scene.effects.images.get(symbol)
		if image == null:
			problems.append("Splash image %s is unavailable" % symbol)
			continue
		var material: ShaderMaterial = EffectSpriteMaterial.textured(scene.library, image, EffectSpriteMaterial.image_blend(image), DEPTH_BIAS, _projection_scale)
		_sprites[symbol] = EffectSpriteMaterial.Sprite.new(material, image)
	if scene.map != null:
		_lighting = MapLighting.new()
		_lighting.configure(scene.map.lights)
	return "; ".join(problems)


## Supplies the lights that shade splash colours; null leaves colours unlit.
func set_lighting(lighting: MapLighting) -> void:
	_lighting = lighting


## Prepares one image directly, for scenes assembled without effect resources.
func add_image(symbol: String, sprite: EffectSpriteMaterial.Sprite) -> void:
	_sprites[symbol] = sprite


## Releases prepared materials.
func clear() -> void:
	_sprites.clear()
	_lighting = null
	_splashes.clear_surfaces()
	visible = false


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for symbol: String in _sprites:
		_sprites[symbol].material.set_shader_parameter("projection_scale", scale)


## Draws [param splashes]; returns the number of quads.
func draw_splashes(splashes: Array[Splash]) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	for splash: Splash in splashes:
		if not splash.timeline.drawn():
			continue
		var sprite: EffectSpriteMaterial.Sprite = _sprites.get(splash.timeline.image)
		if sprite == null:
			continue
		var half: Vector2i = half_extents(sprite.width, sprite.height, splash.timeline.scale)
		var at: Vector3i = splash.origin
		var corners: Array[Vector3] = [
			GameSpace.position(at.x - half.x, at.y, at.z + half.y), GameSpace.position(at.x + half.x, at.y, at.z + half.y),
			GameSpace.position(at.x - half.x, at.y, at.z - half.y), GameSpace.position(at.x + half.x, at.y, at.z - half.y)]
		var base: Color = EffectSpriteMaterial.colour(splash.timeline.rgb())
		var lit: Color = _lighting.shade(base, Vector3.UP) if _lighting != null else base
		EffectSpriteMaterial.batch_for(batches, sprite.material).quad(corners, [lit, lit, lit, lit])
		drawn += 1
	visible = EffectSpriteMaterial.commit(_splashes, batches)
	mesh = _splashes
	return drawn


## Source 3D sprite half extents of a [param width] by [param height] image at 16.16 [param scale].
static func half_extents(width: int, height: int, scale: int) -> Vector2i:
	return Vector2i((((width * scale) >> 16) & 0xffff) >> 1, (((height * scale) >> 16) & 0xffff) >> 1)
