class_name PathSetup
extends RefCounted
## Copies supported decoded PATH records into detached gameplay definitions.

var definitions: Array[PathDefinition] = []
var diagnostics: Array[PathSetupDiagnostic] = []
## Structural map failure only; unsupported path data appears in diagnostics.
var error: String = ""

## Builds all supported source-ordered paths without retaining decoded records.
static func from_map(map: MapFile, source_id: String = "", resource_id: int = -1, build_id: String = "") -> PathSetup:
	var result := PathSetup.new()
	if map == null:
		result.error = "Cannot set up paths from a null map"
		return result
	if not map.error.is_empty():
		result.error = "Cannot set up paths from an invalid map: " + map.error
		return result
	var packet: MapPacket = map.packets.get("PATH")
	if packet == null or map.paths.size() != packet.count or packet.offsets.size() != packet.count:
		result.error = "PATH record count does not match its header"
		return result
	for index: int in map.paths.size():
		var source: MapPath = map.paths[index]
		if source == null or source.path_index != index or source.source_offset != packet.offsets[index]:
			result.error = "PATH source identity does not match its pointer table"
			return result
		var definition := PathDefinition.new()
		definition.source_id = source_id
		definition.resource_id = resource_id
		definition.path_index = index
		definition.source_offset = source.source_offset
		definition.entity_indices = source.entity_indices.duplicate()
		definition.entity_list_error = source.entity_list_error
		var rejection: PathSetupDiagnostic = null
		for segment_index: int in source.segments.size():
			var source_segment: MapPathSegment = source.segments[segment_index]
			if source_segment == null:
				result.error = "PATH contains a null segment record"
				return result
			if source_segment.segment_type < 0 or source_segment.segment_type > 2:
				rejection = _diagnostic("unknown_segment_type", "Unsupported segment type %d" % source_segment.segment_type, source_id, resource_id, build_id, index, segment_index, source_segment.source_offset)
				break
			var segment := PathSegmentDefinition.new()
			segment.segment_type = source_segment.segment_type
			segment.length = source_segment.length
			segment.source_offset = source_segment.source_offset
			segment.start = source_segment.start
			segment.end = source_segment.end
			segment.centre = source_segment.centre
			segment.normal = source_segment.normal
			segment.radius = source_segment.radius
			segment.pitch = source_segment.pitch
			segment.matrix = source_segment.matrix.duplicate()
			segment.smooth_t = source_segment.smooth_t.duplicate()
			segment.smooth_c = source_segment.smooth_c.duplicate()
			definition.segments.append(segment)
		if rejection == null:
			var problem: String = PathRunner.validate_definition(definition)
			if not problem.is_empty():
				rejection = _diagnostic("invalid_geometry", problem, source_id, resource_id, build_id, index, -1, source.source_offset)
		if rejection != null:
			result.diagnostics.append(rejection)
		else:
			result.definitions.append(definition)
	return result

static func _diagnostic(code: String, message: String, source_id: String, resource_id: int, build_id: String, path_index: int, segment_index: int, offset: int) -> PathSetupDiagnostic:
	var result := PathSetupDiagnostic.new()
	result.code = code
	result.source_id = source_id
	result.resource_id = resource_id
	result.build_id = build_id
	result.path_index = path_index
	result.segment_index = segment_index
	result.source_offset = offset
	result.fallback = "Path omitted; other valid paths remain available"
	result.message = message
	return result
