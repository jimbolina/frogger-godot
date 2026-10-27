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
## Source-ordered FORM collision grids, including empty entries.
var forms: Array[MapForm] = []
## Source-ordered camera zones; malformed records retain diagnostics.
var zones: Array[MapZone] = []
## Ordered collision stacks and layers, without gameplay conversion.
var grid_stacks: Array[MapGridStack] = []
var grid_squares: Array[MapGridSquare] = []
## Source-ordered paths with raw segment data.
var paths: Array[MapPath] = []
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
	if not error.is_empty():
		return
	_read_zones()
	if not error.is_empty():
		return
	_read_paths()

func _read_zones() -> void:
	var packet: MapPacket = packets["ZONE"]
	for index: int in packet.count:
		var at: int = packet.offsets[index]
		var end: int = packet.end_offset
		for later: int in packet.offsets:
			if later > at:
				end = mini(end, later)
		var zone := MapZone.new()
		zone.zone_index = index
		zone.source_offset = at
		zone.end_offset = end
		zones.append(zone)
		var table_end: int = packet.source_offset + 8 + packet.count * 4
		if at < table_end or at >= packet.end_offset or packet.offsets.count(at) > 1:
			zone.diagnostics.append("ZONE record %d has invalid or duplicate pointer %d" % [index, at])
			continue
		if at + 84 > end:
			zone.diagnostics.append("ZONE record %d at %d lacks its 84-byte camera prefix" % [index, at])
			continue
		zone.zone_type = _bytes.decode_u16(at)
		var region_count: int = _bytes.decode_u16(at + 2)
		for axis: int in 4:
			zone.bounds.append(_bytes.decode_s16(at + 4 + axis * 2))
		zone.region_pointer = _bytes.decode_u32(at + 12)
		zone.camera_flags = _bytes.decode_u16(at + 16)
		zone.camera_direction = _bytes.decode_s16(at + 18)
		for vector_index: int in 8:
			zone.camera_offsets.append(_vec(at + 20 + vector_index * 8))
		if region_count == 0:
			continue
		if zone.region_pointer < at + 84 or zone.region_pointer > end or region_count * 8 > end - zone.region_pointer:
			zone.diagnostics.append("ZONE record %d at %d has out-of-bounds region pointer %d/count %d" % [index, at, zone.region_pointer, region_count])
			continue
		for region_index: int in region_count:
			var region := MapZoneRegion.new()
			region.region_index = region_index
			region.source_offset = zone.region_pointer + region_index * 8
			for axis: int in 4:
				region.bounds.append(_bytes.decode_s16(region.source_offset + axis * 2))
			zone.regions.append(region)

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
			if t != 8:
				for k: int in 4:
					poly.grid_vertex_indices.append(_bytes.decode_u16(at + k * 2))
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
			if name == "ZONE":
				p.offsets.append(ptr)
				continue
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
	_read_forms()
	if not error.is_empty():
		return
	var grid: MapPacket = packets["GRID"]
	var o: int = grid.source_offset + 4
	if not _range(o, 8, "GRID header", grid.end_offset):
		return
	grid.dimensions = Vector2i(_bytes.decode_u16(o), _bytes.decode_u16(o + 2))
	grid.cell_size = Vector2i(_bytes.decode_u16(o + 4), _bytes.decode_u16(o + 6))
	if grid.dimensions.x > 0 and grid.dimensions.y > 0:
		if grid.dimensions.x % 2 != 0 or grid.dimensions.y % 2 != 0:
			warnings.append("GRID has odd dimensions; source world-bitmask interpolation retains its half-cell offset")
		if grid.cell_size != Vector2i(256, 256):
			warnings.append("GRID has non-256 cell sizes; gameplay setup requires 256-unit cells")
	grid.count = grid.dimensions.x * grid.dimensions.y
	if not _range(o + 8, grid.count * 4, "grid stacks", grid.end_offset):
		return
	for i: int in grid.count:
		var at: int = o + 8 + i * 4
		var stack := MapGridStack.new()
		stack.source_offset = at
		stack.square_count = _bytes[at]
		stack.cliff_height_byte = _bytes[at + 1]
		stack.first_square_index = _bytes.decode_u16(at + 2)
		if _bytes.decode_u16(at + 2) != grid.grid_square_count:
			error = "Grid stack index is not contiguous"
			return
		grid.grid_square_count += _bytes[at]
		grid_stacks.append(stack)
	if not _range(o + 8 + grid.count * 4, grid.grid_square_count * 8, "grid squares", grid.end_offset):
		return
	for i: int in grid.grid_square_count:
		var at: int = o + 8 + grid.count * 4 + i * 8
		var square := MapGridSquare.new()
		square.source_offset = at
		square.flags = _bytes.decode_u32(at)
		if square.flags & ~0xFDFFF:
			warnings.append("Grid square %d has unknown flags 0x%X" % [i, square.flags])
		square.polygon_pointer = _bytes.decode_u32(at + 4)
		if not _polygon_by_offset.has(square.polygon_pointer):
			error = "Grid square pointer does not identify a polygon"
			return
		square.polygon_index = _polygon_by_offset[square.polygon_pointer]
		grid_squares.append(square)

