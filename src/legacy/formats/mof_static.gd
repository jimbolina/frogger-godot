class_name MofStatic
extends RefCounted
## A static model: parts made of polygons, with no skeleton.
##
## Layout (FrogLord's [code]MRStaticMof[/code]); pointers count from the
## first byte of the signature:
## [codeblock]
## 0x02 "FOM"   u32 length of the model   u32 flags   u32 part count
## part headers, 44 bytes each (see MofPart)
## u32 (purpose unknown)
## the vector pool: vertices and normals of every part, 8 bytes each
##     (s16 x, s16 y, s16 z, s16 unused)
## per part: partcels, bounding boxes, hilites, collision primitives,
##     matrices, texture animation, flipbook, polygons
## [/codeblock]
## Such a model is a file of its own (".XMR") or one of the models inside an
## animated file ([MofAnimated]). "Static" only means it has no skeleton: it
## can still hold flipbook animation (several poses per part) and animated
## textures.
##
## An [b]incomplete[/b] model saves memory: it stores its header and its
## polygons and takes everything else from another model with the same
## shape. The gold frogs of the five checkpoints are one model and four
## incomplete ones in other colours. It is recognised by the first part's
## partcel pointer being 0x40.

## Flag: the model has animated textures.
const FLAG_ANIMATED_TEXTURES: int = 1 << 4
## Flag: the model has flipbook animation.
const FLAG_FLIPBOOK: int = 1 << 5
## Size of the header, up to and including the part count.
const HEADER_SIZE: int = 16
## Where the test for an incomplete model looks.
const INCOMPLETE_TEST_OFFSET: int = 0x1C
## The value found there in an incomplete model.
const INCOMPLETE_TEST_VALUE: int = 0x40

## Length the model states for itself.
var length: int = 0
## Flags as stored.
var flags: int = 0
## True when the model borrows its shape from another.
var is_incomplete: bool = false
## The word after the part headers, whose purpose is unknown.
var unknown_word: int = 0
## The parts.
var parts: Array[MofPart] = []
## Why parsing failed, or "".
var error: String = ""


## True if a static model starts at [param base] of [param bytes].
static func is_static(bytes: PackedByteArray, base: int = 0) -> bool:
	return bytes.size() >= base + 4 and bytes[base] == 2 and bytes[base + 1] == 0x46 \
		and bytes[base + 2] == 0x4F and bytes[base + 3] == 0x4D


## True if the static model at [param base] of [param bytes] is incomplete.
static func is_incomplete_at(bytes: PackedByteArray, base: int = 0) -> bool:
	return bytes.size() >= base + INCOMPLETE_TEST_OFFSET + 4 \
		and bytes.decode_u32(base + INCOMPLETE_TEST_OFFSET) == INCOMPLETE_TEST_VALUE


## Parses the [param size] bytes at [param base] of [param bytes] ([param
## size] below 0: to the end). An incomplete model takes its shape from
## [param counterpart]. Check [member error].
static func parse(bytes: PackedByteArray, base: int = 0, size: int = -1, counterpart: MofStatic = null) -> MofStatic:
	var model := MofStatic.new()
	var reader := ByteReader.new(bytes, base, size)
	if reader.has_error() or not is_static(bytes, base):
		model.error = "not a static model"
		return model
	reader.skip(4)
	model.length = reader.read_u32()
	model.flags = reader.read_u32()
	var part_count: int = reader.read_u32()
	model.is_incomplete = is_incomplete_at(bytes, base)
	if part_count * MofPart.HEADER_SIZE > reader.remaining():
		model.error = "%d parts do not fit in %d bytes" % [part_count, reader.size()]
		return model
	for i: int in part_count:
		model.parts.append(MofPart.read_header(reader, i))
	model.unknown_word = reader.read_u32()
	var pool_start: int = reader.get_position()
	var pool_end: int = model.parts[0].partcels_offset() if part_count > 0 else pool_start
	for part: MofPart in model.parts:
		part.read_body(reader, pool_start, pool_end, model.is_incomplete)
		if reader.has_error():
			model.error = reader.error
			return model
	if reader.has_error():
		model.error = reader.error
		return model
	var end: int = model.parts[-1].end_offset if part_count > 0 else reader.get_position()
	if end != model.length or model.length != reader.size():
		model.error = "states %d bytes, its data ends at %d, and %d bytes are present" % [model.length, end, reader.size()]
		return model
	if model.is_incomplete:
		model.error = model._borrow(counterpart)
		if not model.error.is_empty():
			return model
	var expected: int = 0
	if model.texture_animation_target_count() > 0:
		expected |= FLAG_ANIMATED_TEXTURES
	var flipbook_source: MofStatic = counterpart if model.is_incomplete else model
	if flipbook_source.flipbook_action_count() > 0:
		expected |= FLAG_FLIPBOOK
	if model.flags != expected:
		model.error = "flags 0x%X, expected 0x%X from what it holds" % [model.flags, expected]
	return model


## True when the model parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Polygons of all parts.
func polygon_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.polygons.size()
	return total


## Flipbook animations of all parts.
func flipbook_action_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.flipbook_action_count
	return total


## Polygons with animated textures, over all parts.
func texture_animation_target_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.texture_animation_target_count
	return total


## The texture ids the polygons use, each once, in rising order.
func image_ids() -> PackedInt32Array:
	var seen: Dictionary[int, bool] = {}
	for part: MofPart in parts:
		for polygon: MofPolygon in part.polygons:
			if polygon.is_textured():
				seen[polygon.image_id] = true
	var ids := PackedInt32Array(seen.keys())
	ids.sort()
	return ids


func _borrow(counterpart: MofStatic) -> String:
	if counterpart == null or not counterpart.is_valid() or counterpart.is_incomplete:
		return "incomplete, and there is no complete model to take its shape from"
	if counterpart.parts.size() != parts.size():
		return "incomplete with %d parts, but the model it takes its shape from has %d" % [parts.size(), counterpart.parts.size()]
	for i: int in parts.size():
		parts[i].borrow_from(counterpart.parts[i])
	return ""
