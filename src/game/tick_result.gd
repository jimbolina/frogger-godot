class_name TickResult
extends RefCounted
## Ordered control/movement observations, or an error without partial advancement.

var error: String = ""
var tick_index: int = -1
var control_snapshot: GameplayState = null
var move_snapshot: GameplayState = null
var collision_snapshot: GameplayState = null
var camera_snapshot: GameplayState = null
var scripts_snapshot: GameplayState = null
var final_snapshot: GameplayState = null
## Ordered request names emitted during this tick for presentation consumers.
var events: Array[TickEvent] = []
var rng_consumers: Array[String] = []
var entity_contacts: Array[FormReactionResult] = []
var primitive_contacts: Array[EntityPrimitiveContact] = []
