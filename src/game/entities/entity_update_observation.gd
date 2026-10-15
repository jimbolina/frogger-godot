class_name EntityUpdateObservation
extends RefCounted
## One committed source-ordered visit, before transient flags clear and pose advance.

var entity: EntitySnapshot = null
var previous_flags: int = 0
var rng_state: int = 0
var sound_requests: int = 0
var environment: EntityEnvironmentState = null

## Detaches nested entity, script, animation and shared state.
func copy() -> EntityUpdateObservation:
	var result := EntityUpdateObservation.new()
	result.entity = entity.copy() if entity != null else null
	result.previous_flags = previous_flags
	result.rng_state = rng_state
	result.sound_requests = sound_requests
	result.environment = environment.copy() if environment != null else null
	return result
