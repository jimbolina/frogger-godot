class_name MapFile
extends RefCounted
## Bounded reader for final PC FROG 2.00 maps. Coordinates stay in game units.

const TYPE_NAMES: Array[String] = ["F3", "F4", "FT3", "FT4", "G3", "G4", "GT3", "GT4", "G2"]
const TYPE_SIZES: Array[int] = [12, 12, 28, 28, 20, 24, 36, 40, 12]
const CORNERS: Array[int] = [3, 4, 3, 4, 3, 4, 3, 4, 2]
## Failure reason, or empty on success.
var error: String = ""
## Nonfatal format observations.
var warnings: Array[String] = []
## File length and version.
var size: int = 0
var version: String = ""
## Raw coordinates.
var vertices: Array[Vector3i] = []
## Polygons in type order, retaining unreferenced polygons.
var polygons: Array[MapPolygon] = []
## Visible groups followed by the invisible group.
var groups: Array[MapGroup] = []
var group_dimensions: Vector2i = Vector2i.ZERO
var group_size: Vector2i = Vector2i.ZERO
var group_base: Vector3i = Vector3i.ZERO
## Stored lights and animation tracks.
var lights: Array[MapLight] = []
var animations: Array[MapAnimation] = []
## Bounded entity payloads, without gameplay decoding.
var entities: Array[MapEntitySpan] = []
## General settings.
var general: MapGeneral = MapGeneral.new()
## Packet bounds and retained gameplay headers.
var packets: Dictionary[String, MapPacket] = {}
var polygon_counts: PackedInt32Array = PackedInt32Array()
var polygon_pointers: PackedInt32Array = PackedInt32Array()
var _bytes: PackedByteArray
var _polygon_by_offset: Dictionary[int, int] = {}

## Parses a final map, checking error before using the result.
static func read(bytes: PackedByteArray) -> MapFile:
	var map := MapFile.new()
	map._bytes = bytes
	map.size = bytes.size()
	map._read()
	return map

func _range(offset: int, length: int, label: String, end: int = -1) -> bool:
	var bound: int = size if end < 0 else end
	if offset < 0 or length < 0 or offset > bound or length > bound - offset:
		if error.is_empty():
			error = "%s exceeds its bounded file span" % label
		return false
	return true

func _id(offset: int) -> String:
	return _bytes.slice(offset, offset + 4).get_string_from_ascii()

func _vec(offset: int) -> Vector3i:
	return Vector3i(_bytes.decode_s16(offset), _bytes.decode_s16(offset + 2), _bytes.decode_s16(offset + 4))

func _packet(offset: int, identifier: String) -> void:
	if not _range(offset, 4, identifier):
		return
	if _id(offset) != identifier:
		error = "Expected %s at %d" % [identifier, offset]
		return
	for existing: MapPacket in packets.values():
		if existing.source_offset == offset:
			error = "Duplicate map packet offset"
			return
	var packet := MapPacket.new()
	packet.identifier = identifier
	packet.source_offset = offset
	packet.end_offset = size
	packets[identifier] = packet

func _read() -> void:
	if not _range(0, 100, "map header"):
		return
	if _id(0) != "FROG":
		error = "Not a FROG map"
		return
	version = _id(8)
	if version != "2.00":
		error = "Unsupported map version %s" % version
		return
	if _bytes.decode_u32(4) != size:
		warnings.append("Reported map length differs from supplied bytes")
	var names: Array[String] = ["GENE", "GRAP", "FORM", "EMTP", "ZONE", "PATH"]
	for i: int in names.size():
		_packet(_bytes.decode_u32(76 + i * 4), names[i])
	if not error.is_empty():
		return
	var grap: int = packets["GRAP"].source_offset
	if not _range(grap, 28, "GRAP"):
		return
	var graphics: Array[String] = ["LITE", "GROU", "POLY", "VRTX", "GRID", "ANIM"]
	for i: int in graphics.size():
		_packet(_bytes.decode_u32(grap + 4 + i * 4), graphics[i])
	if not error.is_empty():
		return
	for packet: MapPacket in packets.values():
		for other: MapPacket in packets.values():
			if other.source_offset > packet.source_offset:
				packet.end_offset = mini(packet.end_offset, other.source_offset)
		packet.raw_header = _bytes.slice(packet.source_offset, mini(packet.source_offset + 64, packet.end_offset))
	_read_general()
	if not error.is_empty():
		return
	_read_vertices()
	if not error.is_empty():
		return
	_read_polygons()
	if not error.is_empty():
		return
	_read_groups()
	if not error.is_empty():
		return
	_read_lights()
	if not error.is_empty():
		return
	_read_animations()
	if not error.is_empty():
		return
	_read_retained()

