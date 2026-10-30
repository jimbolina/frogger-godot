class_name StackMeshBuilder
extends RefCounted
## Meshes and materials of the level-select stack (SelectCreateMOF, SelectEnableSpinMOF).
##
## A box is six quads over the eight [StackLayout] vertices. Surface 0 holds faces 0-4 with the
## world image: the sides show the row's horizontal strip of it and face 4 the whole image.
## Surface 1 holds face 5, the whole world image on a stack box or the level picture on the
## spinning box. Corners are drawn as stored and quads split like model quads, so faces show
## their fronts outward; normals are the source's, pointing into the box, which the lights expect.
## Materials use [ModelShaders] with its source lighting: the stack's ambient and three parallel
## lights, scaled by the row's tint over 128 so the vertex colour stays neutral.

## Vertex colour of every corner: the neutral polygon colour, the tint living in the material.
const NEUTRAL_COLOUR: int = 0x80
## Faces in surface 0.
const WORLD_FACES: PackedInt32Array = [0, 1, 2, 3, 4]
## Image corners of GPU corners 0-3 for an upright image: top-left, top-right, bottom-left, bottom-right.
const UPRIGHT_CORNERS: PackedInt32Array = [0, 1, 2, 3]
## The whole image as a texture region.
const FULL_REGION: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
## Game units moved toward the camera by the gold-frog quads so they draw over the box side they lie on.
const GOLD_FROG_DEPTH_BIAS: float = 16.0


## The 0..1 texture region a side face shows: the strip of [method StackLayout.side_strip]
## of an image [param texture_height] texels high, or the whole image without a height.
static func side_region(texture_height: int, local_level: int, levels_in_world: int) -> Rect2:
	if texture_height <= 0 or levels_in_world <= 0:
		return FULL_REGION
	var strip: Vector2i = StackLayout.side_strip(texture_height, local_level, levels_in_world)
	return Rect2(0.0, float(strip.x) / texture_height, 1.0, float(strip.y) / texture_height)


## The UV of image corner [param corner] (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right)
## within [param region].
static func corner_uv(corner: int, region: Rect2) -> Vector2:
	return region.position + Vector2(corner & 1, corner >> 1) * region.size


## A box over eight game-space [param vertices] in SelectCreateMOF order. Faces 0-3 show
## [param side] of the world image, face 4 the whole of it; face 5 shows its image with GPU corner
## k taking image corner [code]end_corners[k][/code].
static func box_mesh(vertices: Array[Vector3i], side: Rect2, end_corners: PackedInt32Array = UPRIGHT_CORNERS) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var world := _Surface.new()
	for face: int in WORLD_FACES:
		var region: Rect2 = side if face < StackLayout.SIDE_FACES else FULL_REGION
		world.add_face(vertices, face, region, UPRIGHT_CORNERS)
	world.commit(mesh)
	var end := _Surface.new()
	end.add_face(vertices, StackLayout.FACE_COUNT - 1, FULL_REGION, end_corners)
	end.commit(mesh)
	return mesh


## The stack box of [param row]: its vertices at rest, local to the stack frame.
static func row_mesh(layout: StackLayout, row: int, texture_height: int, local_level: int, levels_in_world: int) -> ArrayMesh:
	return box_mesh(layout.row_vertices(row), side_region(texture_height, local_level, levels_in_world))


## The spinning box for [param row]: the row's size centred on its frame, face 5 showing the
## level picture with [constant StackLayout.SPIN_IMAGE_CORNERS].
static func spin_mesh(layout: StackLayout, row: int, texture_height: int, local_level: int, levels_in_world: int) -> ArrayMesh:
	return box_mesh(StackLayout.box_vertices(layout.y_size(row), 0),
		side_region(texture_height, local_level, levels_in_world), StackLayout.SPIN_IMAGE_CORNERS)


