class_name GameplayState
extends RefCounted
## Detached gameplay state composed from independently owned values.

var sound: LogicalSoundState = null
var flow: LevelFlowState = LevelFlowState.new()
var tongue: TongueState = TongueState.new()
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
## Sky backdrop drift; null unless the level uses the Sky theme.
var sky_drift: SkyDriftState = null
## Frozen unsigned32 Game_timer: advanced once per level-play frame and never reset in a level.
var game_timer: int = 0

## Copies the complete candidate; entity state may be replaced by its own aggregate.
func copy(include_entities: bool = true) -> GameplayState:
	var result := GameplayState.new()
	result.sound = sound.copy() if sound != null else null
	result.flow = flow.copy()
	result.tongue = tongue.copy()
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
	result.sky_drift = sky_drift.copy() if sky_drift != null else null
	result.game_timer = game_timer
	return result
