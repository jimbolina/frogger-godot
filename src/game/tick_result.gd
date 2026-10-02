class_name TickResult
extends RefCounted
## Ordered control/movement observations, or an error without partial advancement.

var error: String = ""
var tick_index: int = -1
var control_snapshot: RunSnapshot = null
var move_snapshot: RunSnapshot = null
var collision_snapshot: RunSnapshot = null
var camera_snapshot: RunSnapshot = null
var final_snapshot: RunSnapshot = null
## Ordered request names emitted during this tick for presentation consumers.
var events: Array[String] = []
var rng_consumers: Array[String] = []
