class_name EntityUpdateResult
extends RefCounted
## Detached candidate script update, ordered requests and immediate frog effect.

var error: String = ""
var script_state: EntityScriptState = null
var animation: EntityAnimationState = null
var random: SourceRandom = null
var matrix12: PackedInt32Array = PackedInt32Array()
var requests: Array[TickEvent] = []
var path_active_request: int = -1
var script_ended: bool = false
var drown: bool = false
