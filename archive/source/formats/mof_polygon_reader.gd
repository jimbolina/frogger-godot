class_name MofPolygonReader
extends RefCounted
## Decodes one polygon of a model part ([MofPolygon]), keeping stored order.


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
		_read_uv(reader, polygon)
		if reader.read_s16() != 0:
			reader.fail("polygon at %d: the clut word is not zero" % reader.get_position())
		_read_uv(reader, polygon)
		if reader.read_s16() != 0:
			reader.fail("polygon at %d: the texture page word is not zero" % reader.get_position())
		for _i: int in corners - 2:
			_read_uv(reader, polygon)
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


static func _read_uv(reader: ByteReader, polygon: MofPolygon) -> void:
	polygon.uvs.append(reader.read_u8())
	polygon.uvs.append(reader.read_u8())
