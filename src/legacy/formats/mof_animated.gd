class_name MofAnimated
extends RefCounted
## The model sets, authored actions and shared transforms of an XAR file.

## Flag identifying an animated model file.
const FLAG_ANIMATED: int = 1 << 3
## Indexed whole transforms and animation data flags used by PC Frogger.
const EXPECTED_FLAGS: int = (1 << 20) | (1 << 16) | FLAG_ANIMATED
## Header size before the model set table.
const HEADER_SIZE: int = 28

## An authored action, including virtual frames and transform indices.
class Action:
	extends RefCounted
	var cel_count: int = 0
	var part_count: int = 0
	var frame_count: int = 0
	var flags: int = 0
	var cel_numbers := PackedInt32Array()
	var transform_indices := PackedInt32Array()
	## A semantic problem disables sampling but preserves the authored record.
	var error: String = ""

## Animation metadata for one embedded static model.
class ModelInfo:
	extends RefCounted
	var animation_type: int = 0
	var static_model_index: int = 0
	var part_count: int = 0
	var flags: int = 0
	var bounding_box := PackedInt32Array()

## A group of models sharing one ordered list of authored actions.
class ModelSet:
	extends RefCounted
	var flags: int = 0
	var models: Array[ModelInfo] = []
	var actions: Array[Action] = []

## File length and flags as stored.
var length: int = 0
var flags: int = 0
## Number of model sets in the header.
var model_set_count: int = 0
## True when ordinary virtual cel references start at zero rather than one.
var starts_at_frame_zero: bool = false
## Transform encoding in the signature (0 through 5).
var transform_code: int = 0
## Offset and size of each embedded static model.
var static_ranges: Array[Vector2i] = []
## Authored model sets and shared transform pool.
var model_sets: Array[ModelSet] = []
var transforms: Array[MofTransform] = []
## Stored shared-data flags and count, for inspection without inferred facts.
var shared_flags: int = 0
var transform_count: int = 0
## Shared bounding boxes, when present.
var bounding_boxes: Array[PackedInt32Array] = []
## Structural parse error; semantic action errors are kept on each action.
var error: String = ""
## Preserved format bits whose meaning is unknown; sampling follows C's fallback.
var diagnostics := PackedStringArray()
var _sets_at: int = 0
var _shared_at: int = 0
var _table_at: int = 0


