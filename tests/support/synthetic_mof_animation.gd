class_name SyntheticMofAnimation
extends RefCounted
## Builds synthetic animated model records, with configurable authored
## transforms, holding the values the same animated model file decodes to.
## Values that only describe where things lie in a file, such as
## [member MofAnimated.length] and [member MofAnimated.static_ranges], keep
## their defaults.

## The animated model file of one model set whose [param static_models]
## share [param actions], with [param transforms] of encoding [param code].
static func animated_file(static_models: Array[MofStatic], code: int = 2,
		transforms: Array[MofTransform] = [], actions: Array[MofAnimated.Action] = [],
		starts_at_zero: bool = true) -> MofFile:
	var file := MofFile.new()
	file.kind = MofFile.Kind.ANIMATED
	file.flags = MofAnimated.EXPECTED_FLAGS
	file.signature = PackedByteArray([0x31 if starts_at_zero else 0x30, 0x30 + code, 0x61, 0x78]).hex_encode()
	var animated := MofAnimated.new()
	file.animated = animated
	animated.flags = MofAnimated.EXPECTED_FLAGS
	animated.model_set_count = 1
	animated.starts_at_frame_zero = starts_at_zero
	animated.transform_code = code
	animated.shared_flags = 9
	animated.transform_count = transforms.size()
	for authored: MofTransform in transforms:
		var stored: MofTransform = _stored(authored, code)
		animated.transforms.append(stored)
		if code >= 4 and stored.raw_values.size() == 11 and stored.raw_values[10] & ~1 != 0:
			var message: String = "undefined scale flags 0x%02X preserved; only bit 0 is applied, as in C" % (stored.raw_values[10] & 255)
			if not animated.diagnostics.has(message):
				animated.diagnostics.append(message)
	var model_set := MofModelSet.new()
	for i: int in static_models.size():
		var info := MofModelInfo.new()
		info.animation_type = 1
		info.static_model_index = i
		info.part_count = static_models[i].parts.size()
		model_set.models.append(info)
	for authored: MofAction in actions:
		model_set.actions.append(_action(authored, animated))
	animated.model_sets.append(model_set)
	for i: int in static_models.size():
		var model: MofStatic = static_models[i]
		file.static_models.append(model)
		if model.is_incomplete:
			file.is_incomplete = true
		if file.error.is_empty() and not model.is_valid():
			file.error = "static model %d: %s" % [i, model.error]
	animated.validate_models(file.static_models)
	return file


## Makes a transform from semantic fields (disk order, excluding padding).
static func transform(code: int, values: Array[int]) -> MofTransform:
	var made := MofTransform.new()
	made.code = code
	made.raw_values = PackedInt32Array(values)
	return made


## Makes an authored action with its unique cels and virtual frames.
static func action(parts: int, cels: int, numbers: Array[int], indices: Array[int], interpolation: bool = false) -> MofAnimated.Action:
	var made := MofAnimated.Action.new()
	made.part_count = parts
	made.cel_count = cels
	made.frame_count = numbers.size() / (3 if interpolation else 1)
	made.flags = 2 if interpolation else 1
	made.cel_numbers = PackedInt32Array(numbers)
	made.transform_indices = PackedInt32Array(indices)
	return made


static func _stored(authored: MofTransform, code: int) -> MofTransform:
	var stored := MofTransform.new()
	stored.code = code
	var rotations: int = 9 if code <= 1 else 4
	for i: int in authored.raw_values.size():
		var value: int = authored.raw_values[i]
		var byte_sized: bool = (i < rotations and (code == 1 or code == 2 or code == 4)) or (code >= 4 and i >= 7)
		stored.raw_values.append(((value & 0xFF) ^ 0x80) - 0x80 if byte_sized else ((value & 0xFFFF) ^ 0x8000) - 0x8000)
	return stored


static func _action(authored: MofAction, animated: MofAnimated) -> MofAction:
	var made := MofAction.new()
	made.cel_count = authored.cel_count & 0xFFFF
	made.part_count = authored.part_count & 0xFFFF
	made.frame_count = authored.frame_count & 0xFFFF
	made.flags = authored.flags & 0xFFFF
	var number_count: int = made.frame_count * (3 if made.flags & 2 != 0 else 1)
	for n: int in number_count:
		made.cel_numbers.append(authored.cel_numbers[n] & 0xFFFF)
	for n: int in made.cel_count * made.part_count:
		var transform_index: int = ((authored.transform_indices[n] & 0xFFFF) ^ 0x8000) - 0x8000
		made.transform_indices.append(transform_index)
		if transform_index < 0 or transform_index >= animated.transforms.size():
			made.error = "transform index %d is outside the shared pool" % transform_index
	if made.flags != 1 and made.flags != 2:
		made.error = "unsupported action flags %d" % made.flags
	if made.cel_count == 0 or made.part_count == 0 or made.frame_count == 0:
		made.error = "action has no cels, parts or frames"
	if made.flags & 2 != 0 and animated.transform_code < 2:
		made.error = "matrix transforms cannot interpolate virtual cels"
	for n: int in number_count:
		var value: int = made.cel_numbers[n]
		if made.flags & 2 != 0 and n % 3 == 2:
			if value > 4096:
				made.error = "interpolation parameter exceeds 4096"
		else:
			var cel: int = value - (1 if made.flags & 2 == 0 and not animated.starts_at_frame_zero else 0)
			if cel < 0 or cel >= made.cel_count:
				made.error = "virtual frame names unavailable cel %d" % cel
	return made
