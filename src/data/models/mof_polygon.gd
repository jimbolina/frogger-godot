class_name MofPolygon
extends Resource
## One polygon of a model part, exactly as the file stores it.
##
## Layout (FrogLord's [code]MRMofPolygon[/code]), all 16-bit values unsigned:
## [codeblock]
## vertex indices, environment normal indices, normal indices   (u16 each)
## textured kinds only:
##     FT4:    s16 image id, then the texture block
##     others: the texture block, then s16 image id
##     texture block: u,v of corner 0   u16 zero   u,v of corner 1   u16 zero
##                    u,v of the remaining corners
## zero bytes up to a multiple of 4
## u8 red, green, blue, code
## [/codeblock]
## Everything is kept in stored order. A quad is stored going round its
## edge, so corner k, texture coordinate k and normal k belong together, and
## its two triangles are corners (0, 1, 3) and (1, 2, 3). FrogLord swaps the
## last two of each list when it loads; this class does not.
##
## A polygon has one colour whatever its kind. Its normals are for lighting,
## which the game does while it runs. The code byte is rewritten by the game
## when it loads a model and means nothing in the file.

## The kind of polygon (see [MofPolygonType]).
@export var type: int = 0
## Index of each corner's vertex in the part's partcel.
@export var vertices := PackedInt32Array()
## Index of each corner's environment normal; empty for most kinds.
@export var environment_normals := PackedInt32Array()
## Index of each lighting normal: one for flat kinds, one per corner for gouraud.
@export var normals := PackedInt32Array()
## u then v of each corner, 0 to 255 across the image; empty when untextured.
@export var uvs := PackedByteArray()
## Global texture id, or -1 when untextured.
@export var image_id: int = -1
## Red, 128 meaning "unchanged".
@export var red: int = 0
## Green.
@export var green: int = 0
## Blue.
@export var blue: int = 0
## The stored code byte.
@export var code: int = 0


## True if the polygon carries a texture.
func is_textured() -> bool:
	return MofPolygonType.is_textured(type)


## True if the polygon has a normal per corner.
func is_gouraud() -> bool:
	return normals.size() > 1


## The normal index that lights corner [param corner], or -1 if the kind has none.
func normal_of_corner(corner: int) -> int:
	if normals.is_empty():
		return -1
	return normals[corner] if normals.size() > 1 else normals[0]
