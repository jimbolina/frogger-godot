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
## corners. Normals are kept for lighting, which is not done yet: a flat
## polygon gives its one normal to every corner, a gouraud polygon has one
## per corner.

## The pose of each part to build: partcel 0, the one the model rests in.
const REST_POSE: int = 0

## Draw textures smoothed instead of pixel by pixel.
var linear_filter: bool = false
## Draw both sides of every polygon.
var two_sided: bool = false

var _library: TextureLibrary
var _preferred: VloFile


## Textures are looked up in [param library], in [param preferred_bank] first.
func _init(library: TextureLibrary, preferred_bank: VloFile = null) -> void:
	_library = library
	_preferred = preferred_bank


# The corners of one surface being collected.
class _Surface:
	extends RefCounted
	var image: VloImage
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()


## Builds the meshes of [param model].
func build(model: MofStatic) -> ModelMesh:
	var result := ModelMesh.new()
	var missing: Dictionary[int, bool] = {}
	var first_vertex: bool = true
	for part: MofPart in model.parts:
		var surfaces: Dictionary[String, _Surface] = {}
		var order: Array[String] = []
		var cel: MofPart.Partcel = part.partcels[REST_POSE] if part.partcels.size() > REST_POSE else null
		if cel != null:
			for polygon: MofPolygon in part.polygons:
				if polygon.vertices.size() < 3:
					result.skipped_polygons += 1
					continue
				_add_polygon(polygon, cel, surfaces, order, missing)
		var mesh: ArrayMesh = null
		order.sort_custom(func(a: String, b: String) -> bool:
			return surfaces[a].blend < surfaces[b].blend if surfaces[a].blend != surfaces[b].blend else a < b)
		for key: String in order:
			var surface: _Surface = surfaces[key]
			if mesh == null:
				mesh = ArrayMesh.new()
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surface.vertices
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
			arrays[Mesh.ARRAY_COLOR] = surface.colors
			if surface.image != null:
				arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var texture: Texture2D = _library.texture_for(surface.image) if surface.image != null else null
			mesh.surface_set_material(mesh.get_surface_count() - 1,
				ModelShaders.material(texture, surface.blend, linear_filter, two_sided))
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
		order: Array[String], missing: Dictionary[int, bool]) -> void:
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
	if not surfaces.has(key):
		var made := _Surface.new()
		made.image = image
		made.blend = blend
		surfaces[key] = made
		order.append(key)
	var surface: _Surface = surfaces[key]
	var color := Color(polygon.red / 255.0, polygon.green / 255.0, polygon.blue / 255.0)
	for corner: int in triangle_corners(polygon.vertices.size()):
		var at: int = polygon.vertices[corner] * 3
		if at + 2 >= cel.vertices.size():
			surface.vertices.append(Vector3.ZERO)
		else:
			surface.vertices.append(GameSpace.position(cel.vertices[at], cel.vertices[at + 1], cel.vertices[at + 2]))
		var normal_at: int = polygon.normal_of_corner(corner) * 3
		if normal_at < 0 or normal_at + 2 >= cel.normals.size():
			surface.normals.append(Vector3.UP)
		else:
			surface.normals.append(GameSpace.normal(cel.normals[normal_at], cel.normals[normal_at + 1], cel.normals[normal_at + 2]))
		surface.colors.append(color)
		if image != null:
			surface.uvs.append(texture_coordinate(image, polygon.uvs[corner * 2], polygon.uvs[corner * 2 + 1]))
