class_name StackLighting
extends RefCounted
## The level-select stack's lights as a [MapLighting]: the ambient and three parallel lights of
## [StackLayout] in its slot order.
##
## Each colour's low byte is taken for all three channels and scaled by 16, as stored light
## values are; each direction is [method StackLayout.light_direction] in Godot space. The level
## select builds its scene lights from it.

## Stored light per colour byte.
const BYTE_SCALE: int = 16


## The stack's ambient and parallel lights.
static func lighting() -> MapLighting:
	var result := MapLighting.new()
	result.ambient = Vector3.ONE * float((StackLayout.AMBIENT_COLOUR & 0xff) * BYTE_SCALE)
	for index: int in StackLayout.LIGHT_COLOURS.size():
		var direction: Vector3i = StackLayout.light_direction(index)
		result.directions.append(GameSpace.normal(direction.x, direction.y, direction.z))
		result.colours.append(Vector3.ONE * float((StackLayout.LIGHT_COLOURS[index] & 0xff) * BYTE_SCALE))
	return result
