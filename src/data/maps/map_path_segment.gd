class_name MapPathSegment
extends Resource
## Raw final-PC PATH segment values; fixed-point fields are not recomputed.

@export var segment_type: int = -1
@export var length: int = 0
@export var source_offset: int = -1
@export var end_offset: int = -1
@export var start: Vector3i = Vector3i.ZERO
@export var end: Vector3i = Vector3i.ZERO
@export var centre: Vector3i = Vector3i.ZERO
@export var normal: Vector3i = Vector3i.ZERO
@export var radius: int = 0
@export var pitch: int = 0
@export var matrix: PackedInt32Array = PackedInt32Array()
@export var smooth_t: PackedInt32Array = PackedInt32Array()
@export var smooth_c: PackedInt32Array = PackedInt32Array()
