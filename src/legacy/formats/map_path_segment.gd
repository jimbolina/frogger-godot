class_name MapPathSegment
extends RefCounted
## Raw final-PC PATH segment values; fixed-point fields are not recomputed.

var segment_type: int = -1
var length: int = 0
var source_offset: int = -1
var end_offset: int = -1
var start: Vector3i = Vector3i.ZERO
var end: Vector3i = Vector3i.ZERO
var centre: Vector3i = Vector3i.ZERO
var normal: Vector3i = Vector3i.ZERO
var radius: int = 0
var pitch: int = 0
var matrix: PackedInt32Array = PackedInt32Array()
var smooth_t: PackedInt32Array = PackedInt32Array()
var smooth_c: PackedInt32Array = PackedInt32Array()
