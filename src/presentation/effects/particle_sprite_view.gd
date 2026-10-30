class_name ParticleSpriteView
extends MeshInstance3D
## Draws the live particles of [ParticleField]s as screen-aligned textured quads.
##
## Each particle follows FrogEffectSlippingDisp and FrogEffectFireDisp
## (PARTICLE.C:1501-1578, 1971-2050): the ordering entry is the particle's
## depth >> 1 plus FROG_EFFECT_SLIP_OT_OFFSET, drawn only inside the table;
## the half extents are (size numerator / entry) >> 8 pixels, culled from
## 0x60; the polygon is FT4, semi-transparent at the image page's rate. Pixel
## extents become camera-plane offsets with the 640x480 focal distances the
## pickup sprites use, and the quad sorts 0x10 slots (32 units) nearer.

## Game units particles move toward the camera: FROG_EFFECT_SLIP_OT_OFFSET.
const DEPTH_BIAS: float = 32.0
## Source ordering table size.
const OT_SIZE: int = 4096

var _particles := ImmediateMesh.new()
var _sprites: Dictionary[String, EffectSpriteMaterial.Sprite] = {}
var _projection_scale := Vector2.ONE


## Prepares the images every frog generator draws from [param scene]'s effect
## resources; generators without an image stay off.
func configure(scene: MapSceneData, generator_names: PackedStringArray) -> String:
	clear()
	if scene == null or scene.effects == null:
		return "Particles require the level's effect resources"
	var problems := PackedStringArray()
	for generator_name: String in generator_names:
		var symbol: String = EffectResources.GENERATOR_IMAGES.get(generator_name, "")
		var image: VloImage = scene.effects.images.get(symbol)
		if image == null:
			problems.append("Particle image for %s is unavailable" % generator_name)
			continue
		var material: ShaderMaterial = EffectSpriteMaterial.textured(scene.library, image, EffectSpriteMaterial.semi_transparent_blend(image), DEPTH_BIAS, _projection_scale)
		_sprites[generator_name] = EffectSpriteMaterial.Sprite.new(material, image)
	return "; ".join(problems)


## True when generator [param generator_name] has a prepared image.
func has_generator(generator_name: String) -> bool:
	return _sprites.has(generator_name)


## Releases prepared materials.
func clear() -> void:
	_sprites.clear()
	_particles.clear_surfaces()
	visible = false


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for generator_name: String in _sprites:
		_sprites[generator_name].material.set_shader_parameter("projection_scale", scale)


## Draws every live particle of [param fields] at render [param fraction]
## from [param camera]; returns the number of quads.
func draw_fields(fields: Array[ParticleField], camera: GameplayCameraSnapshot, fraction: float) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	if camera != null:
		for field: ParticleField in fields:
			var sprite: EffectSpriteMaterial.Sprite = _sprites.get(field.generator_name)
			if sprite == null:
				continue
			for index: int in field.live_indices():
				var centre: Vector3 = field.position(index, fraction)
				var half: Vector2 = half_extents(field.extent(index, sprite.width), field.extent(index, sprite.height), EffectSpriteMaterial.view_depth(camera, centre))
				if half.x < 0.0:
					continue
				var corners: Array[Vector3] = []
				for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					corners.append(EffectSpriteMaterial.world(centre + EffectSpriteMaterial.screen_offset(camera, corner.x * half.x, corner.y * half.y)))
				var tint: Color = EffectSpriteMaterial.colour(field.colour(index))
				EffectSpriteMaterial.batch_for(batches, sprite.material).quad(corners, [tint, tint, tint, tint])
				drawn += 1
	visible = EffectSpriteMaterial.commit(_particles, batches)
	mesh = _particles
	return drawn


## World half extents for source size numerators [param numerator_x] and
## [param numerator_y] at view depth [param depth], or (-1, -1) when the
## source would not draw the particle.
static func half_extents(numerator_x: int, numerator_y: int, depth: float) -> Vector2:
	var entry: int = (int(depth) >> 1) + ParticleField.OT_OFFSET
	if entry <= 0 or entry >= OT_SIZE:
		return Vector2(-1.0, -1.0)
	var pixels_x: int = PlatformMath.divide(numerator_x, entry) >> 8
	if pixels_x >= ParticleField.MAX_HALF_WIDTH:
		return Vector2(-1.0, -1.0)
	var pixels_y: int = PlatformMath.divide(numerator_y, entry) >> 8
	return Vector2(pixels_x * depth / EffectSpriteMaterial.FOCAL_X, pixels_y * depth / EffectSpriteMaterial.FOCAL_Y)