## True if the first four bytes identify an animated model.
static func has_signature(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4:
		return false
	return bytes[0] in [0, 0x30, 0x31] and bytes[1] >= 0x30 and bytes[1] <= 0x39 and bytes[2] == 0x61 and bytes[3] == 0x78


## Reads only the outside header and static ranges, for counterpart discovery.
static func parse_header(bytes: PackedByteArray) -> MofAnimated:
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
	model._sets_at = reader.read_u32()
	model._shared_at = reader.read_u32()
	model._table_at = reader.read_u32()
	if model.flags != EXPECTED_FLAGS:
		model.error = "flags 0x%X, expected 0x%X" % [model.flags, EXPECTED_FLAGS]
		return model
	if model._sets_at != HEADER_SIZE:
		model.error = "model sets at %d, expected %d" % [model._sets_at, HEADER_SIZE]
		return model
	if model._table_at + 4 * static_count != model.length or model.length != bytes.size():
		model.error = "states %d bytes, its model table ends at %d, and %d bytes are present" % [model.length, model._table_at + 4 * static_count, bytes.size()]
		return model
	if model._shared_at < HEADER_SIZE or model._shared_at >= model._table_at:
		model.error = "shared animation data outside the animation section"
		return model
	var starts := PackedInt32Array()
	reader.seek(model._table_at)
	for _i: int in static_count:
		starts.append(reader.read_u32())
	for i: int in static_count:
		var end: int = starts[i + 1] if i + 1 < static_count else model._table_at
		if starts[i] <= model._shared_at or end <= starts[i] or end > model._table_at:
			model.error = "static model %d runs from %d to %d" % [i, starts[i], end]
			return model
		model.static_ranges.append(Vector2i(starts[i], end - starts[i]))
	model.error = reader.error
	return model


## Reads bounded model sets, actions and all six shared transform encodings.
static func parse(bytes: PackedByteArray) -> MofAnimated:
	var model: MofAnimated = parse_header(bytes)
	if not model.is_valid():
		return model
	if model.transform_code >= MofTransform.SIZES.size():
		model.error = "unsupported transform encoding %d" % model.transform_code
		return model
	var end: int = model.static_ranges[0].x if not model.static_ranges.is_empty() else model._table_at
	var reader := ByteReader.new(bytes, 0, end)
	model._read_shared(reader)
	if not reader.has_error():
		model._read_sets(reader)
	model.error = reader.error
	return model


## True when all structures were bounded and read safely.
func is_valid() -> bool:
	return error.is_empty()


## Returns the action list for an embedded static model, or an empty list.
func actions_for(static_index: int) -> Array[Action]:
	for model_set: ModelSet in model_sets:
		for model: ModelInfo in model_set.models:
			if model.static_model_index == static_index:
				return model_set.actions
	return []


## Checks action part counts after embedded static models have been read.
## Unsafe references disable an action, rather than rejecting useful geometry.
func validate_models(models: Array[MofStatic]) -> void:
	for model_set: ModelSet in model_sets:
		for model: ModelInfo in model_set.models:
			for action: Action in model_set.actions:
				if model.static_model_index >= models.size():
					action.error = "static model index %d is unavailable" % model.static_model_index
				elif model.part_count != models[model.static_model_index].parts.size() or action.part_count < model.part_count:
					action.error = "action part count does not match its static model"


## Samples one authored integer frame and part; unavailable samples are empty.
## Interpolation triples use zero-based cel indices even on older signatures.
func sample_matrix(static_index: int, action_index: int, frame: int, part: int) -> PackedInt32Array:
	var actions: Array[Action] = actions_for(static_index)
	if not is_valid() or action_index < 0 or action_index >= actions.size():
		return PackedInt32Array()
	var action: Action = actions[action_index]
	if not action.error.is_empty() or frame < 0 or frame >= action.frame_count or part < 0 or part >= action.part_count:
		return PackedInt32Array()
	for model_set: ModelSet in model_sets:
		for model: ModelInfo in model_set.models:
			if model.static_model_index == static_index and part >= model.part_count:
				return PackedInt32Array()
	if action.flags & 2 != 0:
		var first: int = action.cel_numbers[frame * 3]
		var second: int = action.cel_numbers[frame * 3 + 1]
		var amount: int = action.cel_numbers[frame * 3 + 2]
		return transforms[action.transform_indices[first * action.part_count + part]].interpolate(transforms[action.transform_indices[second * action.part_count + part]], amount)
	var cel: int = action.cel_numbers[frame] - (0 if starts_at_frame_zero else 1)
	return transforms[action.transform_indices[cel * action.part_count + part]].matrix_values()


func _range(reader: ByteReader, at: int, count: int, stride: int, what: String) -> bool:
	if count < 0 or at < HEADER_SIZE or at > reader.size() or count > (reader.size() - at) / stride:
		reader.fail("%s at %d (%d entries) outside animation data" % [what, at, count])
		return false
	return not reader.has_error()


func _box(reader: ByteReader, at: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	if not _range(reader, at, 1, 64, "bounding box"):
		return values
	for i: int in 8:
		for component: int in 3:
			values.append(reader.s16_at(at + i * 8 + component * 2))
	return values


func _read_shared(reader: ByteReader) -> void:
	if not _range(reader, _shared_at, 1, 28, "shared header"):
		return
	reader.seek(_shared_at)
	shared_flags = reader.read_u32()
	transform_count = reader.read_s16()
	var rotations: int = reader.read_s16()
	var translations: int = reader.read_s16()
	var boxes: int = reader.read_s16()
	var at: int = reader.read_u32()
	var rotation_at: int = reader.read_u32()
	var translation_at: int = reader.read_u32()
	var box_at: int = reader.read_u32()
	if shared_flags != 9 or rotations != 0 or translations != 0 or rotation_at != 0 or translation_at != 0:
		reader.fail("unsupported shared animation flags or split transforms")
		return
	if not _range(reader, at, transform_count, MofTransform.SIZES[transform_code], "transforms"):
		return
	reader.seek(at)
	for _i: int in transform_count:
		var transform: MofTransform = MofTransform.read(reader, transform_code)
		transforms.append(transform)
		if transform_code >= 4 and transform.raw_values.size() == 11 and transform.raw_values[10] & ~1 != 0:
			var message: String = "undefined scale flags 0x%02X preserved; only bit 0 is applied, as in C" % (transform.raw_values[10] & 255)
			if not diagnostics.has(message):
				diagnostics.append(message)
	if not _range(reader, box_at, boxes, 64, "shared bounding boxes"):
		return
	for i: int in boxes:
		bounding_boxes.append(_box(reader, box_at + i * 64))


func _read_sets(reader: ByteReader) -> void:
	if not _range(reader, _sets_at, model_set_count, 20, "model sets"):
		return
	for set_index: int in model_set_count:
		reader.seek(_sets_at + set_index * 20)
		var model_set := ModelSet.new()
		model_set.flags = reader.read_u32()
		var model_count: int = reader.read_u8()
		var cel_sets: int = reader.read_u8()
		var bbox_sets: int = reader.read_u8()
		reader.skip(1)
		var models_at: int = reader.read_u32()
		var cels_at: int = reader.read_u32()
		var boxes_at: int = reader.read_u32()
		if model_set.flags != 0 or cel_sets != 1 or bbox_sets != 0:
			reader.fail("unsupported model set type, cel sets or per-cel bounding boxes")
			return
		if not _range(reader, models_at, model_count, 24, "models") or not _range(reader, boxes_at, 0, 1, "bounding box sets"):
			return
		for i: int in model_count:
			reader.seek(models_at + i * 24)
			var model := ModelInfo.new()
			model.animation_type = reader.read_u16()
			model.flags = reader.read_u16()
			model.part_count = reader.read_u16()
			model.static_model_index = reader.read_u16()
			if model.animation_type != 1 or model.flags & ~3 != 0:
				reader.fail("unsupported animation model type or flags")
				return
			var model_cels_at: int = reader.read_u32()
			var box_at: int = reader.read_u32()
			var bbox_set_at: int = reader.read_u32()
			var constraint_at: int = reader.read_u32()
			if model_cels_at != cels_at or constraint_at != 0 or bbox_set_at != 0:
				reader.fail("model has an inconsistent cel set or unsupported constraint/bounding box set")
				return
			if model.flags & 1 != 0 and box_at != 0:
				model.bounding_box = _box(reader, box_at)
			elif model.flags & 1 != 0:
				reader.fail("model's global bounding box pointer is null")
			elif box_at != 0:
				_range(reader, box_at, 0, 1, "unused bounding box pointer")
			model_set.models.append(model)
		_read_actions(reader, cels_at, model_set)
		model_sets.append(model_set)
		if reader.has_error():
			return


func _read_actions(reader: ByteReader, cels_at: int, model_set: ModelSet) -> void:
	if not _range(reader, cels_at, 1, 8, "cel set"):
		return
	reader.seek(cels_at)
	var action_count: int = reader.read_u16()
	reader.skip(2)
	var actions_at: int = reader.read_u32()
	if not _range(reader, actions_at, action_count, 16, "actions"):
		return
	for i: int in action_count:
		reader.seek(actions_at + i * 16)
		var action := Action.new()
		action.cel_count = reader.read_u16()
		action.part_count = reader.read_u16()
		action.frame_count = reader.read_u16()
		action.flags = reader.read_u16()
		var numbers_at: int = reader.read_u32()
		var indices_at: int = reader.read_u32()
		var number_count: int = action.frame_count * (3 if action.flags & 2 != 0 else 1)
		var index_count: int = action.cel_count * action.part_count
		if not _range(reader, numbers_at, number_count, 2, "virtual frames") or not _range(reader, indices_at, index_count, 2, "transform indices"):
			return
		for n: int in number_count:
			action.cel_numbers.append(reader.u16_at(numbers_at + n * 2))
		for n: int in index_count:
			var transform_index: int = reader.s16_at(indices_at + n * 2)
			action.transform_indices.append(transform_index)
			if transform_index < 0 or transform_index >= transforms.size():
				action.error = "transform index %d is outside the shared pool" % transform_index
		if action.flags != 1 and action.flags != 2:
			action.error = "unsupported action flags %d" % action.flags
		if action.cel_count == 0 or action.part_count == 0 or action.frame_count == 0:
			action.error = "action has no cels, parts or frames"
		if action.flags & 2 != 0 and transform_code < 2:
			action.error = "matrix transforms cannot interpolate virtual cels"
		for n: int in number_count:
			var value: int = action.cel_numbers[n]
			if action.flags & 2 != 0 and n % 3 == 2:
				if value > 4096:
					action.error = "interpolation parameter exceeds 4096"
			else:
				var cel: int = value - (1 if action.flags & 2 == 0 and not starts_at_frame_zero else 0)
				if cel < 0 or cel >= action.cel_count:
					action.error = "virtual frame names unavailable cel %d" % cel
		model_set.actions.append(action)
