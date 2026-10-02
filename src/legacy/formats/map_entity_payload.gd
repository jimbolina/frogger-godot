class_name MapEntityPayload
extends RefCounted
## Bounded base-transform decoder for an entity's retained payload.

## Failure reason, or empty when the selected base record decoded.
var error: String = ""
## PSX rotation in row order (fixed12), followed by whole-unit translation.
var matrix12: PackedInt32Array = PackedInt32Array()
## PATH_INFO source path index and initial runner fields.
var path_index: int = -1
var segment_index: int = 0
var segment_distance: int = 0
var motion_flags: int = 0
var speed: int = 0

## Reads only the common PSXMatrix prefix; subtype bytes remain in the span.
static func read_matrix(span: MapEntitySpan) -> MapEntityPayload:
	var result := MapEntityPayload.new()
	if span == null or span.payload.size() < 32:
		result.error = "Entity PSXMatrix payload requires 32 bytes"
		return result
	for index: int in 9:
		result.matrix12.append(span.payload.decode_s16(index * 2))
	# The source matrix carries a 16-bit pad at byte 18. FrogLord reads it
	# without requiring zero, including older maps with other pad values.
	for index: int in 3:
		result.matrix12.append(span.payload.decode_s32(20 + index * 4))
	return result

## Reads the 12-byte PATH_INFO prefix, including its required empty padding.
static func read_path_info(span: MapEntitySpan) -> MapEntityPayload:
	var result := MapEntityPayload.new()
	if span == null or span.payload.size() < 12:
		result.error = "Entity PATH_INFO payload requires 12 bytes"
		return result
	result.path_index = span.payload.decode_u16(0)
	result.segment_index = span.payload.decode_u16(2)
	result.segment_distance = span.payload.decode_u16(4)
	result.motion_flags = span.payload.decode_u16(6)
	result.speed = span.payload.decode_u16(8)
	if span.payload.decode_u16(10) != 0:
		result.error = "Entity PATH_INFO padding is nonzero"
	return result
