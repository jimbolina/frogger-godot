class_name EntityInspection
extends Node3D
## Optional source-space position and orientation markers for attached entities.

var _axes: Array[MeshInstance3D] = []
var _positions: Array[MeshInstance3D] = []
var _generations: Array[int] = []
var _selected: int = -1
var _lifecycle_mode: bool = false
var _contacts: Array[FormContactDefinition] = []
var _contact_outline: MeshInstance3D
var _contact_cell: MeshInstance3D
var _contact_probe: MeshInstance3D
var _marker_materials: Array[StandardMaterial3D] = []
var _cell_key: Vector3i = Vector3i(-1, -1, -1)

## Allocates one marker per definition; flags remain visible as metadata.
func configure(definitions: Array[EntityDefinition]) -> void:
	for marker: MeshInstance3D in _axes:
		if marker != null:
			remove_child(marker)
			marker.queue_free()
	for marker: MeshInstance3D in _positions:
		if marker != null:
			remove_child(marker)
			marker.queue_free()
	_axes.clear()
	_positions.clear()
	_generations.clear()
	_selected = -1
	_lifecycle_mode = false
	_contacts.clear()
	if _contact_outline != null:
		remove_child(_contact_outline)
		_contact_outline.queue_free()
		_contact_outline = null
	if _contact_cell != null:
		remove_child(_contact_cell)
		_contact_cell.queue_free()
		_contact_cell = null
	if _contact_probe != null:
		remove_child(_contact_probe)
		_contact_probe.queue_free()
		_contact_probe = null
	for _definition: EntityDefinition in definitions:
		_axes.append(null)
		_positions.append(null)
		_generations.append(-1)
		_create_marker(_axes.size() - 1)
	set_selected(0 if not definitions.is_empty() else -1)
	visible = false

## Installs detached FORM geometry for the selected entity's query display.
func configure_contacts(definitions: Array[FormContactDefinition]) -> void:
	_cell_key = Vector3i(-1, -1, -1)
	_contacts.clear()
	for definition: FormContactDefinition in definitions:
		_contacts.append(definition.copy() if definition != null else null)
	if _contact_outline == null:
		_contact_outline = MeshInstance3D.new()
		add_child(_contact_outline)
	if _contact_cell == null:
		_contact_cell = MeshInstance3D.new()
		add_child(_contact_cell)
	if _contact_probe == null:
		_contact_probe = MeshInstance3D.new()
		add_child(_contact_probe)
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		_contact_probe.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.2, 1.0, 1.0)
		material.no_depth_test = true
		_contact_probe.material_override = material
	_rebuild_contact_outline()

## Places all markers from an independently owned run snapshot.
func set_snapshot(snapshot: EntityRunSnapshot) -> void:
	if snapshot == null:
		return
	_lifecycle_mode = snapshot.lifecycle_enabled
	for index: int in mini(_axes.size(), snapshot.entities.size()):
		if _lifecycle_mode and not snapshot.entities[index].live:
			_destroy_marker(index)
			continue
		if _lifecycle_mode and _axes[index] != null and _generations[index] != snapshot.entities[index].generation:
			_destroy_marker(index)
		if _axes[index] == null:
			_create_marker(index)
		_generations[index] = snapshot.entities[index].generation
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
	if _contact_outline != null and _selected >= 0 and _selected < snapshot.entities.size():
		var contact: FormContactDefinition = _selected_contact()
		_contact_outline.visible = (not _lifecycle_mode or snapshot.entities[_selected].live) and contact != null and contact.unsupported_reason.is_empty() and contact.dimensions.x > 0 and contact.dimensions.y > 0
		if _contact_outline.visible:
			_contact_outline.transform = GameSpace.transform(snapshot.entities[_selected].matrix12)
			_contact_cell.transform = _contact_outline.transform

## Highlights one source-ordered definition slot while retaining all markers.
func set_selected(index: int) -> void:
	if _selected == index:
		return
	var previous: int = _selected
	_selected = index
	for marker_index: int in [previous, index]:
		_style_marker(marker_index)
	_cell_key = Vector3i(-1, -1, -1)
	_rebuild_contact_outline()

