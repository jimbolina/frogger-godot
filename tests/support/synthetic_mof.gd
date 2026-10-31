class_name SyntheticMof
extends RefCounted
## Describes small models for tests and builds them as model records, with the
## values a model file laid out the same way decodes to (see MofStatic,
## MofPart and MofPolygon). Values that only describe where things lie in a
## file, such as [member MofStatic.length] and [member MofPart.end_offset],
## keep their defaults.


## One polygon for [method static_model].
class Polygon:
	extends RefCounted
	var type: int = MofPolygonType.F3
	var vertices := PackedInt32Array()
	var normals := PackedInt32Array()
	## u, v per corner, in stored order; textured kinds only.
	var uvs := PackedByteArray()
	var image_id: int = 0
	var colour := Color8(128, 128, 128)


## One part for [method static_model].
class Part:
	extends RefCounted
	## x, y, z per vertex, one array per partcel (pose).
	var poses: Array[PackedInt32Array] = []
	## x, y, z per normal, the same for every pose.
	var normals := PackedInt32Array()
	var polygons: Array[Polygon] = []
	## (type, vertex index) of each hilite.
	var hilites: Array[Vector2i] = []
	## Number of collision shapes.
	var collprims: int = 0
	## Number of flipbook animations (0 gives no flipbook).
	var flipbook_actions: int = 0
	## Optional (start, frame count) records; otherwise all actions use all poses.
	var flipbook_ranges: Array[Vector2i] = []
	## Polygon indices with a texture animation showing [member animation_images].
	var animated_polygons := PackedInt32Array()
	var animation_images := PackedInt32Array()
	## Optional per-image durations; absent values use five frames.
	var animation_durations := PackedInt32Array()


## A polygon of kind [param type] joining [param vertices], lit by [param
## normals]; textured kinds also take [param image_id] and [param uvs].
static func polygon(type: int, vertices: Array[int], normals: Array[int], colour: Color = Color8(128, 128, 128),
		image_id: int = 0, uvs: Array[int] = []) -> Polygon:
	var made := Polygon.new()
	made.type = type
	made.vertices = PackedInt32Array(vertices)
	made.normals = PackedInt32Array(normals)
	made.colour = colour
	made.image_id = image_id
	made.uvs = PackedByteArray(uvs)
	return made


## A part with one pose of [param vertices] (x, y, z each) and [param normals].
static func part(vertices: Array[int], normals: Array[int], polygons: Array[Polygon]) -> Part:
	var made := Part.new()
	made.poses.append(PackedInt32Array(vertices))
	made.normals = PackedInt32Array(normals)
	made.polygons = polygons
	return made


## A unit square in the x-y plane (z = 0), 256 units wide, as one quad of
## kind [param type], with texture coordinates at the image's corners.
static func square(type: int, colour: Color = Color8(128, 128, 128), image_id: int = 0) -> Part:
	var normals: Array[int] = [0]
	if MofPolygonType.normal_count(type) == 4:
		normals = [0, 0, 0, 0]
	var uvs: Array[int] = []
	if MofPolygonType.is_textured(type):
		uvs = [0, 0, 255, 0, 255, 255, 0, 255]
	return part([0, 0, 0, 256, 0, 0, 256, 256, 0, 0, 256, 0], [0, 0, -4096],
		[polygon(type, [0, 1, 2, 3], normals, colour, image_id, uvs)])


## The eight corners (x, y, z each) of the box around every pose of [param p].
static func bounding_box(p: Part) -> PackedInt32Array:
	var low := Vector3i(32767, 32767, 32767)
	var high := Vector3i(-32768, -32768, -32768)
	for pose: PackedInt32Array in p.poses:
		for i: int in range(0, pose.size(), 3):
			var at := Vector3i(pose[i], pose[i + 1], pose[i + 2])
			low = low.min(at)
			high = high.max(at)
	var box := PackedInt32Array()
	for x: int in [low.x, high.x]:
		for y: int in [low.y, high.y]:
			for z: int in [low.z, high.z]:
				box.append_array(PackedInt32Array([x, y, z]))
	return box


## A static model file of [param parts].
static func static_file(parts: Array[Part]) -> MofFile:
	var file := MofFile.new()
	file.kind = MofFile.Kind.STATIC
	file.signature = "02464f4d"
	var model: MofStatic = static_model(parts)
	file.flags = model.flags
	file.static_models.append(model)
	file.error = model.error
	return file


## A placeholder model file.
static func dummy_file() -> MofFile:
	var file := MofFile.new()
	file.kind = MofFile.Kind.DUMMY
	file.signature = MofFile.DUMMY_SIGNATURE.to_ascii_buffer().hex_encode()
	file.size = MofFile.DUMMY_SIGNATURE.length()
	return file


