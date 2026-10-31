class_name MofPartReader
extends RefCounted
## Decodes one part of a static model ([MofPart]): its header, then what the
## header points at. The pointers are kept here, since they only matter while
## the model is read.

## The part being read.
var part: MofPart
## Where the partcel list starts, from the start of the model. The vector
## pool of a model ends at the first part's list.
var partcels_at: int = 0
## Where the polygon blocks start.
var polygons_at: int = 0
## Where the hilites start, or 0.
var hilites_at: int = 0
## Where the collision primitives start, or 0.
var collprims_at: int = 0
## Where the collision matrices start, or 0.
var matrices_at: int = 0
## Where the texture animation starts, or 0.
var texture_animation_at: int = 0
## Where the flipbook starts, or 0.
var flipbook_at: int = 0


## Reads a part header at the reader's position.
static func read_header(reader: ByteReader, part_index: int) -> MofPartReader:
	var result := MofPartReader.new()
	var record := MofPart.new()
	result.part = record
	record.index = part_index
	record.flags = reader.read_s16()
	record.partcel_count = reader.read_u16()
	record.vertex_count = reader.read_u16()
	record.normal_count = reader.read_u16()
	record.polygon_count = reader.read_u16()
	record.hilite_count = reader.read_u16()
	result.partcels_at = reader.read_u32()
	result.polygons_at = reader.read_u32()
	result.hilites_at = reader.read_u32()
	if reader.read_u32() != 0:
		reader.fail("part %d: the word the game fills in is not zero" % part_index)
	result.collprims_at = reader.read_u32()
	result.matrices_at = reader.read_u32()
	result.texture_animation_at = reader.read_u32()
	result.flipbook_at = reader.read_u32()
	return result


## Reads what the header points at. The vector pool is the bytes from
## [param pool_start] to [param pool_end]. With [param incomplete] set only
## the polygons are read. Problems are recorded in [param reader].
func read_body(reader: ByteReader, pool_start: int, pool_end: int, incomplete: bool) -> void:
	if not incomplete:
		_read_partcels(reader, pool_start, pool_end)
		_read_hilites(reader)
		_read_collprims(reader)
		_read_matrices(reader)
		_read_texture_animations(reader)
		_read_flipbook(reader)
	_read_polygons(reader)
	if reader.has_error():
		return
	for target: MofTextureTarget in part.texture_targets:
		if target.polygon_index < 0 or target.polygon_index >= part.polygons.size():
			target.error = "texture target names unavailable polygon %d" % target.polygon_index
		elif part.polygons[target.polygon_index].type != target.polygon_type or not part.polygons[target.polygon_index].is_textured():
			target.error = "texture target names an incompatible polygon"
	for hilite: MofHilite in part.hilites:
		var limit: int = part.vertex_count if hilite.attach == MofPart.ATTACH_VERTEX else part.polygons.size()
		if hilite.index >= limit:
			reader.fail("part %d: a hilite names item %d of %d" % [part.index, hilite.index, limit])
	var expected_flags: int = MofPart.FLAG_ANIMATED_TEXTURES if part.texture_animation_target_count > 0 else 0
	if part.flags != expected_flags:
		reader.fail("part %d: flags %d, expected %d" % [part.index, part.flags, expected_flags])