func _read_general() -> void:
	var p: MapPacket = packets["GENE"]
	var o: int = p.source_offset + 4
	if not _range(o, 44, "GENE", p.end_offset):
		return
	for i: int in 22:
		general.raw_words.append(_bytes.decode_u16(o + i * 2) if i < 10 else _bytes.decode_s16(o + i * 2))
	general.start_grid = Vector2i(general.raw_words[0], general.raw_words[1])
	general.start_rotation = general.raw_words[2]
	general.theme = general.raw_words[3]
	general.time_limit = general.raw_words[4]
	general.camera_source_offset = _vec(o + 20)
	general.camera_target_offset = _vec(o + 28)
	if general.start_rotation > 3 or general.theme >= FroggerIds.THEMES.size():
		error = "Invalid GENE rotation or theme"

func _read_vertices() -> void:
	var p: MapPacket = packets["VRTX"]
	var o: int = p.source_offset + 4
	if not _range(o, 4, "VRTX", p.end_offset):
		return
	p.count = _bytes.decode_u16(o)
	if not _range(o + 4, p.count * 8, "vertex records", p.end_offset):
		return
	for i: int in p.count:
		vertices.append(_vec(o + 4 + i * 8))

func _read_polygons() -> void:
	var p: MapPacket = packets["POLY"]
	var o: int = p.source_offset + 4
	if not _range(o, 56, "POLY header", p.end_offset):
		return
	var ranges: Array[Vector2i] = []
	for t: int in 9:
		var range_count: int = _bytes.decode_u16(o + t * 2)
		if range_count == 0:
			continue
		var range_start: int = _bytes.decode_u32(o + 20 + t * 4)
		var range_size: int = range_count * TYPE_SIZES[t]
		if range_start < o + 56 or not _range(range_start, range_size, "polygon records", p.end_offset):
			error = "Invalid %s polygon block" % TYPE_NAMES[t]
			return
		for previous: Vector2i in ranges:
			if range_start < previous.y and previous.x < range_start + range_size:
				error = "Polygon type block byte ranges overlap"
				return
		ranges.append(Vector2i(range_start, range_start + range_size))
	for t: int in 9:
		var count: int = _bytes.decode_u16(o + t * 2)
		var start: int = _bytes.decode_u32(o + 20 + t * 4)
		polygon_counts.append(count)
		polygon_pointers.append(start)
		if count == 0:
			continue
		if start < o + 56 or not _range(start, count * TYPE_SIZES[t], "polygon records", p.end_offset):
			error = "Invalid %s polygon block" % TYPE_NAMES[t]
			return
		for j: int in count:
			var poly := MapPolygon.new()
			poly.type_index = t
			poly.index = polygons.size()
			poly.source_offset = start + j * TYPE_SIZES[t]
			var at: int = poly.source_offset
			if _polygon_by_offset.has(at):
				error = "Polygon blocks overlap"
				return
			for k: int in (TYPE_SIZES[t] >> 1):
				poly.raw_words.append(_bytes.decode_u16(at + k * 2))
			for k: int in CORNERS[t]:
				var vertex: int = _bytes.decode_u16(at + k * 2)
				if vertex >= vertices.size():
					error = "Polygon vertex index exceeds VRTX count"
					return
				poly.vertex_indices.append(vertex)
			var color_at: int = at + (4 if t == 8 else 8)
			if t in [2, 3, 6, 7]:
				poly.flags = _bytes.decode_u16(at + 8)
				if poly.flags & ~7:
					warnings.append("Polygon %d has unknown texture flags 0x%X" % [poly.index, poly.flags])
				poly.texture_id = _bytes.decode_s16(at + 18)
				var uv_offsets: Array[int] = [12, 16, 20, 22]
				for k: int in CORNERS[t]:
					poly.uvs.append(Vector2(_bytes[at + uv_offsets[k]], _bytes[at + uv_offsets[k] + 1]) / 255.0)
				color_at = at + 24
			var color_count: int = CORNERS[t] if t >= 4 else 1
			for k: int in color_count:
				var c: int = color_at + k * 4
				poly.colors.append(Color8(_bytes[c], _bytes[c + 1], _bytes[c + 2]))
			_polygon_by_offset[at] = poly.index
			polygons.append(poly)
	p.count = polygons.size()