## A single unlit quad through four game-space [param corners] in POLY_FT4 order (top-left,
## top-right, bottom-left, bottom-right of the image), as the gold-frog polygons are drawn.
static func quad_mesh(corners: Array[Vector3i]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if corners.size() != 4:
		return mesh
	var surface := _Surface.new()
	var round_order: Array[Vector3i] = [corners[0], corners[1], corners[3], corners[2]]
	var round_uvs: Array[Vector2] = [corner_uv(0, FULL_REGION), corner_uv(1, FULL_REGION), corner_uv(3, FULL_REGION), corner_uv(2, FULL_REGION)]
	surface.add_quad(round_order, Vector3.ZERO, round_uvs)
	surface.commit(mesh)
	return mesh


## A lit, opaque, back-face-culled material for a box surface showing [param texture]
## (untextured when null), tinted by [param tint].
static func box_material(texture: Texture2D, tint: int, projection_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var material: ShaderMaterial = ModelShaders.material(texture, ModelShaders.Blend.OPAQUE, false, false)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("source_lighting", true)
	for index: int in StackLayout.LIGHT_COLOURS.size():
		var direction: Vector3i = StackLayout.light_direction(index)
		material.set_shader_parameter("source_direction%d" % index, GameSpace.normal(direction.x, direction.y, direction.z))
	set_tint(material, tint)
	return material


## An unlit, two-sided material for a raw polygon showing [param texture], drawn
## [constant GOLD_FROG_DEPTH_BIAS] units nearer the camera.
static func quad_material(texture: Texture2D, projection_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var material: ShaderMaterial = ModelShaders.material(texture, ModelShaders.Blend.OPAQUE, false, true)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("depth_bias", GOLD_FROG_DEPTH_BIAS)
	return material


## Sets the light of [param material] for polygon colour [param tint]: the ambient and parallel
## colours (stored bytes times 16) scaled by tint / 128 on the neutral vertex colour.
static func set_tint(material: ShaderMaterial, tint: int) -> void:
	var scale: float = float(tint) / NEUTRAL_COLOUR
	material.set_shader_parameter("source_ambient", Vector3.ONE * float((StackLayout.AMBIENT_COLOUR & 0xff) << 4) * scale)
	for index: int in StackLayout.LIGHT_COLOURS.size():
		var colour: int = StackLayout.LIGHT_COLOURS[index] & 0xff
		material.set_shader_parameter("source_colour%d" % index, Vector3.ONE * float(colour << 4) * scale)


## The tint [param material] was last given by [method set_tint].
static func material_tint(material: ShaderMaterial) -> int:
	var ambient: Vector3 = material.get_shader_parameter("source_ambient")
	return roundi(ambient.x * NEUTRAL_COLOUR / float((StackLayout.AMBIENT_COLOUR & 0xff) << 4))


class _Surface:
	extends RefCounted
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	func add_face(vertices: Array[Vector3i], face: int, region: Rect2, image_corners: PackedInt32Array) -> void:
		var mof: PackedInt32Array = StackLayout.face_indices(face)
		var normal: Vector3i = StackLayout.FACE_NORMALS[face]
		var gpu_of_mof: PackedInt32Array = [0, 1, 3, 2]
		var corners: Array[Vector3i] = []
		var face_uvs: Array[Vector2] = []
		for corner: int in 4:
			corners.append(vertices[mof[corner]])
			face_uvs.append(StackMeshBuilder.corner_uv(image_corners[gpu_of_mof[corner]], region))
		add_quad(corners, GameSpace.normal(normal.x, normal.y, normal.z), face_uvs)

	func add_quad(corners: Array[Vector3i], normal: Vector3, face_uvs: Array[Vector2]) -> void:
		var base: int = positions.size()
		var colour := Color8(StackMeshBuilder.NEUTRAL_COLOUR, StackMeshBuilder.NEUTRAL_COLOUR, StackMeshBuilder.NEUTRAL_COLOUR)
		for corner: int in 4:
			positions.append(GameSpace.position(corners[corner].x, corners[corner].y, corners[corner].z))
			normals.append(normal)
			uvs.append(face_uvs[corner])
			colours.append(colour)
		for corner: int in ModelMeshBuilder.triangle_corners(4):
			indices.append(base + corner)

	func commit(mesh: ArrayMesh) -> void:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
