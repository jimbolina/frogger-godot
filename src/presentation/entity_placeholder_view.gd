class_name EntityPlaceholderView
extends Node3D
## Footprint markers for entity slots that have no resolved model, following committed entity motion.

const COLOUR := Color(1.0, 0.45, 0.15)
const THICKNESS: float = 0.08

var _markers: Array[Node3D] = []
var _material: ShaderMaterial = null

## Creates one marker per `wanted` slot, sized from its FORM footprint when one is supplied.
func configure(wanted: Array[bool], contacts: Array[FormContactDefinition], projection_scale: Vector2) -> void:
	clear()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://src/presentation/tools/terrain_debug.gdshader")
	_material.set_shader_parameter("tint", COLOUR)
	_material.set_shader_parameter("projection_scale", projection_scale)
	for slot: int in wanted.size():
		if not wanted[slot]:
			_markers.append(null)
			continue
		var contact: FormContactDefinition = contacts[slot] if slot < contacts.size() else null
		var dimensions := Vector2i.ONE
		var offsets := Vector2i(-128, -128)
		var height: int = 0
		if contact != null and contact.dimensions.x > 0 and contact.dimensions.y > 0:
			dimensions = contact.dimensions
			offsets = contact.offsets
			height = contact.height
		var box := BoxMesh.new()
		box.size = Vector3(dimensions.x, THICKNESS, dimensions.y)
		var shape := MeshInstance3D.new()
		shape.mesh = box
		shape.material_override = _material
		shape.position = GameSpace.position(offsets.x + (dimensions.x << 7), height, offsets.y + (dimensions.y << 7))
		var marker := Node3D.new()
		marker.add_child(shape)
		marker.visible = false
		add_child(marker)
		_markers.append(marker)

## Removes every marker.
func clear() -> void:
	for marker: Node3D in _markers:
		if marker != null:
			remove_child(marker)
			marker.queue_free()
	_markers.clear()
	_material = null

## Places markers from the committed state's render samples and hides retired or hidden entities.
func draw_state(state: GameplayState, motion: TerrainMotion, weight: float) -> void:
	for slot: int in _markers.size():
		var marker: Node3D = _markers[slot]
		if marker == null:
			continue
		if state == null or state.entities == null or slot >= state.entities.entities.size():
			marker.visible = false
			continue
		var entity: EntitySnapshot = state.entities.entities[slot]
		marker.visible = entity.live and not entity.pop_allocated and not bool(entity.entity_flags & (EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY))
		if marker.visible:
			marker.transform = motion.entity(slot, weight)

## Applies the gameplay projection correction shared by terrain and models.
func set_projection_scale(scale: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("projection_scale", scale)

## Number of allocated markers, for presentation tests.
func marker_count() -> int:
	var count: int = 0
	for marker: Node3D in _markers:
		if marker != null:
			count += 1
	return count
