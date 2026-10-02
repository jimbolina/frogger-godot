class_name PathSegmentDefinition
extends RefCounted
## Detached source path segment with raw integer coefficients.

const SPLINE: int = 0
const ARC: int = 1
const LINE: int = 2

var segment_type: int = LINE
var length: int = 0
var source_offset: int = -1
var start: Vector3i = Vector3i.ZERO
var end: Vector3i = Vector3i.ZERO
var centre: Vector3i = Vector3i.ZERO
var normal: Vector3i = Vector3i.ZERO
var radius: int = 0
var pitch: int = 0
var matrix: PackedInt32Array = PackedInt32Array()
var smooth_t: PackedInt32Array = PackedInt32Array()
var smooth_c: PackedInt32Array = PackedInt32Array()

## Returns an independent copy of all segment fields and coefficient arrays.
func copy() -> PathSegmentDefinition:
	var result := PathSegmentDefinition.new()
	result.segment_type = segment_type
	result.length = length
	result.source_offset = source_offset
	result.start = start
	result.end = end
	result.centre = centre
	result.normal = normal
	result.radius = radius
	result.pitch = pitch
	result.matrix = matrix.duplicate()
	result.smooth_t = smooth_t.duplicate()
	result.smooth_c = smooth_c.duplicate()
	return result
