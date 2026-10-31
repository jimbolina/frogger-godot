class_name PathScenario
extends RefCounted
## Decodes authored path stimuli and optionally selects a player's map path.

var error: String = ""
var name: String = ""
var definition: PathDefinition = null
var start: PathStart = null
var tick_limit: int = 16
var level_code: String = ""
var diagnostics: PackedStringArray = PackedStringArray()

## Builds a small path for visual inspection without source assets.
static func builtin(selected: String) -> PathScenario:
	var scenario := PathScenario.new()
	scenario.name = selected
	scenario.definition = PathDefinition.new()
	scenario.definition.source_id = "synthetic:" + selected
	scenario.start = PathStart.new()
	var segment := PathSegmentDefinition.new()
	match selected:
		"line":
			segment.segment_type = PathSegmentDefinition.LINE
			segment.length = 200
			segment.start = Vector3i(-100, 0, 0)
			segment.end = Vector3i(100, 0, 0)
		"arc":
			segment.segment_type = PathSegmentDefinition.ARC
			segment.length = 628
			segment.start = Vector3i(100, 0, 0)
			segment.centre = Vector3i.ZERO
			segment.normal = Vector3i(0, -4096, 0)
			segment.radius = 100
		"spline":
			segment.segment_type = PathSegmentDefinition.SPLINE
			segment.length = 100
			segment.matrix = PackedInt32Array([0, 0, 0, 0, 0, 0, 800, 0, 0, -400, 0, 0])
			segment.smooth_t = PackedInt32Array([32768, 65536, 98304, 131072])
			segment.smooth_c = PackedInt32Array([0, 0, 335544320, 0, 0, 335544320, 0, 0, 335544320, 0, 0, 335544320])
		_:
			scenario.error = "Unknown path scenario '%s'; choose line, arc or spline" % selected
			return scenario
	scenario.definition.segments.append(segment)
	scenario.error = PathRunner.validate_definition(scenario.definition)
	return scenario

## Reads one authored path scenario JSON object from disk.
static func from_file(path: String) -> PathScenario:
	var failed := PathScenario.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failed.error = "Cannot read path scenario '%s': %s" % [path, error_string(FileAccess.get_open_error())]
		return failed
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		failed.error = "Path scenario must be one JSON object: " + path
		return failed
	var object: Dictionary = json.data
	return from_object(object)

## Decodes exact integer fields from one JSON-compatible fixture object.
static func from_object(object: Dictionary) -> PathScenario:
	var scenario := PathScenario.new()
	if not object.get("name") is String or not object.get("segments") is Array or not object.get("start") is Dictionary:
		scenario.error = "Path scenario requires name, segments and start"
		return scenario
	scenario.name = object.get("name")
	var limit: Variant = object.get("tick_limit", 16)
	if not _bounded_int(limit, 0, 100000):
		scenario.error = "Path tick_limit must be an integer in 0..100000"
		return scenario
	scenario.tick_limit = _integer(limit)
	scenario.definition = PathDefinition.new()
	scenario.definition.source_id = "synthetic:" + scenario.name
	if object.has("source_id"):
		if not object.get("source_id") is String:
			scenario.error = "Path source_id must be a string"
			return scenario
		scenario.definition.source_id = object.get("source_id")
	for field: String in ["resource_id", "path_index", "source_offset"]:
		if not object.has(field):
			continue
		if not _bounded_int(object.get(field), -1, 2147483647):
			scenario.error = "Path %s must be an integer in -1..2147483647" % field
			return scenario
		var identity: int = _integer(object.get(field))
		match field:
			"resource_id":
				scenario.definition.resource_id = identity
			"path_index":
				scenario.definition.path_index = identity
			"source_offset":
				scenario.definition.source_offset = identity
	var raw_segments: Array = object.get("segments")
	for raw: Variant in raw_segments:
		if not raw is Dictionary:
			scenario.error = "Each path segment must be an object"
			return scenario
		var row: Dictionary = raw
		if not _bounded_int(row.get("segment_type"), 0, 2) or not _bounded_int(row.get("length"), 1, 2147483647):
			scenario.error = "Path segment requires known type and positive signed32 length"
			return scenario
		var segment := PathSegmentDefinition.new()
		segment.segment_type = _integer(row.get("segment_type"))
		segment.length = _integer(row.get("length"))
		if row.has("source_offset"):
			if not _bounded_int(row.get("source_offset"), -1, 2147483647):
				scenario.error = "Path segment source_offset must be an integer in -1..2147483647"
				return scenario
			segment.source_offset = _integer(row.get("source_offset"))
		if segment.segment_type == PathSegmentDefinition.LINE or segment.segment_type == PathSegmentDefinition.ARC:
			segment.start = _vector(row.get("start"))
			if segment.start == _invalid_vector():
				scenario.error = "Path segment start requires three signed16 integers"
				return scenario
		if segment.segment_type == PathSegmentDefinition.LINE:
			segment.end = _vector(row.get("end"))
			if segment.end == _invalid_vector():
				scenario.error = "Path line end requires three signed16 integers"
				return scenario
		elif segment.segment_type == PathSegmentDefinition.ARC:
			segment.centre = _vector(row.get("centre"))
			segment.normal = _vector(row.get("normal"))
			if segment.centre == _invalid_vector() or segment.normal == _invalid_vector() or not _bounded_int(row.get("radius"), -2147483648, 2147483647) or not _bounded_int(row.get("pitch"), -2147483648, 2147483647):
				scenario.error = "Path arc requires signed16 centre/normal and signed32 radius/pitch"
				return scenario
			segment.radius = _integer(row.get("radius"))
			segment.pitch = _integer(row.get("pitch"))
		else:
			segment.matrix = _int_array(row.get("matrix"), 12)
			segment.smooth_t = _int_array(row.get("smooth_t"), 4)
			segment.smooth_c = _int_array(row.get("smooth_c"), 12)
			if segment.matrix.size() != 12 or segment.smooth_t.size() != 4 or segment.smooth_c.size() != 12:
				scenario.error = "Path spline requires signed32 coefficient arrays of lengths 12, 4 and 12"
				return scenario
		scenario.definition.segments.append(segment)
	var raw_start: Dictionary = object.get("start")
	for field: String in ["segment_index", "distance", "speed", "flags"]:
		if not _bounded_int(raw_start.get(field), 0, 2147483647):
			scenario.error = "Path start %s must be a nonnegative signed32 integer" % field
			return scenario
	scenario.start = PathStart.new()
	scenario.start.segment_index = _integer(raw_start.get("segment_index"))
	scenario.start.distance = _integer(raw_start.get("distance"))
	scenario.start.speed = _integer(raw_start.get("speed"))
	scenario.start.flags = _integer(raw_start.get("flags"))
	scenario.error = PathRunner.validate_definition(scenario.definition)
	if scenario.error.is_empty():
		scenario.error = PathRunner.create(scenario.definition, scenario.start).error
	return scenario

