class_name SourceDemoFile
extends Resource
## Recorded PC demo header and unmodified input stream, decoded without playback state.

## Logic-tick duration, independent of the number of consumed input records.
@export var duration: int = 0
## Starting grid column.
@export var start_grid_x: int = 0
## Starting grid row.
@export var start_grid_z: int = 0
## Every stored input byte following the header, including unused capacity.
@export var input_bytes: PackedByteArray = PackedByteArray()
## Resource-specific decoding failure, or empty on success.
@export var error: String = ""


## True when the complete header was decoded and its values are nonnegative.
func is_valid() -> bool:
	return error.is_empty()


## Returns a raw unsigned input byte, or -1 for an exhausted or invalid cursor.
func input_at(cursor: int) -> int:
	if cursor < 0 or cursor >= input_bytes.size():
		return -1
	return input_bytes[cursor]