func _read_groups() -> void:
	var p: MapPacket = packets["GROU"]
	var o: int = p.source_offset + 4
	if not _range(o, 16, "GROU header", p.end_offset):
		return
	group_base = _vec(o)
	group_dimensions = Vector2i(_bytes.decode_u16(o + 8), _bytes.decode_u16(o + 10))
	group_size = Vector2i(_bytes.decode_u16(o + 12), _bytes.decode_u16(o + 14))
	p.count = group_dimensions.x * group_dimensions.y + 1
	if not _range(o + 16, p.count * 72, "group records", p.end_offset):
		return
	var referenced: Dictionary[int, bool] = {}
	for i: int in p.count:
		var group := MapGroup.new()
		group.source_offset = o + 16 + i * 72
		group.visible = i < p.count - 1
		if group.visible:
			@warning_ignore("integer_division")
			group.coordinates = Vector2i(i % group_dimensions.x, i / group_dimensions.x)
		else:
			group.coordinates = Vector2i(-1, -1)
		for t: int in 9:
			var count: int = _bytes[group.source_offset + t]
			var ptr: int = _bytes.decode_u32(group.source_offset + 12 + t * 4)
			group.counts.append(count)
			group.pointers.append(ptr)
			if count == 0:
				continue
			if not _polygon_by_offset.has(ptr):
				error = "Group pointer does not identify a polygon"
				return
			var index: int = _polygon_by_offset[ptr]
			for k: int in count:
				if index + k >= polygons.size() or polygons[index + k].type_index != t:
					error = "Group range crosses polygon type bounds"
					return
				group.polygon_indices.append(index + k)
				referenced[index + k] = true
				polygons[index + k].visible = group.visible
		group.static_entity_pointer = _bytes.decode_u32(group.source_offset + 48)
		if group.static_entity_pointer != 0:
			if group.static_entity_pointer < o + 16 + p.count * 72:
				error = "Static entity pointer overlaps group records"
				return
			if not _range(group.static_entity_pointer, 0, "static entity list", p.end_offset):
				return
		groups.append(group)
	if referenced.size() != polygons.size():
		warnings.append("%d polygons are unreferenced by groups" % (polygons.size() - referenced.size()))

func _read_lights() -> void:
	var p: MapPacket = packets["LITE"]
	var o: int = p.source_offset + 4
	if not _range(o, 4, "LITE count", p.end_offset):
		return
	p.count = _bytes.decode_u32(o)
	if not _range(o + 4, p.count * 40, "lights", p.end_offset):
		return
	for i: int in p.count:
		var at: int = o + 4 + i * 40
		var light := MapLight.new()
		light.source_offset = at
		light.category = _bytes[at]
		light.priority = _bytes[at + 1]
		light.parent_id = _bytes.decode_u16(at + 2)
		light.light_type = _bytes[at + 4]
		light.color_word = _bytes.decode_u32(at + 8)
		light.color = Color8(_bytes[at + 8], _bytes[at + 9], _bytes[at + 10])
		light.position = _vec(at + 12)
		light.direction = _vec(at + 20)
		light.attribute_0 = _bytes.decode_u16(at + 28)
		light.attribute_1 = _bytes.decode_u16(at + 30)
		light.enabled = light.category == 1
		lights.append(light)

