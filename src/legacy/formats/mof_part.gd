class_name MofPart
extends RefCounted
## One part of a model: a group of polygons that moves as one piece.
##
## Header, 44 bytes (FrogLord's [code]MRMofPart[/code], the original's
## [code]MR_PART[/code]). Pointers count from the start of the model:
## [codeblock]
## u16 flags (bit 0: has texture animation)   u16 partcels
## u16 vertices per partcel   u16 normals per partcel
## u16 polygons   u16 hilites
## u32 partcels at   u32 polygons at   u32 hilites at (0 = none)
## u32 zero (filled in by the game)
## u32 collision primitives at   u32 matrices at
## u32 texture animation at   u32 flipbook at        (0 = none)
## [/codeblock]
## A partcel is one pose of the part: a set of vertices and normals and a
## bounding box. Partcel 0 is the pose the part rests in; the others are the
## frames of flipbook animations. The vertices and normals of every part sit
## in one pool near the start of the model.
##
## Polygons come in blocks of one kind each ([code]u16 kind, u16 count[/code]
## then the polygons), repeated until the header's polygon count is reached.
##
## A part of an incomplete model holds only its header and polygons; the
## rest is borrowed from the same part of another model (see [MofStatic]).

## Part flag: some polygons have animated textures.
const FLAG_ANIMATED_TEXTURES: int = 1 << 0
## Size of the header.
const HEADER_SIZE: int = 44
## Collision primitive flag: last one of the list.
const COLLPRIM_LAST: int = 1 << 1
## Hilite attached to a vertex of partcel 0.
const ATTACH_VERTEX: int = 1
## Hilite attached to a polygon.
const ATTACH_POLYGON: int = 2


## One pose of a part.
class Partcel:
	extends RefCounted
	## x, y, z of each vertex, in the game's units.
	var vertices := PackedInt32Array()
	## x, y, z of each normal; 4096 is a length of one.
	var normals := PackedInt32Array()
	## x, y, z of the box's 8 corners, or empty when there is no box.
	var bounding_box := PackedInt32Array()


## A marked point of a part, such as where a splash or a particle appears.
class Hilite:
	extends RefCounted
	## What the point is for (the game's own numbering).
	var type: int = 0
	## [constant MofPart.ATTACH_VERTEX] or [constant MofPart.ATTACH_POLYGON].
	var attach: int = 0
	## The vertex or polygon it is attached to.
	var index: int = 0


## A simple collision shape of a part.
class Collprim:
	extends RefCounted
	## 0 cuboid, 1 cylinder along x, 2 along y, 3 along z, 4 sphere.
	var type: int = 0
	## Flags as stored.
	var flags: int = 0
	## x, y, z of the centre, relative to the part.
	var offset := Vector3i.ZERO
	## Radius squared of a cylinder or sphere.
	var radius_squared: int = 0
	## Size along x, y and z.
	var size := Vector3i.ZERO
	## A value for the game's own use.
	var user: int = 0
	## Which of the part's matrices applies, or -1.
	var matrix_index: int = -1


## Position of the part in its model.
var index: int = 0
## Flags as stored.
var flags: int = 0
## Number of partcels the header states.
var partcel_count: int = 0
## Vertices per partcel the header states.
var vertex_count: int = 0
## Normals per partcel the header states.
var normal_count: int = 0
## Polygons the header states.
var polygon_count: int = 0
## Hilites the header states.
var hilite_count: int = 0
## True when everything but the polygons comes from another model's part.
var borrows: bool = false
## The poses. Borrowed when [member borrows] is set.
var partcels: Array[Partcel] = []
## How many different bounding boxes the partcels use.
var bounding_box_count: int = 0
## The marked points. Borrowed when [member borrows] is set.
var hilites: Array[Hilite] = []
## The collision shapes. Borrowed when [member borrows] is set.
var collprims: Array[Collprim] = []
## Number of matrices stored for the collision shapes.
var matrix_count: int = 0
## Number of flipbook animations.
var flipbook_action_count: int = 0
## Number of polygons with an animated texture.
var texture_animation_target_count: int = 0
## Number of texture animations.
var texture_animation_count: int = 0
## Texture ids the texture animations show, in stored order.
var texture_animation_image_ids := PackedInt32Array()
## The polygons, in stored order.
var polygons: Array[MofPolygon] = []
## Where the part's polygon data ends, from the start of the model.
var end_offset: int = 0

var _partcel_at: int = 0
var _polygons_at: int = 0
var _hilites_at: int = 0
var _collprims_at: int = 0
var _matrices_at: int = 0
var _texture_animation_at: int = 0
var _flipbook_at: int = 0


