class_name EntityInspection
extends Node3D
## Optional source-space position and orientation markers for attached entities.

var _axes: Array[MeshInstance3D] = []
var _positions: Array[MeshInstance3D] = []
var _selected: int = -1

## Allocates one marker per definition; flags remain visible as metadata.
func configure(definitions: Array[EntityDefinition]) -> void:
	for marker: MeshInstance3D in _axes:
		remove_child(marker)
		marker.queue_free()
	for marker: MeshInstance3D in _positions:
		remove_child(marker)
		marker.queue_free()
	_axes.clear()
	_positions.clear()
	_selected = -1
	for _definition: EntityDefinition in definitions:
		var axes := MeshInstance3D.new()
		axes.mesh = _axes_mesh()
		add_child(axes)
		_axes.append(axes)
		var position := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.18
		position.mesh = sphere
		add_child(position)
		_positions.append(position)
	set_selected(0 if not definitions.is_empty() else -1)
	visible = false

## Places all markers from an independently owned run snapshot.
func set_snapshot(snapshot: EntityRunSnapshot) -> void:
	if snapshot == null:
		return
	for index: int in mini(_axes.size(), snapshot.entities.size()):
		var matrix: PackedInt32Array = snapshot.entities[index].matrix12
		var origin: Vector3 = GameSpace.position(matrix[9], matrix[10], matrix[11])
		var x_axis: Vector3 = GameSpace.normal(matrix[0], matrix[3], matrix[6]).normalized()
		var y_axis: Vector3 = GameSpace.normal(matrix[1], matrix[4], matrix[7]).normalized()
		var z_axis: Vector3 = GameSpace.normal(matrix[2], matrix[5], matrix[8]).normalized()
		_positions[index].position = origin
		if x_axis.is_zero_approx() or y_axis.is_zero_approx() or z_axis.is_zero_approx():
			_axes[index].visible = false
		else:
			_axes[index].visible = true
			_axes[index].transform = Transform3D(Basis(x_axis, y_axis, z_axis), origin)

## Highlights one source-ordered definition slot while retaining all markers.
func set_selected(index: int) -> void:
	_selected = index
	for marker_index: int in _positions.size():
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(1.0, 0.95, 0.2) if marker_index == _selected else Color(1.0, 0.3, 0.15)
		_positions[marker_index].material_override = material
		_positions[marker_index].scale = Vector3.ONE * (1.6 if marker_index == _selected else 1.0)

## Marker count exposes lifecycle state to inspection tests.
func marker_count() -> int:
	return _positions.size()

static func _axes_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var colors: Array[Color] = [Color(1.0, 0.25, 0.2), Color(0.2, 1.0, 0.3), Color(0.2, 0.65, 1.0)]
	for index: int in 3:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colors[index]
		material.no_depth_test = true
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		mesh.surface_add_vertex(Vector3.ZERO)
		var axis: Vector3 = Vector3.RIGHT if index == 0 else (Vector3.UP if index == 1 else Vector3.BACK)
		mesh.surface_add_vertex(axis * 0.45)
		mesh.surface_end()
	return mesh
