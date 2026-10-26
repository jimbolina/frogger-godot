class_name TickRequests
extends RefCounted
## Logical output requests and cumulative request counters.

var animation_requests: int = 0
var sound_requests: int = 0
var score_requests: int = 0
var life_decrement_requested: bool = false
var game_mode_request: int = -1
var last_animation_request: int = -1
var death_fire_requested: bool = false
var death_scale_colour: Vector3i = Vector3i(-1, -1, -1)

## Returns an independently mutable copy of every value.
func copy() -> TickRequests:
	var result := TickRequests.new()
	result.animation_requests = animation_requests
	result.sound_requests = sound_requests
	result.score_requests = score_requests
	result.life_decrement_requested = life_decrement_requested
	result.game_mode_request = game_mode_request
	result.last_animation_request = last_animation_request
	result.death_fire_requested = death_fire_requested
	result.death_scale_colour = death_scale_colour
	return result