## Reads a part header at the reader's position.
static func read_header(reader: ByteReader, part_index: int) -> MofPart:
	var part := MofPart.new()
	part.index = part_index
	part.flags = reader.read_s16()
	part.partcel_count = reader.read_u16()
	part.vertex_count = reader.read_u16()
	part.normal_count = reader.read_u16()
	part.polygon_count = reader.read_u16()
	part.hilite_count = reader.read_u16()
	part._partcel_at = reader.read_u32()
	part._polygons_at = reader.read_u32()
	part._hilites_at = reader.read_u32()
	if reader.read_u32() != 0:
		reader.fail("part %d: the word the game fills in is not zero" % part_index)
	part._collprims_at = reader.read_u32()
	part._matrices_at = reader.read_u32()
	part._texture_animation_at = reader.read_u32()
	part._flipbook_at = reader.read_u32()
	return part


## Where this part's partcel list starts. The vector pool of a model ends at
## the first part's list.
func partcels_offset() -> int:
	return _partcel_at


## The pose the part rests in, or null.
func static_partcel() -> Partcel:
	return partcels[0] if not partcels.is_empty() else null


## Reads what the header points at. The vector pool is the bytes from
## [param pool_start] to [param pool_end]. With [param incomplete] set only
## the polygons are read. Problems are recorded in [param reader].
func read_body(reader: ByteReader, pool_start: int, pool_end: int, incomplete: bool) -> void:
	if not incomplete:
		_read_partcels(reader, pool_start, pool_end)
		_read_hilites(reader)
		_read_collprims(reader)
		_read_matrices(reader)
	var targets: Array[Vector2i] = []
	if not incomplete:
		targets = _read_texture_animations(reader)
		_read_flipbook(reader)
	_read_polygons(reader)
	if reader.has_error():
		return
	for target: Vector2i in targets:
		if target.y < 0 or target.y >= polygons.size():
			reader.fail("part %d: a texture animation names polygon %d of %d" % [index, target.y, polygons.size()])
		elif polygons[target.y].type != target.x:
			reader.fail("part %d: a texture animation expects polygon %d to be of kind %d" % [index, target.y, target.x])
	for hilite: Hilite in hilites:
		var limit: int = vertex_count if hilite.attach == ATTACH_VERTEX else polygons.size()
		if hilite.index >= limit:
			reader.fail("part %d: a hilite names item %d of %d" % [index, hilite.index, limit])
	var expected_flags: int = FLAG_ANIMATED_TEXTURES if texture_animation_target_count > 0 else 0
	if flags != expected_flags:
		reader.fail("part %d: flags %d, expected %d" % [index, flags, expected_flags])


## Takes the poses, hilites and collision shapes of [param other], as the
## game does for an incomplete model. The counts read from this part's own
## file stay as they were.
func borrow_from(other: MofPart) -> void:
	borrows = true
	partcels = other.partcels
	hilites = other.hilites
	collprims = other.collprims


## Number of polygons of each kind, in the order of [MofPolygonType].
func polygons_by_type() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(MofPolygonType.COUNT)
	for polygon: MofPolygon in polygons:
		counts[polygon.type] += 1
	return counts


