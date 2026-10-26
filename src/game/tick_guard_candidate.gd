class_name TickGuardCandidate
extends RefCounted
## Detached state and setup requirements supplied to an optional guard.

var state: RunSnapshot = null
var visibility_enabled: bool = false
var restricted_contacts: bool = false

## Builds a detached observation of an in-progress state.
static func from_state(value: RunSnapshot) -> TickGuardCandidate:
	var result := TickGuardCandidate.new()
	result.state = value.copy()
	return result

## Builds the setup requirements without passing mutable definitions.
static func from_level(level: LevelDefinition) -> TickGuardCandidate:
	var result := TickGuardCandidate.new()
	if level.entity_collision != null:
		result.visibility_enabled = level.entity_collision.lifecycle != null
		for contact: FormContactDefinition in level.entity_collision.contacts:
			result.restricted_contacts = result.restricted_contacts or not contact.disabled_reason.is_empty()
	return result
