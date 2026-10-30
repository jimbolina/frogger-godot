class_name HopTrailView
extends MeshInstance3D
## Draws the frog's movement trail from a committed [HopTrailState].
##
## Each section between a newer and an older vertex pair is two Gouraud
## triangles, the newer edge at the section colour and the older edge 0x101010
## darker (RenderEffects, EFFECTS.C:956-1060). The source draws them
## semi-transparent with a dummy ABR 1 polygon, which is additive on PC, in the
## global ordering table at each section's own depth, so no depth bias applies.
## The geometry is world space; the trail gains one pair per tick and is not
## interpolated.

## Trail sections sort at their own depth.
const DEPTH_BIAS: float = 0.0

var _trail := ImmediateMesh.new()
var _material: ShaderMaterial = EffectSpriteMaterial.untextured(ModelShaders.Blend.ADD, DEPTH_BIAS, Vector2.ONE)


## Applies the shared projection correction.
func set_projection_scale(scale: Vector2) -> void:
	_material.set_shader_parameter("projection_scale", scale)


## The trail material.
func trail_material() -> ShaderMaterial:
	return _material


## Hides the trail.
func clear() -> void:
	_trail.clear_surfaces()
	visible = false


## Rebuilds the triangles of [param trail]; returns the number of sections drawn.
func draw_trail(trail: HopTrailState) -> int:
	_trail.clear_surfaces()
	mesh = _trail
	var pairs: Array[Array] = []
	if trail != null:
		pairs = trail.pairs()
	if pairs.size() < 2:
		visible = false
		return 0
	var colours: PackedInt32Array = trail.section_colours()
	var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
	var batch: EffectSpriteMaterial.Batch = EffectSpriteMaterial.batch_for(batches, _material)
	for section: int in pairs.size() - 1:
		var newer: Array = pairs[section]
		var older: Array = pairs[section + 1]
		var n0: Vector3i = newer[0]
		var n1: Vector3i = newer[1]
		var o0: Vector3i = older[0]
		var o1: Vector3i = older[1]
		var a0: Vector3 = _point(n0)
		var a1: Vector3 = _point(n1)
		var b0: Vector3 = _point(o0)
		var b1: Vector3 = _point(o1)
		var top: Color = EffectSpriteMaterial.colour(HopTrailState.bytes(colours[section]))
		var bottom: Color = EffectSpriteMaterial.colour(HopTrailState.bytes(colours[section + 1]))
		batch.triangle([a0, a1, b0], [top, top, bottom])
		batch.triangle([b0, a1, b1], [bottom, top, bottom])
	visible = EffectSpriteMaterial.commit(_trail, batches)
	return pairs.size() - 1


static func _point(value: Vector3i) -> Vector3:
	return GameSpace.position(value.x, value.y, value.z)
