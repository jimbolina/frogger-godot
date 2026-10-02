class_name PathInspection
extends Node3D
## Optional map overlay for one detached path definition and runner snapshot.

var _curve: MeshInstance3D
var _marker: MeshInstance3D
var _tangent: MeshInstance3D
var _definition: PathDefinition

func _ready() -> void:
	_curve = MeshInstance3D.new()
	add_child(_curve)
	_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	_marker.mesh = sphere
	_marker.material_override = _material(Color(1.0, 0.2, 0.12))
	add_child(_marker)
	_tangent = MeshInstance3D.new()
	add_child(_tangent)
	visible = false

## Rebuilds a visual sample of a validated path without changing gameplay state.
func configure(definition: PathDefinition) -> void:
	_definition = definition.copy() if definition != null else null
	_curve.mesh = null
	_tangent.mesh = null
	_marker.visible = false
	if _definition == null:
		return
	var mesh := ImmediateMesh.new()
	var material: StandardMaterial3D = _material(Color(0.12, 0.9, 1.0))
	for segment: PathSegmentDefinition in _definition.segments:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for sample_index: int in 17:
			var distance: int = roundi(float(segment.length) * float(sample_index) / 16.0)
			var sample: PathSample = PathEvaluator.sample(segment, distance)
			if sample.error.is_empty():
				mesh.surface_add_vertex(GameSpace.position(sample.position.x, sample.position.y, sample.position.z))
		mesh.surface_end()
	_curve.mesh = mesh

## Moves the marker and tangent using a copied runner observation.
func set_snapshot(snapshot: PathSnapshot) -> void:
	_marker.visible = snapshot != null
	_tangent.mesh = null
	if snapshot == null:
		return
	var position: Vector3 = GameSpace.position(snapshot.position.x, snapshot.position.y, snapshot.position.z)
	_marker.position = position
	var direction: Vector3 = GameSpace.normal(snapshot.tangent.x, snapshot.tangent.y, snapshot.tangent.z)
	if direction.is_zero_approx():
		return
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color(1.0, 0.75, 0.1)))
	line.surface_add_vertex(position)
	line.surface_add_vertex(position + direction.normalized() * 0.45)
	line.surface_end()
	_tangent.mesh = line

static func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color
	result.no_depth_test = true
	return result
