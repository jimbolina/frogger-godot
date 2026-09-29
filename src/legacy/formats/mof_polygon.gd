class_name MofPolygon
extends RefCounted
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
var type: int = 0
## Index of each corner's vertex in the part's partcel.
var vertices := PackedInt32Array()
## Index of each corner's environment normal; empty for most kinds.
var environment_normals := PackedInt32Array()
## Index of each lighting normal: one for flat kinds, one per corner for gouraud.
var normals := PackedInt32Array()
## u then v of each corner, 0 to 255 across the image; empty when untextured.
var uvs := PackedByteArray()
## Global texture id, or -1 when untextured.
var image_id: int = -1
## Red, 128 meaning "unchanged".
var red: int = 0
## Green.
var green: int = 0
## Blue.
var blue: int = 0
## The stored code byte.
var code: int = 0


## Reads one polygon of kind [param polygon_type]. Problems are recorded in
## [param reader].
static func read(reader: ByteReader, polygon_type: int) -> MofPolygon:
	var polygon := MofPolygon.new()
	polygon.type = polygon_type
	var corners: int = MofPolygonType.vertex_count(polygon_type)
	for _i: int in corners:
		polygon.vertices.append(reader.read_u16())
	for _i: int in MofPolygonType.environment_normal_count(polygon_type):
		polygon.environment_normals.append(reader.read_u16())
	for _i: int in MofPolygonType.normal_count(polygon_type):
		polygon.normals.append(reader.read_u16())
	if MofPolygonType.is_textured(polygon_type):
		if polygon_type == MofPolygonType.FT4:
			polygon.image_id = reader.read_s16()
		polygon._read_uv(reader)
		if reader.read_s16() != 0:
			reader.fail("polygon at %d: the clut word is not zero" % reader.get_position())
		polygon._read_uv(reader)
		if reader.read_s16() != 0:
			reader.fail("polygon at %d: the texture page word is not zero" % reader.get_position())
		for _i: int in corners - 2:
			polygon._read_uv(reader)
		if polygon_type != MofPolygonType.FT4:
			polygon.image_id = reader.read_s16()
	while reader.get_position() % 4 != 0 and not reader.has_error():
		if reader.read_u8() != 0:
			reader.fail("polygon at %d: padding is not zero" % reader.get_position())
	polygon.red = reader.read_u8()
	polygon.green = reader.read_u8()
	polygon.blue = reader.read_u8()
	polygon.code = reader.read_u8()
	return polygon


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


func _read_uv(reader: ByteReader) -> void:
	uvs.append(reader.read_u8())
	uvs.append(reader.read_u8())
