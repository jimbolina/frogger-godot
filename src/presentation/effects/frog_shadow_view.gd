class_name FrogShadowView
extends MeshInstance3D
## Draws ground shadows as textured quads that follow the level grid's heights.
##
## Each request names its corner offsets, image symbol and owner frame; the
## corners, grid-line split and texture split come from
## [FrogShadowGeometry], the heights from the level grid. Shadows are FT4 at
## grey 0x30, always semi-transparent at the image page's rate, and sort four
## ordering slots nearer than their averaged depth (RenderEffects,
## EFFECTS.C:877-930). A request whose heights cannot be found is not drawn.

## Game units the shadow moves toward the camera: SHADOW_OT_OFFSET (-4 slots).
const DEPTH_BIAS: float = 8.0

## One shadow to draw.
class Request extends RefCounted:
	## Owner frame whose rotation picks the quadrant.
	var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
	## Owner translation in game units.
	var translation := Vector3i.ZERO
	var offsets: Array[Vector3i] = []
	var symbol: String = ""
	var no_rotation: bool = false

var _sprites: Dictionary[String, EffectSpriteMaterial.Sprite] = {}
var _grid: GridDefinition = null
var _shadows := ImmediateMesh.new()
var _projection_scale := Vector2.ONE


## Prepares the shadow images [param symbols] from [param scene]'s effect
## resources against [param grid]; symbols without an image stay off.
func configure(scene: MapSceneData, grid: GridDefinition, symbols: PackedStringArray) -> String:
	clear()
	_grid = grid
	if scene == null or scene.effects == null:
		return "Shadows require the level's effect resources"
	var problems := PackedStringArray()
	for symbol: String in symbols:
		var image: VloImage = scene.effects.images.get(symbol)
		if image == null:
			problems.append("Shadow image %s is unavailable" % symbol)
			continue
		var material: ShaderMaterial = EffectSpriteMaterial.textured(scene.library, image, EffectSpriteMaterial.semi_transparent_blend(image), DEPTH_BIAS, _projection_scale)
		_sprites[symbol] = EffectSpriteMaterial.Sprite.new(material, image)
	return "; ".join(problems)


## Replaces the grid that supplies heights.
func set_grid(grid: GridDefinition) -> void:
	_grid = grid


## Releases prepared materials.
func clear() -> void:
	_sprites.clear()
	_shadows.clear_surfaces()
	visible = false


## True when [param symbol] has a prepared image.
func has_symbol(symbol: String) -> bool:
	return _sprites.has(symbol)


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for symbol: String in _sprites:
		_sprites[symbol].material.set_shader_parameter("projection_scale", scale)


## Draws [param requests]; returns how many shadows were drawn.
func draw_shadows(requests: Array[Request]) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	var grey: Color = EffectSpriteMaterial.colour(Vector3i.ONE * FrogShadowGeometry.GREY)
	var colours: Array[Color] = [grey, grey, grey, grey]
	for request: Request in requests:
		var sprite: EffectSpriteMaterial.Sprite = _sprites.get(request.symbol)
		if sprite == null or request.offsets.size() != 4 or _grid == null:
			continue
		var uv := FrogShadowGeometry.TextureUv.spanning(sprite.width, sprite.height)
		var shape: FrogShadowGeometry.Layout = FrogShadowGeometry.layout(request.offsets, request.translation, request.matrix12, request.no_rotation, _grid.base, uv)
		var heights: PackedInt32Array = FrogShadowGeometry.heights(shape, _grid)
		if heights.is_empty():
			continue
		var batch: EffectSpriteMaterial.Batch = EffectSpriteMaterial.batch_for(batches, sprite.material)
		var at: int = 0
		for poly_index: int in shape.polys.size():
			var corners: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner: int in 4:
				var point: FrogShadowGeometry.Point = shape.polys[poly_index][corner]
				corners.append(GameSpace.position(point.x, heights[at], point.z))
				var texel: Vector2i = shape.uvs[poly_index][corner]
				uvs.append(Vector2(float(texel.x) / maxf(1.0, sprite.width), float(texel.y) / maxf(1.0, sprite.height)))
				at += 1
			batch.quad(corners, colours, uvs)
		drawn += 1
	visible = EffectSpriteMaterial.commit(_shadows, batches)
	mesh = _shadows
	return drawn
