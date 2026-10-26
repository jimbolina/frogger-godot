class_name TickGuard
extends RefCounted
## Optional candidate validation boundary; implementations cannot publish a tick.

enum Phase { SETUP, RESET_WORLD, RESET_POSE, ENTITY_UPDATE, MOVEMENT, BEFORE_CONTACT, CONTACT_WORLD, CONTACT_POSE, FINAL }

## Returns an isolated guard for one run.
func copy() -> TickGuard:
	return TickGuard.new()

## Rejects a phase with a diagnostic, or returns an empty string.
func check(_phase: Phase, _candidate: TickGuardCandidate) -> String:
	return ""
