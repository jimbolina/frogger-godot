class_name TickGuardCandidate
extends RefCounted
## Detached state and setup requirements supplied to an optional guard.

var state: GameplayState = null
var visibility_enabled: bool = false
var restricted_contacts: bool = false

## Copies an in-progress state; entity observations are included only when requested.
static func from_state(value: GameplayState, include_entities: bool = false) -> TickGuardCandidate:
	var result := TickGuardCandidate.new()
	result.state = value.copy(include_entities)
	return result

## Builds the setup requirements without passing mutable definitions.
static func from_level(level: LevelDefinition) -> TickGuardCandidate:
	var result := TickGuardCandidate.new()
	if level.entity_collision != null:
		result.visibility_enabled = level.entity_collision.lifecycle != null
		for contact: FormContactDefinition in level.entity_collision.contacts:
			result.restricted_contacts = result.restricted_contacts or not contact.disabled_reason.is_empty()
	return result
