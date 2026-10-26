class_name GameplayState
extends RefCounted
## Detached gameplay state composed from independently owned values.

var frog: FrogState = FrogState.new()
var attachment: AttachmentState = AttachmentState.new()
var requests: TickRequests = TickRequests.new()
var diagnostics: TickDiagnostics = TickDiagnostics.new()
var tick_index: int = 0
var entities: EntityRunSnapshot = null
var entity_environment: EntityEnvironmentState = null
var completed: bool = false
var camera: GameplayCameraSnapshot = null
var animation: FrogAnimationState = null
var rng_state: int = 1

## Copies the complete candidate; entity state may be replaced by its own aggregate.
func copy(include_entities: bool = true) -> GameplayState:
	var result := GameplayState.new()
	result.frog = frog.copy()
	result.attachment = attachment.copy()
	result.requests = requests.copy()
	result.diagnostics = diagnostics.copy()
	result.tick_index = tick_index
	result.entities = entities.copy() if include_entities and entities != null else null
	result.entity_environment = entity_environment.copy() if entity_environment != null else null
	result.completed = completed
	result.camera = camera.copy() if camera != null else null
	result.animation = animation.copy() if animation != null else null
	result.rng_state = rng_state
	return result
