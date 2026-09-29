class_name MofAnimated
extends RefCounted
## The outside of an animated model file (".XAR"): where its static models are.
##
## Layout (FrogLord's [code]MRAnimatedMof[/code]):
## [codeblock]
## signature: '0', '1' or 0, then a digit, then "ax"
## u32 length of the file   u32 flags (always 0x110008)
## u16 model sets   u16 static models
## u32 model sets at   u32 shared animation data at   u32 model table at
## model sets, shared animation data (transforms, poses)
## the static models, one after another (see MofStatic)
## model table: u32 where each static model starts
## [/codeblock]
## The first signature byte '1' means animations start at frame zero; the
## digit says how transforms are stored. A static model inside the file is
## whole: its own pointers count from its own first byte. It runs up to the
## start of the next one, and the last one up to the model table.
##
## This class only finds the static models. The skeleton and the animations
## are read by a later phase.

## Flag: the file is an animated model.
const FLAG_ANIMATED: int = 1 << 3
## The flags every animated model has.
const EXPECTED_FLAGS: int = (1 << 20) | (1 << 16) | FLAG_ANIMATED
## Size of the header.
const HEADER_SIZE: int = 28

## Length the file states for itself.
var length: int = 0
## Flags as stored.
var flags: int = 0
## Number of model sets.
var model_set_count: int = 0
## True when the signature says animations start at frame zero.
var starts_at_frame_zero: bool = false
## The signature's digit: how transforms are stored.
var transform_code: int = 0
## Start (x) and size (y) of each static model inside the file.
var static_ranges: Array[Vector2i] = []
## Why parsing failed, or "".
var error: String = ""


## True if [param bytes] carry the signature of an animated model.
static func has_signature(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4:
		return false
	var first: int = bytes[0]
	return (first == 0 or first == 0x30 or first == 0x31) and bytes[1] >= 0x30 and bytes[1] <= 0x39 \
		and bytes[2] == 0x61 and bytes[3] == 0x78


## Parses the header and model table of [param bytes]. Check [member error].
static func parse(bytes: PackedByteArray) -> MofAnimated:
	var model := MofAnimated.new()
	var reader := ByteReader.new(bytes)
	if not has_signature(bytes) or bytes.size() < HEADER_SIZE:
		model.error = "not an animated model"
		return model
	model.starts_at_frame_zero = bytes[0] == 0x31
	model.transform_code = bytes[1] - 0x30
	reader.skip(4)
	model.length = reader.read_u32()
	model.flags = reader.read_u32()
	model.model_set_count = reader.read_u16()
	var static_count: int = reader.read_u16()
	var sets_at: int = reader.read_u32()
	var shared_at: int = reader.read_u32()
	var table_at: int = reader.read_u32()
	if model.flags != EXPECTED_FLAGS:
		model.error = "flags 0x%X, expected 0x%X" % [model.flags, EXPECTED_FLAGS]
		return model
	if sets_at != HEADER_SIZE:
		model.error = "model sets at %d, expected %d" % [sets_at, HEADER_SIZE]
		return model
	if table_at + 4 * static_count != model.length or model.length != bytes.size():
		model.error = "states %d bytes, its model table ends at %d, and %d bytes are present" % [
			model.length, table_at + 4 * static_count, bytes.size()]
		return model
	var starts := PackedInt32Array()
	reader.seek(table_at)
	for _i: int in static_count:
		starts.append(reader.read_u32())
	if reader.has_error():
		model.error = reader.error
		return model
	for i: int in static_count:
		var end: int = starts[i + 1] if i + 1 < static_count else table_at
		if starts[i] <= shared_at or end <= starts[i] or end > table_at:
			model.error = "static model %d runs from %d to %d" % [i, starts[i], end]
			return model
		model.static_ranges.append(Vector2i(starts[i], end - starts[i]))
	return model


## True when the file parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()
