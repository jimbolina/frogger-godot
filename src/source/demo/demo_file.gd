class_name SourceDemoFile
extends RefCounted
## Recorded PC demo header and unmodified input stream, decoded without playback state.

## Logic-tick duration, independent of the number of consumed input records.
var duration: int = 0
## Starting grid column.
var start_grid_x: int = 0
## Starting grid row.
var start_grid_z: int = 0
## Every stored input byte following the header, including unused capacity.
var input_bytes := PackedByteArray()
## Resource-specific decoding failure, or empty on success.
var error: String = ""


## Reads three little-endian signed integers and the remaining input bytes.
static func parse(bytes: PackedByteArray, resource_name: String = "demo") -> SourceDemoFile:
	var demo := SourceDemoFile.new()
	if bytes.size() < 12:
		demo.error = "%s: demo header needs 12 bytes, found %d" % [resource_name, bytes.size()]
		return demo
	demo.duration = bytes.decode_s32(0)
	demo.start_grid_x = bytes.decode_s32(4)
	demo.start_grid_z = bytes.decode_s32(8)
	if demo.duration < 0 or demo.start_grid_x < 0 or demo.start_grid_z < 0:
		demo.error = "%s: negative demo duration or starting grid coordinate" % resource_name
		return demo
	demo.input_bytes = bytes.slice(12)
	return demo


## True when the complete header was decoded and its values are nonnegative.
func is_valid() -> bool:
	return error.is_empty()


## Returns a raw unsigned input byte, or -1 for an exhausted or invalid cursor.
func input_at(cursor: int) -> int:
	if cursor < 0 or cursor >= input_bytes.size():
		return -1
	return input_bytes[cursor]