## The static model of [param parts].
static func static_model(parts: Array[Part]) -> MofStatic:
	var model := MofStatic.new()
	model.unknown_word = 0x0A000000
	for i: int in parts.size():
		var made: MofPart = _part(parts[i], i)
		model.parts.append(made)
		if not made.texture_targets.is_empty():
			model.flags |= MofStatic.FLAG_ANIMATED_TEXTURES
		if not made.flipbook_actions.is_empty():
			model.flags |= MofStatic.FLAG_FLIPBOOK
		for hilite: MofHilite in made.hilites:
			if model.error.is_empty() and hilite.index >= made.vertex_count:
				model.error = "part %d: a hilite names item %d of %d" % [i, hilite.index, made.vertex_count]
	return model


static func _part(spec: Part, index: int) -> MofPart:
	var made := MofPart.new()
	made.index = index
	made.flags = MofPart.FLAG_ANIMATED_TEXTURES if not spec.animated_polygons.is_empty() else 0
	made.partcel_count = spec.poses.size()
	made.vertex_count = spec.poses[0].size() / 3
	made.normal_count = spec.normals.size() / 3
	made.polygon_count = spec.polygons.size()
	made.hilite_count = spec.hilites.size()
	var box: PackedInt32Array = bounding_box(spec)
	for pose: PackedInt32Array in spec.poses:
		var cel := MofPartcel.new()
		cel.vertices = _s16s(pose)
		cel.normals = _s16s(spec.normals)
		cel.bounding_box = box
		made.partcels.append(cel)
	made.bounding_box_count = 1 if not spec.poses.is_empty() else 0
	for pair: Vector2i in spec.hilites:
		var hilite := MofHilite.new()
		hilite.type = pair.x & 0xFF
		hilite.attach = MofPart.ATTACH_VERTEX
		hilite.index = pair.y & 0xFFFF
		made.hilites.append(hilite)
	for c: int in spec.collprims:
		var prim := MofCollprim.new()
		prim.flags = MofPart.COLLPRIM_LAST if c == spec.collprims - 1 else 0
		made.collprims.append(prim)
	for poly: Polygon in spec.polygons:
		made.polygons.append(_polygon(poly))
	if not spec.animated_polygons.is_empty():
		var animation := MofTextureAnimation.new()
		for image_index: int in spec.animation_images.size():
			animation.image_ids.append(spec.animation_images[image_index])
			animation.durations.append(spec.animation_durations[image_index] if image_index < spec.animation_durations.size() else 5)
			made.texture_animation_image_ids.append(spec.animation_images[image_index])
		if spec.animation_images.is_empty():
			animation.error = "texture animation list is empty"
		made.texture_lists.append(animation)
		for polygon_index: int in spec.animated_polygons:
			var target := MofTextureTarget.new()
			target.polygon_type = spec.polygons[polygon_index].type
			target.polygon_index = polygon_index
			target.list_index = 0
			target.error = animation.error
			if not made.polygons[polygon_index].is_textured():
				target.error = "texture target names an incompatible polygon"
			made.texture_targets.append(target)
		made.texture_animation_target_count = made.texture_targets.size()
		made.texture_animation_count = 1
	var action_count: int = spec.flipbook_ranges.size() if not spec.flipbook_ranges.is_empty() else spec.flipbook_actions
	made.flipbook_action_count = action_count
	for action_index: int in action_count:
		var action := MofFlipbookAction.new()
		action.frame_count = spec.flipbook_ranges[action_index].y if not spec.flipbook_ranges.is_empty() else spec.poses.size()
		action.start = spec.flipbook_ranges[action_index].x if not spec.flipbook_ranges.is_empty() else 0
		if action.frame_count == 0 or action.start + action.frame_count > made.partcels.size():
			action.error = "flipbook range %d + %d exceeds %d partcels" % [action.start, action.frame_count, made.partcels.size()]
		made.flipbook_actions.append(action)
	return made


static func _polygon(spec: Polygon) -> MofPolygon:
	var made := MofPolygon.new()
	made.type = spec.type
	made.vertices = spec.vertices.duplicate()
	var environment: int = MofPolygonType.environment_normal_count(spec.type)
	made.environment_normals = spec.normals.slice(0, environment)
	made.normals = spec.normals.slice(environment, environment + MofPolygonType.normal_count(spec.type))
	if MofPolygonType.is_textured(spec.type):
		made.uvs = spec.uvs.duplicate()
		made.image_id = ((spec.image_id & 0xFFFF) ^ 0x8000) - 0x8000
	made.red = spec.colour.r8
	made.green = spec.colour.g8
	made.blue = spec.colour.b8
	made.code = 0xFF
	return made


static func _s16s(values: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for value: int in values:
		out.append(((value & 0xFFFF) ^ 0x8000) - 0x8000)
	return out
