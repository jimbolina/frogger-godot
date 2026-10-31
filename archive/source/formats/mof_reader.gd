class_name MofReader
extends RefCounted
## Decodes a model file ("MOF") into a [MofFile].
##
## What a file is shows in its first bytes, never in its name (see
## [MofFile]). Static models are read by [MofStaticReader], the outside of an
## animated model by [MofAnimatedReader].


## What [param bytes] hold, judged by their first bytes.
static func kind_of(bytes: PackedByteArray) -> MofFile.Kind:
	if bytes.size() >= 4 and bytes.slice(0, 4) == MofFile.DUMMY_SIGNATURE.to_ascii_buffer():
		return MofFile.Kind.DUMMY
	if bytes.size() < 12:
		return MofFile.Kind.UNKNOWN
	if bytes.decode_u32(8) & MofAnimated.FLAG_ANIMATED != 0:
		return MofFile.Kind.ANIMATED if MofAnimatedReader.has_signature(bytes) else MofFile.Kind.UNKNOWN
	return MofFile.Kind.STATIC if MofStaticReader.is_static(bytes) else MofFile.Kind.UNKNOWN


## True if [param bytes] hold an incomplete model, which can only be parsed
## together with the model it takes its shape from.
static func needs_counterpart(bytes: PackedByteArray) -> bool:
	match kind_of(bytes):
		MofFile.Kind.STATIC:
			return MofStaticReader.is_incomplete_at(bytes)
		MofFile.Kind.ANIMATED:
			var outside: MofAnimated = MofAnimatedReader.read_header(bytes)
			for part: Vector2i in outside.static_ranges:
				if MofStaticReader.is_incomplete_at(bytes, part.x):
					return true
	return false


## Parses [param bytes]. An incomplete model takes its shape from [param
## counterpart]. Check [member MofFile.error].
static func parse(bytes: PackedByteArray, counterpart: MofFile = null) -> MofFile:
	var file := MofFile.new()
	file.size = bytes.size()
	file.signature = bytes.slice(0, 4).hex_encode()
	file.kind = kind_of(bytes)
	match file.kind:
		MofFile.Kind.UNKNOWN:
			file.error = "not a model"
		MofFile.Kind.DUMMY:
			pass
		MofFile.Kind.STATIC:
			file.flags = bytes.decode_u32(8)
			_add_static(file, MofStaticReader.read(bytes, 0, -1, _static_of(counterpart, 0)), 0)
		MofFile.Kind.ANIMATED:
			file.flags = bytes.decode_u32(8)
			file.animated = MofAnimatedReader.read(bytes)
			if not file.animated.is_valid():
				file.error = file.animated.error
				return file
			for i: int in file.animated.static_ranges.size():
				var part: Vector2i = file.animated.static_ranges[i]
				_add_static(file, MofStaticReader.read(bytes, part.x, part.y, _static_of(counterpart, i)), i)
			file.animated.validate_models(file.static_models)
	return file


static func _static_of(file: MofFile, position: int) -> MofStatic:
	if file == null or position >= file.static_models.size():
		return null
	return file.static_models[position]


static func _add_static(file: MofFile, model: MofStatic, position: int) -> void:
	file.static_models.append(model)
	if model.is_incomplete:
		file.is_incomplete = true
	if file.error.is_empty() and not model.is_valid():
		file.error = "static model %d: %s" % [position, model.error] if file.kind == MofFile.Kind.ANIMATED else model.error
