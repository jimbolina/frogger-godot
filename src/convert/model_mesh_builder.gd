class_name ModelMeshBuilder
extends RefCounted
## Builds Godot meshes from a static model ([MofStatic]).
##
## Each part becomes one [ArrayMesh]. Its polygons are sorted into surfaces
## by the texture they use and by how they are drawn, because a surface has
## one material:
## [br]- untextured polygons;
## [br]- textured polygons, one surface per texture;
## [br]- translucent polygons (a textured polygon whose texture has the
##   translucent flag), one surface per texture, mixed in the way the texture's
##   blend mode says.
## [br]Every corner gets its own vertex, as corners that share a position
## still differ in colour and texture coordinate.
##
## [b]Corners.[/b] A triangle is drawn as stored. A quad is stored going
## round its edge and is drawn as corners (0, 1, 3) and (1, 2, 3).
##
## [b]Texture coordinates.[/b] A stored coordinate runs from 0 to 255 across
## the in-game part of the image. The game turns it into a whole pixel,
## [code]coordinate * size / 255[/code], and so does this.
##
## [b]Colour and normals.[/b] A polygon has one colour, given to all its
## corners. Optional map probe lighting uses stored normals: a flat
## polygon gives its one normal to every corner, a gouraud polygon has one
## per corner.

## The pose of each part to build: partcel 0, the one the model rests in.
const REST_POSE: int = 0

## Draw textures smoothed and mipmapped instead of pixel by pixel; starts as
## the library's texture set asks.
var linear_filter: bool = false
## Draw both sides of every polygon.
var two_sided: bool = false
## Draw through the lit shaders of the modern rendering profile; starts as
## the library's catalog asks. A probe prelit by [member lighting] stays on
## the retail shaders.
var lit_materials: bool = false
## Optional map lighting for a static model probe; standalone viewers stay unlit.
var lighting: MapLighting
## Probe's world orientation when prelighting its normals.
var lighting_basis: Basis = Basis.IDENTITY

var _library: TextureLibrary
var _preferred: VloFile


## Textures are looked up in [param library], in [param preferred_bank] first.
func _init(library: TextureLibrary, preferred_bank: VloFile = null) -> void:
	_library = library
	_preferred = preferred_bank
	linear_filter = library != null and library.linear_filter()
	lit_materials = library != null and library.rendering_profile().is_modern()


class _Surface:
	extends RefCounted
	var image: VloImage
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var vertex_indices := PackedInt32Array()
	var normal_indices := PackedInt32Array()
	var target: int = -1
	var list_index: int = -1


## Builds the meshes of [param model].
func build(model: MofStatic) -> ModelMesh:
	return _build(model, false)