## Replaces synthetic geometry with a detached path from one player's level.
func attach_data(data: AssetCatalog, selected_level_code: String, selected_path_index: int) -> String:
	if data == null or not data.is_valid():
		return "Path inspection requires valid player data"
	var number: int = FroggerIds.level_from_code(selected_level_code)
	if number < 0 or AssetCatalog.is_multiplayer_level(number):
		return "Path inspection requires a known single-player level code"
	var book: MapBookEntry = data.map_book_entry(number)
	if book == null:
		return "Path inspection cannot find the level's map entry"
	var resource_id: int = book.map_id(false)
	var problems := PackedStringArray()
	var map: MapFile = data.read_map(resource_id, problems)
	if map == null:
		return "Path inspection cannot read map: " + "; ".join(problems)
	var setup: PathSetup = PathSetup.from_map(map, data.version.internal_name + ":" + selected_level_code.to_upper(), resource_id, data.version.internal_name)
	if not setup.error.is_empty():
		return setup.error
	for diagnostic: PathSetupDiagnostic in setup.diagnostics:
		diagnostics.append(diagnostic.to_text())
	for item: PathDefinition in setup.definitions:
		if item.path_index == selected_path_index:
			definition = item.copy()
			level_code = selected_level_code.to_upper()
			name = level_code.to_lower() + "-path-%d" % selected_path_index
			return PathRunner.create(definition, start).error
	for diagnostic: PathSetupDiagnostic in setup.diagnostics:
		if diagnostic.path_index == selected_path_index:
			return diagnostic.to_text()
	return "Path index %d is not present in level %s" % [selected_path_index, selected_level_code]

static func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = value
	return is_finite(number) and number == floor(number) and number >= float(minimum) and number <= float(maximum)

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

static func _invalid_vector() -> Vector3i:
	return Vector3i(2147483647, 2147483647, 2147483647)

static func _vector(value: Variant) -> Vector3i:
	if not value is Array:
		return _invalid_vector()
	var items: Array = value
	if items.size() != 3:
		return _invalid_vector()
	for item: Variant in items:
		if not _bounded_int(item, -32768, 32767):
			return _invalid_vector()
	return Vector3i(_integer(items[0]), _integer(items[1]), _integer(items[2]))

static func _int_array(value: Variant, count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not value is Array:
		return result
	var items: Array = value
	if items.size() != count:
		return result
	for item: Variant in items:
		if not _bounded_int(item, -2147483648, 2147483647):
			return PackedInt32Array()
		result.append(_integer(item))
	return result
