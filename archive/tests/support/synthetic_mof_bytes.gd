class_name SyntheticMofBytes
extends RefCounted
## Writes the model specs of [SyntheticMof] as model files, laid out as the
## game's tools lay them out (see MofStatic, MofPart, MofPolygon and
## MofAnimated), for the reader tests.


## The bytes of one polygon.
static func polygon_bytes(p: SyntheticMof.Polygon) -> PackedByteArray:
	var out := PackedByteArray()
	for v: int in p.vertices:
		_u16(out, v)
	for n: int in p.normals:
		_u16(out, n)
	if MofPolygonType.is_textured(p.type):
		if p.type == MofPolygonType.FT4:
			_u16(out, p.image_id)
		out.append_array(p.uvs.slice(0, 2))
		_u16(out, 0)
		out.append_array(p.uvs.slice(2, 4))
		_u16(out, 0)
		out.append_array(p.uvs.slice(4))
		if p.type != MofPolygonType.FT4:
			_u16(out, p.image_id)
	while out.size() % 4 != 0:
		out.append(0)
	out.append_array(PackedByteArray([p.colour.r8, p.colour.g8, p.colour.b8, 0xFF]))
	return out


## A static model of [param parts]. With [param incomplete] set, the model
## keeps its header and polygons and leaves out the rest, as the game's
## incomplete models do.
static func build_static(parts: Array[SyntheticMof.Part], incomplete: bool = false) -> PackedByteArray:
	var header_size: int = 16 + 44 * parts.size() + 4
	var pool := PackedByteArray()
	var vertex_offsets: Array[PackedInt32Array] = []
	var normal_offsets := PackedInt32Array()
	if not incomplete:
		for p: SyntheticMof.Part in parts:
			var offsets := PackedInt32Array()
			for pose: PackedInt32Array in p.poses:
				offsets.append(header_size + pool.size())
				_vectors(pool, pose)
			vertex_offsets.append(offsets)
		for p: SyntheticMof.Part in parts:
			normal_offsets.append(header_size + pool.size())
			_vectors(pool, p.normals)
	var body := PackedByteArray()
	var body_start: int = header_size + pool.size()
	var headers := PackedByteArray()
	var flags: int = 0
	for i: int in parts.size():
		var p: SyntheticMof.Part = parts[i]
		var partcel_at: int = body_start + body.size()
		if incomplete:
			body.resize(body.size() + 16 * p.poses.size())
		else:
			var box_at: int = partcel_at + 16 * p.poses.size()
			for pose: int in p.poses.size():
				_u32(body, vertex_offsets[i][pose])
				_u32(body, normal_offsets[i])
				_u32(body, box_at)
				_u32(body, 0)
			_vectors(body, SyntheticMof.bounding_box(p))
		var hilite_at: int = 0
		var collprim_at: int = 0
		var animation_at: int = 0
		var flipbook_at: int = 0
		if not incomplete:
			if not p.hilites.is_empty():
				hilite_at = body_start + body.size()
				for hilite: Vector2i in p.hilites:
					body.append_array(PackedByteArray([hilite.x, MofPart.ATTACH_VERTEX]))
					_u16(body, hilite.y)
					_u32(body, 0)
					_u32(body, 0)
			if p.collprims > 0:
				collprim_at = body_start + body.size()
				for c: int in p.collprims:
					_u16(body, 0)
					_u16(body, MofPart.COLLPRIM_LAST if c == p.collprims - 1 else 0)
					body.resize(body.size() + 8 + 8 + 4 + 8)
					_u32(body, 0xFFFFFFFF)
			if not p.animated_polygons.is_empty():
				animation_at = body_start + body.size()
				_u32(body, p.animated_polygons.size())
				var list_at: int = animation_at + 4 + 16 * p.animated_polygons.size()
				for polygon_index: int in p.animated_polygons:
					_u32(body, p.polygons[polygon_index].type)
					_u32(body, polygon_index)
					_u32(body, 0)
					_u32(body, list_at)
				_u32(body, p.animation_images.size())
				for image_index: int in p.animation_images.size():
					_u16(body, p.animation_images[image_index])
					_u16(body, p.animation_durations[image_index] if image_index < p.animation_durations.size() else 5)
				flags |= MofStatic.FLAG_ANIMATED_TEXTURES
		var action_count: int = p.flipbook_ranges.size() if not p.flipbook_ranges.is_empty() else p.flipbook_actions
		if action_count > 0:
			flags |= MofStatic.FLAG_FLIPBOOK
			if not incomplete:
				flipbook_at = body_start + body.size()
				_u16(body, 0)
				_u16(body, action_count)
				for action_index: int in action_count:
					_u16(body, p.flipbook_ranges[action_index].y if not p.flipbook_ranges.is_empty() else p.poses.size())
					_u16(body, p.flipbook_ranges[action_index].x if not p.flipbook_ranges.is_empty() else 0)
		var polygons_at: int = body_start + body.size()
		var kind: int = -1
		var run := PackedByteArray()
		var run_count: int = 0
		for poly: SyntheticMof.Polygon in p.polygons:
			if poly.type != kind and run_count > 0:
				_block(body, kind, run_count, run)
				run = PackedByteArray()
				run_count = 0
			kind = poly.type
			run.append_array(polygon_bytes(poly))
			run_count += 1
		if run_count > 0:
			_block(body, kind, run_count, run)
		_u16(headers, 1 if (not incomplete and not p.animated_polygons.is_empty()) else 0)
		_u16(headers, p.poses.size())
		_u16(headers, p.poses[0].size() / 3)
		_u16(headers, p.normals.size() / 3)
		_u16(headers, p.polygons.size())
		_u16(headers, p.hilites.size())
		_u32(headers, partcel_at)
		_u32(headers, polygons_at)
		_u32(headers, hilite_at)
		_u32(headers, 0)
		_u32(headers, collprim_at)
		_u32(headers, 0)
		_u32(headers, animation_at)
		_u32(headers, flipbook_at)
	var out := PackedByteArray([2, 0x46, 0x4F, 0x4D])
	_u32(out, header_size + pool.size() + body.size())
	_u32(out, flags if not incomplete else flags & MofStatic.FLAG_FLIPBOOK)
	_u32(out, parts.size())
	out.append_array(headers)
	_u32(out, 0x0A000000)
	out.append_array(pool)
	out.append_array(body)
	return out


## A valid XAR holding embedded static models and no authored actions.
static func build_animated(static_models: Array[PackedByteArray]) -> PackedByteArray:
	return SyntheticMofAnimationBytes.build(static_models)

## A placeholder model file.
static func build_dummy() -> PackedByteArray:
	return MofFile.DUMMY_SIGNATURE.to_ascii_buffer()


static func _block(body: PackedByteArray, kind: int, count: int, polygons: PackedByteArray) -> void:
	_u16(body, kind)
	_u16(body, count)
	body.append_array(polygons)


static func _vectors(out: PackedByteArray, values: PackedInt32Array) -> void:
	for i: int in range(0, values.size(), 3):
		for k: int in 3:
			_u16(out, values[i + k] & 0xFFFF)
		_u16(out, 0)


static func _u16(out: PackedByteArray, value: int) -> void:
	out.resize(out.size() + 2)
	out.encode_u16(out.size() - 2, value & 0xFFFF)


static func _u32(out: PackedByteArray, value: int) -> void:
	out.resize(out.size() + 4)
	out.encode_u32(out.size() - 4, value & 0xFFFFFFFF)
