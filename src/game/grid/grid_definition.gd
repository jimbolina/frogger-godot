class_name GridDefinition
extends RefCounted
## Validated static terrain in integer game units; setup owns construction.

var dimensions: Vector2i = Vector2i.ZERO
var base: Vector2i = Vector2i.ZERO
var stacks: Array[GridStackDefinition] = []
var squares: Array[GridSquareDefinition] = []

## Returns a bounded cell's stack, or null outside the board. Requires validated setup.
func stack_at(cell: Vector2i) -> GridStackDefinition:
	if cell.x < 0 or cell.y < 0 or cell.x >= dimensions.x or cell.y >= dimensions.y:
		return null
	return stacks[cell.y * dimensions.x + cell.x]