func _style_marker(index: int) -> void:
	if index < 0 or index >= _positions.size() or _positions[index] == null:
		return
	if _marker_materials.is_empty():
		for color: Color in [Color(1.0, 0.3, 0.15), Color(1.0, 0.95, 0.2)]:
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.no_depth_test = true
			material.albedo_color = color
			_marker_materials.append(material)
	_positions[index].material_override = _marker_materials[1 if index == _selected else 0]
	_positions[index].scale = Vector3.ONE * (1.6 if index == _selected else 1.0)

## Places the fixed world probe and highlights the selected local FORM cell.
func set_contact(probe_world: Vector3i, result: FormContactResult) -> void:
	if _contact_probe == null:
		return
	_contact_probe.position = GameSpace.position(probe_world.x, probe_world.y, probe_world.z)
	_contact_probe.visible = true
	_contact_cell.visible = false
	var contact: FormContactDefinition = _selected_contact()
	if contact == null or result == null or result.status != FormContactResult.CONTACT or result.entity_index != contact.entity_index:
		return
	var x0: int = contact.offsets.x + (result.cell.x << 8)
	var z0: int = contact.offsets.y + (result.cell.y << 8)
	var key := Vector3i(_selected, result.cell.x, result.cell.y)
	if key != _cell_key:
		_contact_cell.mesh = _grid_mesh(x0, z0, x0 + 256, z0 + 256, contact.height, Color(0.2, 1.0, 0.4), false)
		_cell_key = key
	_contact_cell.visible = true

func _selected_contact() -> FormContactDefinition:
	return _contacts[_selected] if _selected >= 0 and _selected < _contacts.size() else null

func _rebuild_contact_outline() -> void:
	if _contact_outline == null:
		return
	var contact: FormContactDefinition = _selected_contact()
	if contact == null or not contact.unsupported_reason.is_empty() or contact.dimensions.x <= 0 or contact.dimensions.y <= 0:
		_contact_outline.visible = false
		_contact_cell.visible = false
		return
	_contact_outline.mesh = _grid_mesh(contact.offsets.x, contact.offsets.y,
		contact.offsets.x + (contact.dimensions.x << 8), contact.offsets.y + (contact.dimensions.y << 8),
		contact.height, Color(1.0, 0.8, 0.2), true, contact.dimensions)
	_contact_outline.visible = true
	_contact_cell.visible = false

static func _grid_mesh(x0: int, z0: int, x1: int, z1: int, y: int, color: Color, include_cells: bool, dimensions: Vector2i = Vector2i.ONE) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var x_count: int = dimensions.x if include_cells else 1
	var z_count: int = dimensions.y if include_cells else 1
	for column: int in x_count + 1:
		var x: int = x0 + column * 256
		mesh.surface_add_vertex(GameSpace.position(x, y, z0))
		mesh.surface_add_vertex(GameSpace.position(x, y, z1))
	for row: int in z_count + 1:
		var z: int = z0 + row * 256
		mesh.surface_add_vertex(GameSpace.position(x0, y, z))
		mesh.surface_add_vertex(GameSpace.position(x1, y, z))
	mesh.surface_end()
	return mesh

## Marker count exposes lifecycle state to inspection tests.
func marker_count() -> int:
	var count: int = 0
	for marker: MeshInstance3D in _positions:
		if marker != null:
			count += 1
	return count

func _create_marker(index: int) -> void:
	var axes := MeshInstance3D.new()
	axes.mesh = _axes_mesh()
	add_child(axes)
	_axes[index] = axes
	var position := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	position.mesh = sphere
	add_child(position)
	_positions[index] = position
	_style_marker(index)

func _destroy_marker(index: int) -> void:
	if _axes[index] != null:
		remove_child(_axes[index])
		_axes[index].queue_free()
		_axes[index] = null
	if _positions[index] != null:
		remove_child(_positions[index])
		_positions[index].queue_free()
		_positions[index] = null
	_generations[index] = -1

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