## Builds all flipbook cels and texture frames once, with bounds covering every action.
func build_animated(file: MofFile, static_index: int = 0) -> ModelMesh:
	var result: ModelMesh = _build(file.static_models[static_index], true)
	if file.animated == null:
		var model: MofStatic = file.static_models[static_index]
		if model.parts.is_empty():
			return result
		for action: MofPart.FlipbookAction in model.parts[0].flipbook_actions:
			var box := AABB()
			var first_vertex: bool = true
			for part: MofPart in model.parts:
				for cel_index: int in range(maxi(action.start, 0), mini(action.start + action.frame_count, part.partcels.size())):
					var cel: MofPart.Partcel = part.partcels[cel_index]
					for at: int in range(0, cel.vertices.size(), 3):
						var vertex: Vector3 = GameSpace.position(cel.vertices[at], cel.vertices[at + 1], cel.vertices[at + 2])
						box = AABB(vertex, Vector3.ZERO) if first_vertex else box.expand(vertex)
						first_vertex = false
			result.action_bounds.append(box if not first_vertex else result.bounds)
		return result
	var first: bool = true
	for action_index: int in file.animated.actions_for(static_index).size():
		var action: MofAnimated.Action = file.animated.actions_for(static_index)[action_index]
		var action_box := AABB()
		var action_first: bool = true
		if not action.error.is_empty():
			result.action_bounds.append(result.bounds)
			continue
		for frame: int in action.frame_count:
			for part_index: int in result.part_bounds.size():
				var pose: Transform3D = GameSpace.transform(file.animated.sample_matrix(static_index, action_index, frame, part_index))
				var local: AABB = result.part_bounds[part_index]
				var radius: float = 0.0
				for corner: int in 8:
					radius = maxf(radius, local.get_endpoint(corner).length())
				var extent: float = radius * _basis_extent(pose.basis)
				var box := AABB(pose.origin - Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
				result.bounds = box if first else result.bounds.merge(box)
				first = false
				action_box = box if action_first else action_box.merge(box)
				action_first = false
		result.action_bounds.append(action_box if not action_first else result.bounds)
	return result


static func _basis_extent(basis: Basis) -> float:
	var xy: float = absf(basis.x.dot(basis.y))
	var xz: float = absf(basis.x.dot(basis.z))
	var yz: float = absf(basis.y.dot(basis.z))
	return sqrt(maxf(basis.x.length_squared() + xy + xz,
		maxf(basis.y.length_squared() + xy + yz, basis.z.length_squared() + xz + yz)))


func _build(model: MofStatic, animated: bool) -> ModelMesh:
	var result := ModelMesh.new()
	var missing: Dictionary[int, bool] = {}
	var first_vertex: bool = true
	var lit_shading: bool = lit_materials and lighting == null
	for part: MofPart in model.parts:
		var tracks: Array[ModelTextureTrack] = []
		var surfaces: Dictionary[String, _Surface] = {}
		var order: Array[String] = []
		var cel: MofPart.Partcel = part.partcels[REST_POSE] if part.partcels.size() > REST_POSE else null
		if cel != null:
			for polygon: MofPolygon in part.polygons:
				if polygon.vertices.size() < 3:
					result.skipped_polygons += 1
					continue
				var target_index: int = _target_for(part, polygon) if animated else -1
				_add_polygon(polygon, cel, surfaces, order, missing, target_index,
					part.texture_targets[target_index].list_index if target_index >= 0 else -1)
		var mesh: ArrayMesh = null
		var morph_cels: Array[Array] = []
		order.sort_custom(func(a: String, b: String) -> bool:
			return surfaces[a].blend < surfaces[b].blend if surfaces[a].blend != surfaces[b].blend else a < b)
		for key: String in order:
			var surface: _Surface = surfaces[key]
			if mesh == null:
				mesh = ArrayMesh.new()
				if animated:
					mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
					for cel_index: int in range(1, part.partcels.size()):
						mesh.add_blend_shape("Cel%d" % cel_index)
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surface.vertices
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
			arrays[Mesh.ARRAY_COLOR] = surface.colors
			if surface.image != null:
				arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
			var blends: Array[Array] = []
			if animated:
				for cel_index: int in range(1, part.partcels.size()):
					var blend_arrays: Array = []
					blend_arrays.resize(Mesh.ARRAY_MAX)
					blend_arrays[Mesh.ARRAY_VERTEX] = _cel_vertices(part.partcels[cel_index], surface.vertex_indices)
					blend_arrays[Mesh.ARRAY_NORMAL] = _cel_normals(part.partcels[cel_index], surface.normal_indices)
					blends.append(blend_arrays)
			var cels: Array = [arrays]
			cels.append_array(blends)
			morph_cels.append(cels)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
			var texture: Texture2D = _library.texture_for(surface.image) if surface.image != null else null
			var material: ShaderMaterial = ModelShaders.material(texture, surface.blend, linear_filter, two_sided, lit_shading)
			if surface.target >= 0:
				_set_pixel_uv(material, surface.image)
				var track := ModelTextureTrack.new()
				track.surface = mesh.get_surface_count() - 1
				track.target = surface.target
				track.original = material
				if surface.image == null:
					result.diagnostics.append("part %d texture target %d: original image unavailable; animation stays untextured because its pixel UVs cannot be resolved" % [part.index, surface.target])
				if surface.list_index >= 0 and surface.list_index < part.texture_lists.size():
					for image_id: int in part.texture_lists[surface.list_index].image_ids:
						var image: VloImage = _library.image_for_id(image_id, _preferred) if _library != null else null
						if image == null:
							missing[image_id] = true
						if surface.image == null:
							track.frames.append(material)
							continue
						var frame_blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
						if surface.image != null and surface.image.has_flag(VloImage.FLAG_TRANSLUCENT) and image != null:
							frame_blend = ModelShaders.blend_for_mode(image.blend_mode())
						var frame_material: ShaderMaterial = ModelShaders.material(_library.texture_for(image) if image != null else null,
							frame_blend, linear_filter, two_sided, lit_shading)
						_set_pixel_uv(frame_material, image)
						track.frames.append(frame_material)
				tracks.append(track)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			mesh.surface_set_name(mesh.get_surface_count() - 1, key)
			result.surface_count += 1
			result.triangle_count += surface.vertices.size() / 3
			for vertex: Vector3 in surface.vertices:
				if first_vertex:
					result.bounds = AABB(vertex, Vector3.ZERO)
					first_vertex = false
				else:
					result.bounds = result.bounds.expand(vertex)
		result.part_meshes.append(mesh)
		result.morph_meshes.append(ModelMorphMesh.create(mesh, morph_cels) if animated else null)
		if animated and mesh != null and mesh.get_blend_shape_count() > 0 and result.morph_meshes[-1] == null:
			result.diagnostics.append("part %d cel atlas exceeds 4096 pixels per side; using native blend shapes" % part.index)
		result.texture_tracks.append(tracks)
		var local := AABB()
		var local_first: bool = true
		for partcel: MofPart.Partcel in part.partcels:
			for at: int in range(0, partcel.vertices.size(), 3):
				var vertex: Vector3 = GameSpace.position(partcel.vertices[at], partcel.vertices[at + 1], partcel.vertices[at + 2])
				local = AABB(vertex, Vector3.ZERO) if local_first else local.expand(vertex)
				local_first = false
		result.part_bounds.append(local)
		if animated:
			result.bounds = result.bounds.merge(local)
			if mesh != null:
				mesh.custom_aabb = local
				if result.morph_meshes[-1] != null:
					result.morph_meshes[-1].mesh.custom_aabb = local
	result.missing_image_ids = PackedInt32Array(missing.keys())
	result.missing_image_ids.sort()
	return result


## Where stored texture coordinate ([param u], [param v]) of [param image]
## lies in its Godot texture, 0 to 1.
static func texture_coordinate(image: VloImage, u: int, v: int) -> Vector2:
	var x: int = image.left_padding() + (u * image.width) / 255
	var y: int = image.top_padding() + (v * image.height) / 255
	return Vector2(float(x) / image.padded_width, float(y) / image.padded_height)


## The corners of the triangles of a polygon with [param corner_count]
## corners, three for each triangle.
static func triangle_corners(corner_count: int) -> PackedInt32Array:
	if corner_count == 4:
		return PackedInt32Array([0, 1, 3, 1, 2, 3])
	if corner_count == 3:
		return PackedInt32Array([0, 1, 2])
	return PackedInt32Array()


func _add_polygon(polygon: MofPolygon, cel: MofPart.Partcel, surfaces: Dictionary[String, _Surface],
		order: Array[String], missing: Dictionary[int, bool], target: int = -1, list_index: int = -1) -> void:
	var image: VloImage = null
	if polygon.is_textured():
		image = _library.image_for_id(polygon.image_id, _preferred) if _library != null else null
		if image == null:
			missing[polygon.image_id] = true
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
	if image != null and image.has_flag(VloImage.FLAG_TRANSLUCENT):
		blend = ModelShaders.blend_for_mode(image.blend_mode())
	var key: String = "plain" if image == null else "texture %d%s" % [image.texture_id,
		"" if blend == ModelShaders.Blend.OPAQUE else " blend %d" % blend]
	if target >= 0:
		key = "animated %d" % target
	if not surfaces.has(key):
		var made := _Surface.new()
		made.image = image
		made.blend = blend
		made.target = target
		made.list_index = list_index
		surfaces[key] = made
		order.append(key)
	var surface: _Surface = surfaces[key]
	var color := Color(polygon.red / 255.0, polygon.green / 255.0, polygon.blue / 255.0)
	for corner: int in triangle_corners(polygon.vertices.size()):
		var at: int = polygon.vertices[corner] * 3
		surface.vertex_indices.append(at)
		if at + 2 >= cel.vertices.size():
			surface.vertices.append(Vector3.ZERO)
		else:
			surface.vertices.append(GameSpace.position(cel.vertices[at], cel.vertices[at + 1], cel.vertices[at + 2]))
		var normal_at: int = polygon.normal_of_corner(corner) * 3
		surface.normal_indices.append(normal_at)
		if normal_at < 0 or normal_at + 2 >= cel.normals.size():
			surface.normals.append(Vector3.UP)
		else:
			surface.normals.append(GameSpace.normal(cel.normals[normal_at], cel.normals[normal_at + 1], cel.normals[normal_at + 2]))
		var lit: Color = color
		if lighting != null:
			lit = lighting.shade(color, surface.normals[surface.normals.size() - 1], lighting_basis)
		surface.colors.append(lit)
		if image != null:
			if target >= 0:
				surface.uvs.append(Vector2((polygon.uvs[corner * 2] * image.width) / 255,
					(polygon.uvs[corner * 2 + 1] * image.height) / 255))
			else:
				surface.uvs.append(texture_coordinate(image, polygon.uvs[corner * 2], polygon.uvs[corner * 2 + 1]))


static func _set_pixel_uv(material: ShaderMaterial, image: VloImage) -> void:
	if image == null:
		return
	material.set_shader_parameter("uv_scale", Vector2(1.0 / image.padded_width, 1.0 / image.padded_height))
	material.set_shader_parameter("uv_offset", Vector2(float(image.left_padding()) / image.padded_width,
		float(image.top_padding()) / image.padded_height))


static func _target_for(part: MofPart, polygon: MofPolygon) -> int:
	var polygon_index: int = part.polygons.find(polygon)
	for index: int in part.texture_targets.size():
		if part.texture_targets[index].polygon_type == polygon.type and part.texture_targets[index].polygon_index == polygon_index \
				and part.texture_targets[index].error.is_empty():
			return index
	return -1


static func _cel_vertices(cel: MofPart.Partcel, indices: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for at: int in indices:
		out.append(GameSpace.position(cel.vertices[at], cel.vertices[at + 1], cel.vertices[at + 2]) if at >= 0 and at + 2 < cel.vertices.size() else Vector3.ZERO)
	return out


static func _cel_normals(cel: MofPart.Partcel, indices: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for at: int in indices:
		out.append(GameSpace.normal(cel.normals[at], cel.normals[at + 1], cel.normals[at + 2]) if at >= 0 and at + 2 < cel.normals.size() else Vector3.UP)
	return out
