class_name EntityUpdateResult
extends RefCounted
## Detached candidate script update, ordered requests and immediate frog effect.

var runtime: EntityScriptRuntime = null
var runtime_error: String = ""
var pop_started: bool = false
var error: String = ""
var script_state: EntityScriptState = null
var animation: EntityAnimationState = null
var random: SourceRandom = null
var matrix12: PackedInt32Array = PackedInt32Array()
var requests: Array[TickEvent] = []
var path_active_request: int = -1
var script_ended: bool = false
var entity_flags: int = 0
var environment: EntityEnvironmentState = null
var checkpoint_collision_changed: bool = false
var drown: bool = false
var frog_deaths: PackedInt32Array = PackedInt32Array()
var effects: Array[EntityScriptEffect] = []

## Retains the established notification projection and source effect order.
func add_request(request: TickEvent) -> void:
	if runtime != null and runtime_error.is_empty():
		runtime_error = runtime.sound(request, random, Vector3i(matrix12[9], matrix12[10], matrix12[11]))
	requests.append(request)
	var effect: EntityScriptEffect = EntityScriptEffect.event(request)
	if runtime != null:
		runtime.events.append(request.for_entity(runtime.entity_index))
		if request.kind == TickEvent.Kind.SOUND:
			runtime.state.requests.sound_requests += 1
		effect.applied = true
	effects.append(effect)

## Records a frog death at its position among script and callback notifications.
func add_death(animation_id: int) -> void:
	frog_deaths.append(animation_id)
	var effect: EntityScriptEffect = EntityScriptEffect.death(animation_id)
	if runtime != null:
		runtime.frog.kill(runtime.state, animation_id, false, runtime.events)
		effect.applied = true
	effects.append(effect)

## Executes forced movement at its source position on an aggregate candidate.
func add_ejection(delta: int, duration: int) -> void:
	var effect: EntityScriptEffect = EntityScriptEffect.ejection(delta, duration)
	if runtime != null:
		runtime_error = runtime.frog.eject(runtime.state, delta, duration, runtime.events)
		effect.applied = true
	effects.append(effect)