func _read_vectors(reader: ByteReader, at: int, count: int, pool_start: int, pool_end: int, what: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count == 0:
		return out
	if at < pool_start or at + 8 * count > pool_end:
		reader.fail("part %d: %s at %d lie outside the vector pool (%d to %d)" % [index, what, at, pool_start, pool_end])
		return out
	if (at - pool_start) % 8 != 0:
		reader.fail("part %d: %s at %d are not on an 8-byte step of the vector pool" % [index, what, at])
		return out
	out.resize(count * 3)
	for i: int in count:
		out[i * 3] = reader.s16_at(at + i * 8)
		out[i * 3 + 1] = reader.s16_at(at + i * 8 + 2)
		out[i * 3 + 2] = reader.s16_at(at + i * 8 + 4)
	return out


func _read_partcels(reader: ByteReader, pool_start: int, pool_end: int) -> void:
	if partcel_count == 0:
		return
	reader.seek(_partcel_at)
	var box_offsets := PackedInt32Array()
	for i: int in partcel_count:
		var vertices_at: int = reader.read_u32()
		var normals_at: int = reader.read_u32()
		box_offsets.append(reader.read_u32())
		if reader.read_u32() != 0:
			reader.fail("part %d partcel %d: the unused word is not zero" % [index, i])
		if reader.has_error():
			return
		var cel := Partcel.new()
		cel.vertices = _read_vectors(reader, vertices_at, vertex_count, pool_start, pool_end, "vertices")
		cel.normals = _read_vectors(reader, normals_at, normal_count, pool_start, pool_end, "normals")
		partcels.append(cel)
	var boxes: Dictionary[int, PackedInt32Array] = {}
	for i: int in partcel_count:
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
		partcels[i].bounding_box = boxes[at]
	bounding_box_count = boxes.size()


func _read_hilites(reader: ByteReader) -> void:
	if hilite_count == 0:
		return
	reader.seek(_hilites_at)
	for i: int in hilite_count:
		var hilite := Hilite.new()
		hilite.type = reader.read_u8()
		hilite.attach = reader.read_u8()
		hilite.index = reader.read_u16()
		if reader.read_u32() != 0 or reader.read_u32() != 0:
			reader.fail("part %d hilite %d: the words the game fills in are not zero" % [index, i])
		if hilite.attach != ATTACH_VERTEX and hilite.attach != ATTACH_POLYGON:
			reader.fail("part %d hilite %d: attached to kind %d" % [index, i, hilite.attach])
		if reader.has_error():
			return
		hilites.append(hilite)


func _read_collprims(reader: ByteReader) -> void:
	if _collprims_at == 0:
		return
	reader.seek(_collprims_at)
	while not reader.has_error():
		var prim := Collprim.new()
		prim.type = reader.read_u16()
		prim.flags = reader.read_u16()
		if reader.read_u32() != 0 or reader.read_u32() != 0:
			reader.fail("part %d: a collision shape's words the game fills in are not zero" % index)
		if prim.type > 4:
			reader.fail("part %d: a collision shape of kind %d" % [index, prim.type])
		prim.offset = Vector3i(reader.read_s16(), reader.read_s16(), reader.read_s16())
		reader.skip(2)
		prim.radius_squared = reader.read_s32()
		prim.size = Vector3i(reader.read_u16(), reader.read_u16(), reader.read_u16())
		prim.user = reader.read_u16()
		prim.matrix_index = reader.read_s32()
		if reader.has_error():
			return
		collprims.append(prim)
		if prim.flags & COLLPRIM_LAST != 0:
			return


# The first section that starts after [param at], out of the ones that can follow it.
func _section_after(at: int, candidates: PackedInt32Array) -> int:
	var found: int = -1
	for candidate: int in candidates:
		if candidate > at and (found < 0 or candidate < found):
			found = candidate
	return found


func _read_matrices(reader: ByteReader) -> void:
	if _matrices_at == 0:
		return
	var end: int = _section_after(_matrices_at, PackedInt32Array([_texture_animation_at, _flipbook_at, _polygons_at]))
	if end < 0 or (end - _matrices_at) % 32 != 0:
		reader.fail("part %d: cannot tell where the matrices at %d end" % [index, _matrices_at])
		return
	matrix_count = (end - _matrices_at) / 32


# Returns (polygon kind, polygon index) of each animated polygon.
func _read_texture_animations(reader: ByteReader) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if _texture_animation_at == 0:
		return targets
	var end: int = _section_after(_texture_animation_at, PackedInt32Array([_flipbook_at, _polygons_at]))
	if end < 0:
		reader.fail("part %d: cannot tell where the texture animations at %d end" % [index, _texture_animation_at])
		return targets
	reader.seek(_texture_animation_at)
	var count: int = reader.read_s32()
	var lists_wanted := PackedInt32Array()
	for i: int in count:
		var kind: int = reader.read_s32()
		var polygon_index: int = reader.read_s32()
		if reader.read_u32() != 0:
			reader.fail("part %d texture animation %d: the word the game fills in is not zero" % [index, i])
		lists_wanted.append(reader.read_s32())
		if reader.has_error():
			return targets
		targets.append(Vector2i(kind, polygon_index))
	var lists_found := PackedInt32Array()
	while reader.get_position() < end and not reader.has_error():
		lists_found.append(reader.get_position())
		var entries: int = reader.read_s32()
		for _i: int in entries:
			texture_animation_image_ids.append(reader.read_s16())
			reader.read_u16() # How many game frames the image stays.
	if reader.get_position() != end:
		reader.fail("part %d: texture animations end at %d, the next section starts at %d" % [index, reader.get_position(), end])
	for wanted: int in lists_wanted:
		if not lists_found.has(wanted):
			reader.fail("part %d: no texture animation at %d" % [index, wanted])
	texture_animation_target_count = targets.size()
	texture_animation_count = lists_found.size()
	return targets


func _read_flipbook(reader: ByteReader) -> void:
	if _flipbook_at == 0:
		return
	reader.seek(_flipbook_at)
	var flipbook_flags: int = reader.read_u16()
	if flipbook_flags != 0:
		reader.fail("part %d: flipbook flags %d" % [index, flipbook_flags])
	flipbook_action_count = reader.read_u16()
	reader.skip(4 * flipbook_action_count)


func _read_polygons(reader: ByteReader) -> void:
	end_offset = _polygons_at
	if polygon_count == 0 and _polygons_at == 0:
		return
	reader.seek(_polygons_at)
	var left: int = polygon_count
	while left > 0 and not reader.has_error():
		var kind: int = reader.read_u16()
		var count: int = reader.read_u16()
		if not MofPolygonType.is_valid(kind):
			reader.fail("part %d: polygons of kind %d" % [index, kind])
			return
		for _i: int in count:
			polygons.append(MofPolygon.read(reader, kind))
			if reader.has_error():
				return
		left -= count
	if left < 0:
		reader.fail("part %d: %d more polygons than the header states" % [index, -left])
	end_offset = reader.get_position()