func _read_animations() -> void:
	var p: MapPacket = packets["ANIM"]
	var o: int = p.source_offset + 4
	if not _range(o, 8, "ANIM header", p.end_offset):
		return
	p.count = _bytes.decode_u32(o)
	var start: int = _bytes.decode_u32(o + 4)
	if start < o + 8:
		error = "Animation records overlap ANIM header"
		return
	if not _range(start, p.count * 32, "animation records", p.end_offset):
		return
	for i: int in p.count:
		var at: int = start + i * 32
		var anim := MapAnimation.new()
		anim.source_offset = at
		anim.raw_header = _bytes.slice(at, at + 32)
		anim.delta_u = _bytes.decode_s8(at)
		anim.delta_v = _bytes.decode_s8(at + 1)
		anim.uv_frame_count = _bytes.decode_u16(at + 2)
		anim.initial_u = _bytes[at + 4]
		anim.initial_v = _bytes[at + 5]
		anim.initial_uv_count = _bytes.decode_u16(at + 6)
		anim.initial_cel = _bytes.decode_u16(at + 10)
		anim.frames_per_texture = _bytes.decode_u16(at + 16)
		anim.initial_cel_count = _bytes.decode_u16(at + 18)
		anim.type = _bytes.decode_u16(at + 20)
		if anim.type < 1 or anim.type > 3:
			error = "Unknown animation type"
			return
		var cels: int = _bytes.decode_u16(at + 8) if anim.type & 2 else 0
		var cel_ptr: int = _bytes.decode_u32(at + 12)
		if anim.type & 2 and (cels == 0 or anim.initial_cel >= cels):
			error = "Texture animation requires cels and a bounded initial cel"
			return
		if cels > 0:
			if cel_ptr < start + p.count * 32:
				error = "Animation textures overlap record headers"
				return
			if not _range(cel_ptr, cels * 2, "animation textures", p.end_offset):
				return
			for k: int in cels:
				anim.texture_ids.append(_bytes.decode_u16(cel_ptr + k * 2))
		var targets: int = _bytes.decode_u16(at + 22)
		var target_ptr: int = _bytes.decode_u32(at + 28)
		if targets > 0:
			if target_ptr < start + p.count * 32:
				error = "Animation targets overlap record headers"
				return
			if not _range(target_ptr, targets * 12, "animation targets", p.end_offset):
				return
			anim.raw_targets = _bytes.slice(target_ptr, target_ptr + targets * 12)
			for k: int in targets:
				var ptr: int = _bytes.decode_u32(target_ptr + k * 12)
				if not _polygon_by_offset.has(ptr):
					error = "Animation target does not identify a polygon"
					return
				if polygons[_polygon_by_offset[ptr]].type_index not in [2, 3, 6, 7]:
					error = "Animation targets an untextured polygon"
					return
				anim.target_pointers.append(ptr)
				anim.target_polygon_indices.append(_polygon_by_offset[ptr])
		animations.append(anim)

func _read_retained() -> void:
	for name: String in ["FORM", "EMTP", "ZONE", "PATH"]:
		var p: MapPacket = packets[name]
		var o: int = p.source_offset + (8 if name == "EMTP" else 4)
		if name == "EMTP":
			if not _range(p.source_offset + 4, 4, "EMTP length field", p.end_offset):
				return
			var length: int = _bytes.decode_u32(p.source_offset + 4)
			if length < 12:
				error = "EMTP length is smaller than its header"
				return
			if not _range(p.source_offset, length, "EMTP length", p.end_offset):
				return
			p.end_offset = p.source_offset + length
		if not _range(o, 4, name + " count", p.end_offset):
			return
		p.count = _bytes.decode_u16(o) if name in ["FORM", "EMTP"] else _bytes.decode_u32(o)
		if not _range(o + 4, p.count * 4, name + " pointer table", p.end_offset):
			return
		for i: int in p.count:
			var ptr: int = _bytes.decode_u32(o + 4 + i * 4)
			if p.offsets.has(ptr) or ptr < o + 4 + p.count * 4 or not _range(ptr, 4, name + " record", p.end_offset):
				error = "Invalid %s record pointer" % name
				return
			p.offsets.append(ptr)
		if name == "EMTP":
			for i: int in p.count:
				var at: int = p.offsets[i]
				var end: int = p.end_offset
				for ptr: int in p.offsets:
					if ptr > at:
						end = mini(end, ptr)
				if not _range(at, 24, "entity identity", end):
					return
				var entity := MapEntitySpan.new()
				entity.source_offset = at
				entity.end_offset = end
				entity.form_grid_id = _bytes.decode_u16(at)
				entity.unique_id = _bytes.decode_u16(at + 2)
				entity.form_id = _bytes.decode_u16(at + 4)
				entity.flags = _bytes.decode_u16(at + 6)
				entity.payload = _bytes.slice(at + 24, end)
				entities.append(entity)
	var grid: MapPacket = packets["GRID"]
	var o: int = grid.source_offset + 4
	if not _range(o, 8, "GRID header", grid.end_offset):
		return
	grid.dimensions = Vector2i(_bytes.decode_u16(o), _bytes.decode_u16(o + 2))
	grid.cell_size = Vector2i(_bytes.decode_u16(o + 4), _bytes.decode_u16(o + 6))
	grid.count = grid.dimensions.x * grid.dimensions.y
	if not _range(o + 8, grid.count * 4, "grid stacks", grid.end_offset):
		return
	for i: int in grid.count:
		var at: int = o + 8 + i * 4
		if _bytes.decode_u16(at + 2) != grid.grid_square_count:
			error = "Grid stack index is not contiguous"
			return
		grid.grid_square_count += _bytes[at]
	if not _range(o + 8 + grid.count * 4, grid.grid_square_count * 8, "grid squares", grid.end_offset):
		return