func _read_forms() -> void:
	var packet: MapPacket = packets["FORM"]
	for index: int in packet.count:
		var at: int = packet.offsets[index]
		var end: int = packet.end_offset
		for ptr: int in packet.offsets:
			if ptr > at:
				end = mini(end, ptr)
		if not _range(at, 12, "FORM header", end):
			return
		var form := MapForm.new()
		form.form_index = index
		form.source_offset = at
		form.end_offset = end
		form.data_count = _bytes.decode_u16(at)
		form.stored_max_y = _bytes.decode_s16(at + 2)
		form.dimensions = Vector2i(_bytes.decode_s16(at + 4), _bytes.decode_s16(at + 6))
		form.offsets = Vector2i(_bytes.decode_s16(at + 8), _bytes.decode_s16(at + 10))
		if not _range(at + 12, form.data_count * 4, "FORM data pointers", end):
			return
		if form.data_count == 0:
			if form.dimensions.x <= 0 or form.dimensions.y <= 0:
				form.diagnostics.append("Empty FORM retains nonpositive dimensions")
			forms.append(form)
			continue
		if form.data_count != 1:
			form.diagnostics.append("Multiple FORM_DATA records; gameplay uses only the first")
		if form.dimensions.x <= 0 or form.dimensions.y <= 0:
			form.diagnostics.append("FORM_DATA has nonpositive grid dimensions")
		var data_pointers := PackedInt32Array()
		for data_index: int in form.data_count:
			var pointer: int = _bytes.decode_u32(at + 12 + data_index * 4)
			if data_pointers.has(pointer) or pointer < at + 12 + form.data_count * 4 or not _range(pointer, 12, "FORM_DATA header", end):
				error = "Invalid FORM_DATA record pointer"
				return
			data_pointers.append(pointer)
		for data_index: int in form.data_count:
			var data_at: int = data_pointers[data_index]
			var data_end: int = end
			for pointer: int in data_pointers:
				if pointer > data_at:
					data_end = mini(data_end, pointer)
			if not _range(data_at, 12, "FORM_DATA bounded header", data_end):
				return
			var entry := MapFormData.new()
			entry.source_offset = data_at
			entry.end_offset = data_end
			entry.height_type = _bytes.decode_u16(data_at)
			entry.height = _bytes.decode_s16(data_at + 2)
			entry.flags_pointer = _bytes.decode_u32(data_at + 4)
			entry.heights_pointer = _bytes.decode_u32(data_at + 8)
			if entry.height_type != 0:
				entry.diagnostics.append("Unsupported FORM_DATA height mode %d" % entry.height_type)
			if entry.heights_pointer != data_at + 2:
				entry.diagnostics.append("FORM_DATA height pointer differs from scalar height")
			if form.dimensions.x > 0 and form.dimensions.y > 0:
				var square_count: int = form.dimensions.x * form.dimensions.y
				if entry.flags_pointer < data_at + 12 or not _range(entry.flags_pointer, square_count * 2, "FORM_DATA grid flags", data_end):
					error = "Invalid FORM_DATA grid flags pointer"
					return
				for square_index: int in square_count:
					entry.grid_flags.append(_bytes.decode_u16(entry.flags_pointer + square_index * 2))
			else:
				if entry.flags_pointer < data_at + 12 or entry.flags_pointer > data_end:
					error = "Invalid FORM_DATA grid flags pointer"
					return
				entry.diagnostics.append("Grid flags unavailable for nonpositive dimensions")
			form.data.append(entry)
		forms.append(form)

