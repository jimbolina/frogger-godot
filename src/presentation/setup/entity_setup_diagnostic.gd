class_name EntitySetupDiagnostic
extends RefCounted
## A source-located entity rejection or inspection limitation.

var code: String = ""
var severity: String = "warning"
var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var entity_index: int = -1
var form_id: int = -1
var form_name: String = ""
var source_offset: int = -1
var message: String = ""
var fallback: String = ""

## Returns an independent diagnostic value.
func copy() -> EntitySetupDiagnostic:
	var result := EntitySetupDiagnostic.new()
	result.code = code
	result.severity = severity
	result.source_id = source_id
	result.build_id = build_id
	result.resource_id = resource_id
	result.entity_index = entity_index
	result.form_id = form_id
	result.form_name = form_name
	result.source_offset = source_offset
	result.message = message
	result.fallback = fallback
	return result

## Formats this diagnostic for logs and support reports.
func to_text() -> String:
	var place: String = "%s map resource %d entity %d form %d" % [source_id, resource_id, entity_index, form_id]
	if not form_name.is_empty():
		place += " (%s)" % form_name
	if not build_id.is_empty():
		place += " [%s]" % build_id
	if source_offset >= 0:
		place += " at 0x%X" % source_offset
	return "%s [%s] %s: %s; %s" % [severity, code, place, message, fallback]
