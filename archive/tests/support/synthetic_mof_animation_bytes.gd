class_name SyntheticMofAnimationBytes
extends RefCounted
## Writes complete synthetic animated model files (XAR), with configurable
## authored transforms, for the reader tests.

## Writes one model set whose static models share the supplied actions.
static func build(static_models: Array[PackedByteArray], code: int = 2,
		transforms: Array[MofTransform] = [], actions: Array[MofAnimated.Action] = [],
		starts_at_zero: bool = true) -> PackedByteArray:
	var model_set := MofAnimated.ModelSet.new()
	model_set.actions = actions
	for i: int in static_models.size():
		var model := MofAnimated.ModelInfo.new()
		model.animation_type = 1
		model.static_model_index = i
		model.part_count = static_models[i].decode_u32(12)
		model_set.models.append(model)
	return build_sets(static_models, [model_set], code, transforms, starts_at_zero)


## Writes multiple independent sets and optional model bounding boxes.
## Each set's static indices, flags and actions are authored independently.
static func build_sets(static_models: Array[PackedByteArray], sets: Array[MofAnimated.ModelSet],
		code: int = 2, transforms: Array[MofTransform] = [], starts_at_zero: bool = true) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(28 + 20 * sets.size())
	for set_index: int in sets.size():
		var model_set: MofAnimated.ModelSet = sets[set_index]
		var header_at: int = 28 + 20 * set_index
		var models_at: int = out.size()
		out.resize(out.size() + 24 * model_set.models.size())
		var box_offsets := PackedInt32Array()
		for model: MofAnimated.ModelInfo in model_set.models:
			box_offsets.append(out.size())
			if not model.bounding_box.is_empty():
				for i: int in 8:
					for component: int in 3:
						_u16(out, model.bounding_box[i * 3 + component])
					_u16(out, 0)
		var cels_at: int = out.size()
		var actions_at: int = cels_at + 8
		out.resize(actions_at + 16 * model_set.actions.size())
		for i: int in model_set.actions.size():
			var authored: MofAnimated.Action = model_set.actions[i]
			var at: int = actions_at + i * 16
			out.encode_u16(at, authored.cel_count)
			out.encode_u16(at + 2, authored.part_count)
			out.encode_u16(at + 4, authored.frame_count)
			out.encode_u16(at + 6, authored.flags)
			out.encode_u32(at + 8, out.size())
			for value: int in authored.cel_numbers:
				_u16(out, value)
			_align(out)
			out.encode_u32(at + 12, out.size())
			for value: int in authored.transform_indices:
				_u16(out, value)
			_align(out)
		out.encode_u32(header_at, model_set.flags)
		out[header_at + 4] = model_set.models.size()
		out[header_at + 5] = 1
		out.encode_u32(header_at + 8, models_at)
		out.encode_u32(header_at + 12, cels_at)
		out.encode_u32(header_at + 16, out.size())
		for i: int in model_set.models.size():
			var model: MofAnimated.ModelInfo = model_set.models[i]
			var at: int = models_at + i * 24
			out.encode_u16(at, model.animation_type)
			out.encode_u16(at + 2, model.flags)
			out.encode_u16(at + 4, model.part_count)
			out.encode_u16(at + 6, model.static_model_index)
			out.encode_u32(at + 8, cels_at)
			out.encode_u32(at + 12, box_offsets[i])
		out.encode_u16(cels_at, model_set.actions.size())
		out.encode_u32(cels_at + 4, actions_at)
	var shared_at: int = out.size()
	out.resize(shared_at + 28)
	out.encode_u32(shared_at, 9)
	out.encode_u16(shared_at + 4, transforms.size())
	out.encode_u32(shared_at + 12, out.size())
	for authored_transform: MofTransform in transforms:
		_write_transform(out, code, authored_transform.raw_values)
	_align(out)
	out.encode_u32(shared_at + 24, out.size())
	var starts := PackedInt32Array()
	for model: PackedByteArray in static_models:
		starts.append(out.size())
		out.append_array(model)
	var table_at: int = out.size()
	for start: int in starts:
		_u32(out, start)
	out[0] = 0x31 if starts_at_zero else 0x30
	out[1] = 0x30 + code
	out[2] = 0x61
	out[3] = 0x78
	out.encode_u32(4, out.size())
	out.encode_u32(8, MofAnimated.EXPECTED_FLAGS)
	out.encode_u16(12, sets.size())
	out.encode_u16(14, static_models.size())
	out.encode_u32(16, 28)
	out.encode_u32(20, shared_at)
	out.encode_u32(24, table_at)
	return out

static func _write_transform(out: PackedByteArray, code: int, values: PackedInt32Array) -> void:
	var rotations: int = 9 if code <= 1 else 4
	for i: int in rotations:
		if code == 1 or code == 2 or code == 4:
			out.append(values[i] & 255)
		else:
			_u16(out, values[i])
	if code == 1:
		out.append(0)
	for i: int in range(rotations, rotations + 3):
		_u16(out, values[i])
	if code >= 4:
		for i: int in range(7, 11):
			out.append(values[i] & 255)


static func _align(out: PackedByteArray) -> void:
	while out.size() % 4 != 0:
		out.append(0)


static func _u16(out: PackedByteArray, value: int) -> void:
	out.resize(out.size() + 2)
	out.encode_u16(out.size() - 2, value & 65535)


static func _u32(out: PackedByteArray, value: int) -> void:
	out.resize(out.size() + 4)
	out.encode_u32(out.size() - 4, value)
