class_name MapInspectionDefaults
extends RefCounted
## Developer inspection selections for maps with established contact examples.

const ORG1_LOG_ENTITY_ID: int = 12

## Returns an authored identity to prefer, or -1 to retain the viewer's first item.
static func preferred_entity_id(level_code: String) -> int:
	return ORG1_LOG_ENTITY_ID if level_code == "ORG1" else -1
