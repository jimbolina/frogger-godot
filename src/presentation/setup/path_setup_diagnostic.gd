class_name PathSetupDiagnostic
extends RefCounted
## A source-located rejection or fallback while preparing gameplay paths.

var code: String = ""
var severity: String = "warning"
var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var path_index: int = -1
var segment_index: int = -1
var source_offset: int = -1
var fallback: String = ""
var message: String = ""

## Formats the diagnostic for logs and support reports.
func to_text() -> String:
	var place: String = "%s map resource %d path %d" % [source_id, resource_id, path_index]
	if not build_id.is_empty():
		place = "%s (%s)" % [place, build_id]
	if segment_index >= 0:
		place += " segment %d" % segment_index
	if source_offset >= 0:
		place += " at 0x%X" % source_offset
	return "%s [%s] %s: %s; %s" % [severity, code, place, message, fallback]
