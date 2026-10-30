class_name PopRingView
extends MeshInstance3D
## Draws the frog's death pop rings around the projected frog origin.
##
## Each ring is eight Gouraud quads between the outer and inner octagons of
## [PopRingGeometry]. The source projects the octagon at SYSTEM_PERSPECTIVE
## depth around the origin's screen point, so an offset of n units is n / 192
## of the origin's view depth on the camera plane. The ring uses ABR 1
## (additive on PC) at the fixed ordering slot FROG_POPPING_FIXED_OT, so it
## draws over the scene without a depth test.

var _rings := ImmediateMesh.new()
var _material: ShaderMaterial = EffectSpriteMaterial.in_front(ModelShaders.Blend.ADD, Vector2.ONE)


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_material.set_shader_parameter("projection_scale", scale)


## The ring material.
func ring_material() -> ShaderMaterial:
	return _material


## Hides every ring.
func clear() -> void:
	_rings.clear_surfaces()
	visible = false


## Draws [param rings] around game point [param origin] from [param camera]
## at [param game_timer]; returns the number of rings drawn.
func draw_rings(rings: Array[PopRingGeometry], origin: Vector3, camera: GameplayCameraSnapshot, game_timer: int) -> int:
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var drawn: int = 0
	var depth: float = EffectSpriteMaterial.view_depth(camera, origin) if camera != null else 0.0
	if depth > 0.0:
		var factor: float = depth / PopRingGeometry.SYSTEM_PERSPECTIVE
		var batch: EffectSpriteMaterial.Batch = EffectSpriteMaterial.batch_for(batches, _material)
		for ring: PopRingGeometry in rings:
			if not ring.drawn():
				continue
			var shape: PopRingGeometry.Frame = ring.frame(game_timer)
			var outer: Color = EffectSpriteMaterial.colour(shape.outer_rgb)
			var inner: Color = EffectSpriteMaterial.colour(shape.inner_rgb)
			var colours: Array[Color] = [outer, outer, inner, inner]
			for point: int in PopRingGeometry.POINTS:
				var following: int = (point + 1) % PopRingGeometry.POINTS
				var corners: Array[Vector3] = [
					_corner(origin, camera, shape.outer[point], factor), _corner(origin, camera, shape.outer[following], factor),
					_corner(origin, camera, shape.inner[point], factor), _corner(origin, camera, shape.inner[following], factor)]
				batch.quad(corners, colours)
			drawn += 1
	visible = EffectSpriteMaterial.commit(_rings, batches)
	mesh = _rings
	return drawn


static func _corner(origin: Vector3, camera: GameplayCameraSnapshot, offset: Vector2i, factor: float) -> Vector3:
	return EffectSpriteMaterial.world(origin + EffectSpriteMaterial.screen_offset(camera, offset.x * factor, offset.y * factor))
