class_name EntityCaveDefinition
extends RefCounted
## Detached Cave frogger-light operands and their frozen precomputed radii.

var min_radius: int = 0
var max_radius: int = 0
var die_speed: int = 0
## Unsigned 32-bit squared radii and per-tick decay from ENTSTRCavCreateFroggerLight.
var light_min_squared: int = 0
var light_max_squared: int = 0
var light_die: int = 0

## Copies authored operands and precomputed values.
func copy() -> EntityCaveDefinition:
	var result := EntityCaveDefinition.new()
	result.min_radius = min_radius
	result.max_radius = max_radius
	result.die_speed = die_speed
	result.light_min_squared = light_min_squared
	result.light_max_squared = light_max_squared
	result.light_die = light_die
	return result
