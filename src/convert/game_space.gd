class_name GameSpace
extends RefCounted
## Turns positions and directions of the original game into Godot's.
##
## The original measures in whole units, 256 to a grid square, with x to the
## right, y [b]down[/b] and z away from the viewer. Godot has y up and looks
## along minus z. Turning the game's space half a turn about the x axis gives
## Godot's: [code](x, y, z)[/code] becomes [code](x, -y, -z)[/code]. Being a
## turn and not a mirror image, it leaves the order of a polygon's corners as
## it is: a face that shows its front in the game shows its front here.
##
## One grid square is one Godot unit. The game's own logic keeps the original
## whole units; only what is drawn is converted.

## Game units in one grid square.
const UNITS_PER_SQUARE: int = 256
## Length of a normal of length one, as stored.
const NORMAL_ONE: int = 4096


## The Godot position of game position ([param x], [param y], [param z]).
static func position(x: int, y: int, z: int) -> Vector3:
	return Vector3(x, -y, -z) / UNITS_PER_SQUARE


## The Godot direction of a stored normal.
static func normal(x: int, y: int, z: int) -> Vector3:
	return Vector3(x, -y, -z) / NORMAL_ONE


## The game position nearest to Godot position [param at].
static func to_game(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x * UNITS_PER_SQUARE), roundi(-at.y * UNITS_PER_SQUARE), roundi(-at.z * UNITS_PER_SQUARE))
