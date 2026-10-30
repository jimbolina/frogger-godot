class_name GoldGlowView
extends MeshInstance3D
## Draws the gold-frog glow: one camera-plane quad per glowing gold frog.
##
## PGIN_gold_frog_glow (PARTICLE.C:2607-2724) is created for the general gold
## frog (ent_gen.c:1095-1099), the original theme's gold baby frog
## (ent_org.c:262-269, shown with the frog at 417 and hidden with it at 447)
## and the Jungle outro statue frog (ent_jun.c:813-820). It is killed with
## its entity or its pop; here a glow draws while its entity is shown, which
## the committed snapshot states. The display reads the frame translation,
## not the creation offset, so the quad is centred on the entity origin. Its
## ordering entry is the origin's depth >> 1 minus 0x30, drawn only inside
## the table and while the screen Y is within 0x300; the half size follows
## [GlowPulse] at that entry. The quad is FT4 in colour (255, 255, 16) with
## the PC glow image 1727, semi-transparent at the image page's rate, and
## sorts 0x30 slots (96 units) nearer.

## Source ordering offset of the glow.
const OT_OFFSET: int = -0x30
## Game units the glow moves toward the camera.
const DEPTH_BIAS: float = 96.0
## Retail PC glow colour.
const COLOUR := Vector3i(255, 255, 16)
## Largest drawn screen Y magnitude.
const MAX_SCREEN_Y: int = 0x300
## ORG_GOLD_BABY_FROG_FORM_ID (ent_org.h).
const ORG_GOLD_BABY_FROG_FORM: int = 24

## One glow: its owner's generation, pulse moves and drawn origins.
class Glow extends RefCounted:
	var generation: int = 0
	var moves: int = 0
	var shown: bool = false
	var before := Vector3.ZERO
	var at := Vector3.ZERO

	## The pulse angle after this glow's moves.
	func angle() -> int:
		return GlowPulse.angle_after(moves)

var _glows: Dictionary[int, Glow] = {}
var _sprite: EffectSpriteMaterial.Sprite = null
var _mesh := ImmediateMesh.new()
var _projection_scale := Vector2.ONE


## Prepares the PC glow image from [param scene]'s effect resources.
func configure(scene: MapSceneData) -> String:
	clear()
	if scene == null or scene.effects == null:
		return "The gold-frog glow requires the level's effect resources"
	var image: VloImage = scene.effects.images.get(EffectResources.GLOW_SYMBOL)
	if image == null:
		return "Gold-frog glow image %s is unavailable" % EffectResources.GLOW_SYMBOL
	var material: ShaderMaterial = EffectSpriteMaterial.textured(scene.library, image, EffectSpriteMaterial.semi_transparent_blend(image), DEPTH_BIAS, _projection_scale)
	_sprite = EffectSpriteMaterial.Sprite.new(material, image)
	return ""


## Prepares the glow image directly, for scenes assembled without effect resources.
func set_image(sprite: EffectSpriteMaterial.Sprite) -> void:
	_sprite = sprite


## Forgets every glow and the prepared image.
func clear() -> void:
	_sprite = null
	collapse()


## Forgets every glow.
func collapse() -> void:
	_glows.clear()
	_mesh.clear_surfaces()
	visible = false


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	if _sprite != null:
		_sprite.material.set_shader_parameter("projection_scale", scale)


## Whether [param definition] creates a gold-frog glow.
static func owns_glow(definition: EntityDefinition) -> bool:
	if definition == null or definition.behavior == null:
		return false
	match definition.behavior.kind:
		EntityBehavior.Kind.GOLD_FROG:
			return true
		EntityBehavior.Kind.BABY_FROG:
			return definition.form_id == ORG_GOLD_BABY_FROG_FORM
		EntityBehavior.Kind.JUN_GOLD_FROG:
			return definition.jungle != null and definition.jungle.op_id == EntityJungleDefinition.GOLD_FROG_STATUE_ID
	return false


## Steps every glow for one committed tick of [param entities], slot by slot against [param definitions].
func accept(definitions: Array[EntityDefinition], entities: Array[EntitySnapshot]) -> void:
	var kept: Dictionary[int, Glow] = {}
	for slot: int in mini(definitions.size(), entities.size()):
		var entity: EntitySnapshot = entities[slot]
		if not owns_glow(definitions[slot]) or not entity.live:
			continue
		var at := Vector3(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		var glow: Glow = _glows.get(slot)
		if glow == null or glow.generation != entity.generation:
			glow = Glow.new()
			glow.generation = entity.generation
			glow.at = at
		glow.moves += 1
		glow.before = glow.at
		glow.at = at
		glow.shown = CaveSpriteView.shown(entity)
		kept[slot] = glow
	_glows = kept


## Live glows by entity slot.
func glows() -> Dictionary[int, Glow]:
	return _glows


## Draws every shown glow from [param camera] at render [param fraction]; returns the number of quads.
func draw_glows(camera: GameplayCameraSnapshot, fraction: float) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	if camera != null and _sprite != null:
		var tint: Color = EffectSpriteMaterial.colour(COLOUR)
		for slot: int in _glows:
			var glow: Glow = _glows[slot]
			if not glow.shown:
				continue
			var centre: Vector3 = glow.before.lerp(glow.at, clampf(fraction, 0.0, 1.0))
			var half: Vector2 = half_extents(camera, centre, _sprite.width, _sprite.height, glow.angle())
			if half.x < 0.0:
				continue
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				corners.append(EffectSpriteMaterial.world(centre + EffectSpriteMaterial.screen_offset(camera, corner.x * half.x, corner.y * half.y)))
			EffectSpriteMaterial.batch_for(batches, _sprite.material).quad(corners, [tint, tint, tint, tint])
			drawn += 1
	visible = EffectSpriteMaterial.commit(_mesh, batches)
	mesh = _mesh
	return drawn


## World half extents of a [param width] by [param height] glow at game point
## [param centre] and pulse [param angle] from [param camera], or (-1, -1)
## when the source would not draw it.
static func half_extents(camera: GameplayCameraSnapshot, centre: Vector3, width: int, height: int, angle: int) -> Vector2:
	var depth: float = EffectSpriteMaterial.view_depth(camera, centre)
	var otz: int = (int(depth) >> 1) + OT_OFFSET
	if otz <= 0 or otz >= ParticleSpriteView.OT_SIZE:
		return Vector2(-1.0, -1.0)
	var down: float = (centre - Vector3(camera.source_world)).dot(Vector3(camera.axis_y_12)) / 4096.0
	if absf(240.0 + EffectSpriteMaterial.FOCAL_Y * down / depth) >= MAX_SCREEN_Y:
		return Vector2(-1.0, -1.0)
	var pixels: Vector2i = GlowPulse.half_size(width, height, otz, angle)
	return Vector2(pixels.x * depth / EffectSpriteMaterial.FOCAL_X, pixels.y * depth / EffectSpriteMaterial.FOCAL_Y)