func _read_paths() -> void:
	var packet: MapPacket = packets["PATH"]
	var table_end: int = packet.source_offset + 8 + packet.count * 4
	for i: int in packet.count:
		var at: int = packet.offsets[i]
		var limit: int = packet.end_offset
		for pointer: int in packet.offsets:
			if pointer > at:
				limit = mini(limit, pointer)
		if at < table_end or not _range(at, 8, "PATH record", limit):
			error = "Invalid PATH record %d" % i
			return
		var path := MapPath.new()
		path.path_index = i
		path.source_offset = at
		path.entity_list_pointer = _bytes.decode_u32(at)
		if path.entity_list_pointer != 0:
			var list_at: int = path.entity_list_pointer
			while true:
				if list_at < 0 or list_at + 2 > _bytes.size():
					path.entity_list_error = "PATH entity list is outside map storage or lacks its terminator"
					break
				var entity_index: int = _bytes.decode_s16(list_at)
				list_at += 2
				if entity_index == -1:
					break
				if entity_index < 0:
					path.entity_list_error = "PATH entity list has a negative authored index"
					break
				path.entity_indices.append(entity_index)
		var count: int = _bytes.decode_u32(at + 4)
		if not _range(at + 8, count * 4, "PATH segment pointer table", limit):
			return
		var payload_start: int = at + 8 + count * 4
		var pointers: Array[int] = []
		for j: int in count:
			var pointer: int = _bytes.decode_u32(at + 8 + j * 4)
			if pointers.has(pointer) or pointer < payload_start or not _range(pointer, 8, "PATH segment", limit):
				error = "Invalid PATH segment pointer at path %d segment %d" % [i, j]
				return
			pointers.append(pointer)
		for j: int in count:
			var segment_at: int = pointers[j]
			var segment_limit: int = limit
			for pointer: int in pointers:
				if pointer > segment_at:
					segment_limit = mini(segment_limit, pointer)
			var segment := MapPathSegment.new()
			segment.segment_type = _bytes.decode_u32(segment_at)
			segment.length = _bytes.decode_s32(segment_at + 4)
			segment.source_offset = segment_at
			var required: int = 8
			match segment.segment_type:
				0: required = 120
				1: required = 40
				2: required = 24
			if not _range(segment_at, required, "PATH segment payload", segment_limit):
				return
			segment.end_offset = segment_at + required if segment.segment_type <= 2 else segment_limit
			match segment.segment_type:
				0:
					for k: int in 12:
						segment.matrix.append(_bytes.decode_s32(segment_at + 8 + k * 4))
					for k: int in 4:
						segment.smooth_t.append(_bytes.decode_s32(segment_at + 56 + k * 4))
					for k: int in 12:
						segment.smooth_c.append(_bytes.decode_s32(segment_at + 72 + k * 4))
				1:
					segment.start = _vec(segment_at + 8)
					segment.centre = _vec(segment_at + 16)
					segment.normal = _vec(segment_at + 24)
					segment.radius = _bytes.decode_s32(segment_at + 32)
					segment.pitch = _bytes.decode_s32(segment_at + 36)
				2:
					segment.start = _vec(segment_at + 8)
					segment.end = _vec(segment_at + 16)
				_:
					warnings.append("Unknown PATH segment type %d at path %d segment %d" % [segment.segment_type, i, j])
			path.segments.append(segment)
		paths.append(path)
