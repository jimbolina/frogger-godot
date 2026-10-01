class_name MofFile
extends RefCounted
## A model file ("MOF"): a placeholder, a static model or an animated model.
##
## Every model lives inside a WAD. What a file is shows in its first bytes,
## never in its name (FrogLord's [code]MRModel[/code]):
## [br]- the four bytes [code]DUMY[/code] and nothing else: a placeholder. A
##   level's WAD has a slot for every model of its theme, and the ones the
##   level does not use are placeholders;
## [br]- bit 3 of the flags at byte 8 set: an animated model ([MofAnimated]),
##   which holds one or more static models;
## [br]- otherwise a static model ([MofStatic]).
##
## Whatever the kind, the shapes end up in [member static_models], so code
## that only draws a model does not care which it was.

## What a model file holds.
enum Kind {
	## Not a model.
	UNKNOWN,
	## A placeholder.
	DUMMY,
	## One static model.
	STATIC,
	## An animated model holding static models.
	ANIMATED,
}

## Names of [enum Kind], as the golden facts write them.
const KIND_NAMES: Array[String] = ["unknown", "dummy", "static", "animated"]
## The contents of a placeholder.
const DUMMY_SIGNATURE: String = "DUMY"

## What the file holds.
var kind: Kind = Kind.UNKNOWN
## The first four bytes, as hexadecimal.
var signature: String = ""
## Size of the file.
var size: int = 0
## Flags as stored (0 for a placeholder).
var flags: int = 0
## True when a static model in the file borrows its shape from another file.
var is_incomplete: bool = false
## The outside of an animated model, or null.
var animated: MofAnimated
## The static models: one for a static file, those inside an animated file,
## none for a placeholder.
var static_models: Array[MofStatic] = []
## Why parsing failed, or "".
var error: String = ""


## What [param bytes] hold, judged by their first bytes.
static func kind_of(bytes: PackedByteArray) -> Kind:
	if bytes.size() >= 4 and bytes.slice(0, 4) == DUMMY_SIGNATURE.to_ascii_buffer():
		return Kind.DUMMY
	if bytes.size() < 12:
		return Kind.UNKNOWN
	if bytes.decode_u32(8) & MofAnimated.FLAG_ANIMATED != 0:
		return Kind.ANIMATED if MofAnimated.has_signature(bytes) else Kind.UNKNOWN
	return Kind.STATIC if MofStatic.is_static(bytes) else Kind.UNKNOWN


## True if [param bytes] hold an incomplete model, which can only be parsed
## together with the model it takes its shape from.
static func needs_counterpart(bytes: PackedByteArray) -> bool:
	match kind_of(bytes):
		Kind.STATIC:
			return MofStatic.is_incomplete_at(bytes)
		Kind.ANIMATED:
			var outside: MofAnimated = MofAnimated.parse_header(bytes)
			for part: Vector2i in outside.static_ranges:
				if MofStatic.is_incomplete_at(bytes, part.x):
					return true
	return false


## Parses [param bytes]. An incomplete model takes its shape from [param
## counterpart]. Check [member error].
static func parse(bytes: PackedByteArray, counterpart: MofFile = null) -> MofFile:
	var file := MofFile.new()
	file.size = bytes.size()
	file.signature = bytes.slice(0, 4).hex_encode()
	file.kind = kind_of(bytes)
	match file.kind:
		Kind.UNKNOWN:
			file.error = "not a model"
		Kind.DUMMY:
			pass
		Kind.STATIC:
			file.flags = bytes.decode_u32(8)
			file._add_static(MofStatic.parse(bytes, 0, -1, _static_of(counterpart, 0)), 0)
		Kind.ANIMATED:
			file.flags = bytes.decode_u32(8)
			file.animated = MofAnimated.parse(bytes)
			if not file.animated.is_valid():
				file.error = file.animated.error
				return file
			for i: int in file.animated.static_ranges.size():
				var part: Vector2i = file.animated.static_ranges[i]
				file._add_static(MofStatic.parse(bytes, part.x, part.y, _static_of(counterpart, i)), i)
			file.animated.validate_models(file.static_models)
	return file


## True when the file parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Name of the kind, e.g. "static".
func kind_name() -> String:
	return KIND_NAMES[kind]


## Parts of all static models.
func part_count() -> int:
	var total: int = 0
	for model: MofStatic in static_models:
		total += model.parts.size()
	return total


## Polygons of all static models.
func polygon_count() -> int:
	var total: int = 0
	for model: MofStatic in static_models:
		total += model.polygon_count()
	return total


## The texture ids the polygons use, each once, in rising order.
func image_ids() -> PackedInt32Array:
	var seen: Dictionary[int, bool] = {}
	for model: MofStatic in static_models:
		for id: int in model.image_ids():
			seen[id] = true
	var ids := PackedInt32Array(seen.keys())
	ids.sort()
	return ids


static func _static_of(file: MofFile, position: int) -> MofStatic:
	if file == null or position >= file.static_models.size():
		return null
	return file.static_models[position]


func _add_static(model: MofStatic, position: int) -> void:
	static_models.append(model)
	if model.is_incomplete:
		is_incomplete = true
	if error.is_empty() and not model.is_valid():
		error = "static model %d: %s" % [position, model.error] if kind == Kind.ANIMATED else model.error
