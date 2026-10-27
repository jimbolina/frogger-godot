class_name EntityForestDefinition
extends RefCounted
## Authored Forest subtype operands resolved from supplied entity payloads.

var release_distance: int = 0
var swarm_speed: int = 0
var run_time: int = 0
var roll_time: int = 0
var run_speed: int = 0
var roll_speed: int = 0

## Detaches the authored operands retained by a gameplay run.
func copy() -> EntityForestDefinition:
	var result := EntityForestDefinition.new()
	result.release_distance = release_distance
	result.swarm_speed = swarm_speed
	result.run_time = run_time
	result.roll_time = roll_time
	result.run_speed = run_speed
	result.roll_speed = roll_speed
	return result
