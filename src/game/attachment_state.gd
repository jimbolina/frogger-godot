class_name AttachmentState
extends RefCounted
## Platform-local attachment and per-tick contact identities.

var entity_hit_indices: PackedInt32Array = PackedInt32Array()
var death_entity_index: int = -1
var current_entity_index: int = -1
var forbidden_entity_index: int = -1
var entity_cell: Vector2i = Vector2i.ZERO
var entity_offset_16: Vector3i = Vector3i.ZERO
var entity_angle: int = 0
var entity_transform12: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var entity_carry_indices: PackedInt32Array = PackedInt32Array()
## Source primitive collision-rotation cache; it persists across contacts and ticks.
var primitive_transpose: CollisionTransposeCache = CollisionTransposeCache.new()

## Returns an independently mutable copy of every value.
func copy() -> AttachmentState:
	var result := AttachmentState.new()
	result.entity_hit_indices = entity_hit_indices.duplicate()
	result.current_entity_index = current_entity_index
	result.forbidden_entity_index = forbidden_entity_index
	result.entity_cell = entity_cell
	result.entity_offset_16 = entity_offset_16
	result.entity_angle = entity_angle
	result.entity_transform12 = entity_transform12.duplicate()
	result.entity_carry_indices = entity_carry_indices.duplicate()
	result.death_entity_index = death_entity_index
	result.primitive_transpose = primitive_transpose.copy()
	return result
