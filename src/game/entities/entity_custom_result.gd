class_name EntityCustomResult
extends RefCounted
## Private custom-update outputs for the aggregate entity visit.

var path_active_request: int = -1
var path_reset_requested: bool = false
var death_animation: int = -1
var error: String = ""
var entity: EntitySnapshot = null
var environment: EntityEnvironmentState = null
var random: SourceRandom = null
