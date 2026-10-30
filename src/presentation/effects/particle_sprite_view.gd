class_name ParticleSpriteView
extends MeshInstance3D
## Draws the live particles of [ParticleField]s as screen-aligned textured quads.
##
## Each particle follows its generator's display (PARTICLE.C:
## FrogEffectSlippingDisp and FrogEffectFireDisp, 1501-1578, 1971-2050;
## Hilite_exhaust_disp, Hilite_dust_disp and Hilite_fire_disp, 1276-1384,
## 2154-2253, 2513-2593): the ordering entry is the particle's depth >> 1
## plus the field's ordering offset, drawn only inside the table (the hilite
## fire holds it at 1 or more); the half extents are (size numerator / entry)
## >> 8 pixels, culled from 0x60; the polygon is FT4, semi-transparent at the
## image page's rate, and the PC dust display sets ABR 1 on its images. Pixel
## extents become camera-plane offsets with the 640x480 focal distances the
## pickup sprites use, and the quad sorts by the field's ordering offset:
## 0x10 slots (32 units) nearer for the frog kinds, the dust and the hilite
## fire, 0x10 slots further for the exhaust. A dust particle shows the image
## of the record's texture list its [method ParticleField.image_index] names.

## Game units frog particles move toward the camera: FROG_EFFECT_SLIP_OT_OFFSET.
const DEPTH_BIAS: float = 32.0
## Source ordering table size.
const OT_SIZE: int = 4096
## Source ABR bit Hilite_dust_disp sets on the PC.
const DUST_BLEND_BIT: int = 1

var _particles := ImmediateMesh.new()
var _images: Dictionary[String, Array] = {}
var _sprites: Dictionary[String, EffectSpriteMaterial.Sprite] = {}
var _library: TextureLibrary = null
var _projection_scale := Vector2.ONE


## Prepares the images every generator in [param generator_names] draws from
## [param scene]'s effect resources: the record's texture or texture list, or
## the image [constant EffectResources.GENERATOR_IMAGES] names; generators
## without an image stay off.
func configure(scene: MapSceneData, generator_names: PackedStringArray) -> String:
	clear()
	if scene == null or scene.effects == null:
		return "Particles require the level's effect resources"
	_library = scene.library
	var problems := PackedStringArray()
	for generator_name: String in generator_names:
		var images: Array[VloImage] = generator_images(scene.effects, generator_name)
		if images.is_empty():
			problems.append("Particle image for %s is unavailable" % generator_name)
			continue
		_images[generator_name] = images
	return "; ".join(problems)


## True when generator [param generator_name] has a prepared image.
func has_generator(generator_name: String) -> bool:
	return _images.has(generator_name)


## Releases prepared materials.
func clear() -> void:
	_images.clear()
	_sprites.clear()
	_library = null
	_particles.clear_surfaces()
	visible = false


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for key: String in _sprites:
		_sprites[key].material.set_shader_parameter("projection_scale", scale)


## Draws every live particle of [param fields] at render [param fraction]
## from [param camera]; returns the number of quads.
func draw_fields(fields: Array[ParticleField], camera: GameplayCameraSnapshot, fraction: float) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	if camera != null:
		for field: ParticleField in fields:
			if not _images.has(field.generator_name):
				continue
			for index: int in field.live_indices():
				var sprite: EffectSpriteMaterial.Sprite = _sprite(field, field.image_index(index))
				if sprite == null:
					continue
				var centre: Vector3 = field.position(index, fraction)
				var half: Vector2 = half_extents(field.extent(index, sprite.width), field.extent(index, sprite.height), EffectSpriteMaterial.view_depth(camera, centre), field.ot_offset(), field.clamps_near())
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


## The images generator [param generator_name] draws in list order: each
## texture id of its record resolved through a symbol of [param effects]
## with that id, or the single image [constant EffectResources.GENERATOR_IMAGES]
## names; empty when any is unavailable.
static func generator_images(effects: EffectResources, generator_name: String) -> Array[VloImage]:
	var result: Array[VloImage] = []
	for texture_id: int in effects.generator_texture_ids(generator_name):
		var image: VloImage = null
		for symbol: String in effects.images:
			if effects.texture_ids.get(symbol, -1) == texture_id:
				image = effects.images[symbol]
				break
		if image == null:
			result.clear()
			break
		result.append(image)
	if result.is_empty():
		var named: VloImage = effects.images.get(EffectResources.GENERATOR_IMAGES.get(generator_name, ""))
		if named != null:
			result.append(named)
	return result


## Game units of depth bias for an ordering offset of [param slots].
static func depth_bias_for(slots: int) -> float:
	return EffectSpriteMaterial.slots_bias(slots)


## World half extents for source size numerators [param numerator_x] and
## [param numerator_y] at view depth [param depth] with ordering offset
## [param ot_offset], or (-1, -1) when the source would not draw the
## particle; [param clamp_near] holds the entry at 1 or more.
static func half_extents(numerator_x: int, numerator_y: int, depth: float, ot_offset: int = ParticleField.OT_OFFSET, clamp_near: bool = false) -> Vector2:
	var entry: int = (int(depth) >> 1) + ot_offset
	if clamp_near:
		entry = maxi(1, entry)
	if entry <= 0 or entry >= OT_SIZE:
		return Vector2(-1.0, -1.0)
	var pixels_x: int = PlatformMath.divide(numerator_x, entry) >> 8
	if pixels_x >= ParticleField.MAX_HALF_WIDTH:
		return Vector2(-1.0, -1.0)
	var pixels_y: int = PlatformMath.divide(numerator_y, entry) >> 8
	return Vector2(pixels_x * depth / EffectSpriteMaterial.FOCAL_X, pixels_y * depth / EffectSpriteMaterial.FOCAL_Y)


func _sprite(field: ParticleField, image_index: int) -> EffectSpriteMaterial.Sprite:
	var images: Array = _images[field.generator_name]
	var image: VloImage = images[clampi(image_index, 0, images.size() - 1)]
	var key: String = "%s:%d:%d" % [field.generator_name, image_index, field.ot_offset()]
	if not _sprites.has(key):
		var mode: int = image.blend_mode() | DUST_BLEND_BIT if field.generator_name == EffectResources.DUST_GENERATOR else image.blend_mode()
		var material: ShaderMaterial = EffectSpriteMaterial.textured(_library, image, ModelShaders.blend_for_mode(mode), depth_bias_for(field.ot_offset()), _projection_scale)
		_sprites[key] = EffectSpriteMaterial.Sprite.new(material, image)
	return _sprites[key]