func _read_vectors(reader: ByteReader, at: int, count: int, pool_start: int, pool_end: int, what: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count == 0:
		return out
	if at < pool_start or at + 8 * count > pool_end:
		reader.fail("part %d: %s at %d lie outside the vector pool (%d to %d)" % [part.index, what, at, pool_start, pool_end])
		return out
	if (at - pool_start) % 8 != 0:
		reader.fail("part %d: %s at %d are not on an 8-byte step of the vector pool" % [part.index, what, at])
		return out
	out.resize(count * 3)
	for i: int in count:
		out[i * 3] = reader.s16_at(at + i * 8)
		out[i * 3 + 1] = reader.s16_at(at + i * 8 + 2)
		out[i * 3 + 2] = reader.s16_at(at + i * 8 + 4)
	return out


func _read_partcels(reader: ByteReader, pool_start: int, pool_end: int) -> void:
	if part.partcel_count == 0:
		return
	reader.seek(partcels_at)
	var box_offsets := PackedInt32Array()
	for i: int in part.partcel_count:
		var vertices_at: int = reader.read_u32()
		var normals_at: int = reader.read_u32()
		box_offsets.append(reader.read_u32())
		if reader.read_u32() != 0:
			reader.fail("part %d partcel %d: the unused word is not zero" % [part.index, i])
		if reader.has_error():
			return
		var cel := MofPartcel.new()
		cel.vertices = _read_vectors(reader, vertices_at, part.vertex_count, pool_start, pool_end, "vertices")
		cel.normals = _read_vectors(reader, normals_at, part.normal_count, pool_start, pool_end, "normals")
		part.partcels.append(cel)
	var boxes: Dictionary[int, PackedInt32Array] = {}
	for i: int in part.partcel_count:
		var at: int = box_offsets[i]
		if at == 0:
			continue
		if not boxes.has(at):
			var box := PackedInt32Array()
			for corner: int in 8:
				box.append(reader.s16_at(at + corner * 8))
				box.append(reader.s16_at(at + corner * 8 + 2))
				box.append(reader.s16_at(at + corner * 8 + 4))
			boxes[at] = box
		part.partcels[i].bounding_box = boxes[at]
	part.bounding_box_count = boxes.size()


func _read_hilites(reader: ByteReader) -> void:
	if part.hilite_count == 0:
		return
	reader.seek(hilites_at)
	for i: int in part.hilite_count:
		var hilite := MofHilite.new()
		hilite.type = reader.read_u8()
		hilite.attach = reader.read_u8()
		hilite.index = reader.read_u16()
		if reader.read_u32() != 0 or reader.read_u32() != 0:
			reader.fail("part %d hilite %d: the words the game fills in are not zero" % [part.index, i])
		if hilite.attach != MofPart.ATTACH_VERTEX and hilite.attach != MofPart.ATTACH_POLYGON:
			reader.fail("part %d hilite %d: attached to kind %d" % [part.index, i, hilite.attach])
		if reader.has_error():
			return
		part.hilites.append(hilite)


func _read_collprims(reader: ByteReader) -> void:
	if collprims_at == 0:
		return
	reader.seek(collprims_at)
	while not reader.has_error():
		var prim := MofCollprim.new()
		prim.type = reader.read_u16()
		prim.flags = reader.read_u16()
		if reader.read_u32() != 0 or reader.read_u32() != 0:
			reader.fail("part %d: a collision shape's words the game fills in are not zero" % part.index)
		if prim.type > 4:
			reader.fail("part %d: a collision shape of kind %d" % [part.index, prim.type])
		prim.offset = Vector3i(reader.read_s16(), reader.read_s16(), reader.read_s16())
		reader.skip(2)
		prim.radius_squared = reader.read_s32()
		prim.size = Vector3i(reader.read_u16(), reader.read_u16(), reader.read_u16())
		prim.user = reader.read_u16()
		prim.matrix_index = reader.read_s32()
		if reader.has_error():
			return
		part.collprims.append(prim)
		if prim.flags & MofPart.COLLPRIM_LAST != 0:
			return


func _section_after(at: int, candidates: PackedInt32Array) -> int:
	var found: int = -1
	for candidate: int in candidates:
		if candidate > at and (found < 0 or candidate < found):
			found = candidate
	return found


func _read_matrices(reader: ByteReader) -> void:
	if matrices_at == 0:
		return
	var end: int = _section_after(matrices_at, PackedInt32Array([texture_animation_at, flipbook_at, polygons_at]))
	if end < 0 or (end - matrices_at) % 32 != 0:
		reader.fail("part %d: cannot tell where the matrices at %d end" % [part.index, matrices_at])
		return
	part.matrix_count = (end - matrices_at) / 32
	reader.seek(matrices_at)
	for matrix_index: int in part.matrix_count:
		var values := PackedInt32Array()
		for component: int in 9:
			values.append(reader.read_s16())
		reader.skip(2)
		for axis: int in 3:
			values.append(reader.read_s32())
		if reader.has_error():
			return
		part.matrices.append(values)


func _read_texture_animations(reader: ByteReader) -> void:
	if texture_animation_at == 0:
		return
	var end: int = _section_after(texture_animation_at, PackedInt32Array([flipbook_at, polygons_at]))
	if end < 0 or end > reader.size():
		reader.fail("part %d: cannot bound its texture animations" % part.index)
		return
	var section: ByteReader = reader.sub_reader(texture_animation_at, end - texture_animation_at)
	var count: int = section.read_s32()
	if count < 0 or count > section.remaining() / 16:
		reader.fail("part %d: texture target count %d exceeds its section" % [part.index, count])
		return
	var wanted := PackedInt32Array()
	for i: int in count:
		var target := MofTextureTarget.new()
		target.polygon_type = section.read_s32()
		target.polygon_index = section.read_s32()
		if section.read_u32() != 0:
			section.fail("part %d texture animation %d: the game's word is not zero" % [part.index, i])
		wanted.append(section.read_s32())
		part.texture_targets.append(target)
	var found: Dictionary[int, int] = {}
	while section.has_more() and not section.has_error():
		found[texture_animation_at + section.get_position()] = part.texture_lists.size()
		var animation := MofTextureAnimation.new()
		var entries: int = section.read_s32()
		if entries < 0 or entries > section.remaining() / 4:
			section.fail("part %d: texture list count %d exceeds its section" % [part.index, entries])
			break
		for _i: int in entries:
			var image: int = section.read_s16()
			animation.image_ids.append(image)
			animation.durations.append(section.read_u16())
			part.texture_animation_image_ids.append(image)
		if entries == 0:
			animation.error = "texture animation list is empty"
		part.texture_lists.append(animation)
	if section.has_error():
		reader.fail(section.error)
		return
	for i: int in wanted.size():
		var target: MofTextureTarget = part.texture_targets[i]
		if wanted[i] < texture_animation_at or wanted[i] >= end:
			reader.fail("part %d: texture list pointer outside its section" % part.index)
			return
		if not found.has(wanted[i]):
			target.error = "texture list pointer does not name a list"
		else:
			target.list_index = found[wanted[i]]
			if not part.texture_lists[target.list_index].error.is_empty():
				target.error = part.texture_lists[target.list_index].error
	part.texture_animation_target_count = part.texture_targets.size()
	part.texture_animation_count = part.texture_lists.size()


func _read_flipbook(reader: ByteReader) -> void:
	if flipbook_at == 0:
		return
	var end: int = _section_after(flipbook_at, PackedInt32Array([polygons_at]))
	if end < 0 or end > reader.size():
		reader.fail("part %d: cannot bound its flipbook" % part.index)
		return
	var section: ByteReader = reader.sub_reader(flipbook_at, end - flipbook_at)
	var flipbook_flags: int = section.read_u16()
	if flipbook_flags != 0:
		section.fail("part %d: flipbook flags %d" % [part.index, flipbook_flags])
	part.flipbook_action_count = section.read_u16()
	if part.flipbook_action_count > section.remaining() / 4:
		section.fail("part %d: flipbook action count exceeds its section" % part.index)
	for _i: int in part.flipbook_action_count:
		if section.has_error():
			break
		var action := MofFlipbookAction.new()
		action.frame_count = section.read_u16()
		action.start = section.read_u16()
		if action.frame_count == 0 or action.start + action.frame_count > part.partcels.size():
			action.error = "flipbook range %d + %d exceeds %d partcels" % [action.start, action.frame_count, part.partcels.size()]
		part.flipbook_actions.append(action)
	if section.has_error():
		reader.fail(section.error)


func _read_polygons(reader: ByteReader) -> void:
	part.end_offset = polygons_at
	if part.polygon_count == 0 and polygons_at == 0:
		return
	reader.seek(polygons_at)
	var left: int = part.polygon_count
	while left > 0 and not reader.has_error():
		var kind: int = reader.read_u16()
		var count: int = reader.read_u16()
		if count == 0 or count > left:
			reader.fail("part %d: polygon block count %d exceeds the %d remaining polygons" % [part.index, count, left])
			return
		if not MofPolygonType.is_valid(kind):
			reader.fail("part %d: polygons of kind %d" % [part.index, kind])
			return
		for _i: int in count:
			part.polygons.append(MofPolygonReader.read(reader, kind))
			if reader.has_error():
				return
		left -= count
	if left < 0:
		reader.fail("part %d: %d more polygons than the header states" % [part.index, -left])
	part.end_offset = reader.get_position()
