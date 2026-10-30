class_name MenuWaterMesh
extends RefCounted
## Meshes and materials of the front-end water surface and riverbed (HSInitialiseWater,
## HSUpdateWater) built from [MenuWater].
##
## The water is one surface over the shared grid vertices with the whole texture spread across
## it; only its vertex heights change, through [method set_heights], so its material and
## texture coordinates stay as built. The riverbed is flat and gives each quad its own corners so
## every quad holds the whole texture, flipped vertically on even rows. Both are drawn with
## [ModelShaders] colours: the riverbed opaque, the water added to what is behind it. The source
## puts both at the back of its ordering table, so the shaders draw them at fixed depths behind
## every other polygon: the riverbed at [constant RIVERBED_DEPTH] and the water just in front of
## it at [constant WATER_DEPTH], so the boxes of the level select always cover them.

## Distance from the camera, in Godot units, at which the riverbed is drawn.
const RIVERBED_DEPTH: float = 200.0
## Distance from the camera, in Godot units, at which the water is drawn.
const WATER_DEPTH: float = 150.0
## Far clip distance a camera drawing the water needs.
const CAMERA_FAR: float = 256.0
## Source units the water may rise above or sink below rest (HIGH_SCORE_VIEW_WAVE_AMP_X plus _Z).
const WAVE_REACH: int = MenuWater.WAVE_AMP_X + MenuWater.WAVE_AMP_Z

const _PROJECTION_LINE: String = "\tPOSITION.xy *= projection_scale;\n"
const _BACKGROUND_LINES: String = """	vec4 background_clip = PROJECTION_MATRIX * vec4(0.0, 0.0, -background_depth, 1.0);
	POSITION.z = background_clip.z / background_clip.w * POSITION.w;
"""

static var _shaders: Dictionary[int, Shader] = {}

## The water surface: one surface whose vertex positions follow [method set_heights].
var water: ArrayMesh
## The flat riverbed.
var riverbed: ArrayMesh
## The water's current Godot vertex positions, in [MenuWater] vertex order.
var water_positions := PackedVector3Array()


## Both meshes, the water at the heights of viewport frame count [param frame].
static func create(frame: int = 0) -> MenuWaterMesh:
	var result := MenuWaterMesh.new()
	result.water_positions = positions(MenuWater.water_vertices(), _floats(MenuWater.heights(frame)))
	result.water = _water_mesh(result.water_positions)
	result.riverbed = _riverbed_mesh()
	return result


## Godot positions of source [param grid] vertices with Y replaced by [param heights].
static func positions(grid: Array[Vector3i], heights: PackedFloat32Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(grid.size())
	for index: int in grid.size():
		var at: Vector3i = grid[index]
		var height: float = heights[index] if index < heights.size() else 0.0
		result[index] = Vector3(at.x, -height, -at.z) / GameSpace.UNITS_PER_SQUARE
	return result


## Texture coordinates of every water vertex: vertex (i, j) shows fraction (i / X_NUM, j / Z_NUM)
## of the image.
static func water_uvs() -> PackedVector2Array:
	var result := PackedVector2Array()
	for j: int in MenuWater.WATER_Z_NUM + 1:
		for i: int in MenuWater.WATER_X_NUM + 1:
			result.append(Vector2(float(i) / MenuWater.WATER_X_NUM, float(j) / MenuWater.WATER_Z_NUM))
	return result


## The UV of texture corner [param corner] (0 top-left, 1 top-right, 2 bottom-left, 3
## bottom-right) of the whole image.
static func corner_uv(corner: int) -> Vector2:
	return Vector2(corner & 1, corner >> 1)


## Triangle vertex indices of the quads of a grid [param x_num] by [param z_num] quads whose
## quad (i, j) uses [method MenuWater.quad_vertices].
static func grid_indices(x_num: int, z_num: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for j: int in z_num:
		for i: int in x_num:
			var corners: PackedInt32Array = MenuWater.quad_vertices(i, j, x_num)
			var round_order: PackedInt32Array = [corners[0], corners[1], corners[3], corners[2]]
			for corner: int in ModelMeshBuilder.triangle_corners(4):
				result.append(round_order[corner])
	return result


## Moves the water vertices to source heights [param heights] in [MenuWater] vertex order.
func set_heights(heights: PackedFloat32Array) -> void:
	water_positions = positions(MenuWater.water_vertices(), heights)
	if water.get_surface_count() > 0:
		water.surface_update_vertex_region(0, 0, water_positions.to_byte_array())


## The water's material: [param texture] added to what is behind it, colour-keyed, two-sided.
static func water_material(texture: Texture2D, projection_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	return _material(texture, ModelShaders.Blend.ADD, WATER_DEPTH, projection_scale)


## The riverbed's opaque, two-sided material showing [param texture].
static func riverbed_material(texture: Texture2D, projection_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	return _material(texture, ModelShaders.Blend.OPAQUE, RIVERBED_DEPTH, projection_scale)


## The shader text of [method ModelShaders.shader_code] for [param blend] with every vertex
## drawn at the depth of a point [code]background_depth[/code] units ahead of the camera.
static func shader_code(textured: bool, blend: ModelShaders.Blend) -> String:
	var code: String = ModelShaders.shader_code(textured, blend, false, true)
	code = code.replace("uniform float depth_bias = 0.0;\n", "uniform float depth_bias = 0.0;\nuniform float background_depth = 1.0;\n")
	return code.replace(_PROJECTION_LINE, _PROJECTION_LINE + _BACKGROUND_LINES)


static func _material(texture: Texture2D, blend: ModelShaders.Blend, depth: float, projection_scale: Vector2) -> ShaderMaterial:
	var key: int = int(blend) * 2 + (1 if texture != null else 0)
	if not _shaders.has(key):
		var made := Shader.new()
		made.code = shader_code(texture != null, blend)
		_shaders[key] = made
	var material := ShaderMaterial.new()
	material.shader = _shaders[key]
	if texture != null:
		material.set_shader_parameter("image", texture)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("background_depth", depth)
	return material


static func _floats(values: PackedInt32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for value: int in values:
		result.append(value)
	return result


static func _colours(count: int, colour: int) -> PackedColorArray:
	var rgb: Vector3i = MenuWater.prim_rgb(colour)
	var result := PackedColorArray()
	result.resize(count)
	result.fill(Color8(rgb.x, rgb.y, rgb.z))
	return result


static func _bounds(x_num: int, z_num: int, x_len: int, z_len: int) -> AABB:
	var half: Vector3 = Vector3(x_len * x_num, WAVE_REACH * 2, z_len * z_num) / (2.0 * GameSpace.UNITS_PER_SQUARE)
	return AABB(-half, half * 2.0)


static func _water_mesh(at: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = at
	arrays[Mesh.ARRAY_TEX_UV] = water_uvs()
	arrays[Mesh.ARRAY_COLOR] = _colours(at.size(), MenuWater.WATER_PRIM_COLOUR)
	arrays[Mesh.ARRAY_INDEX] = grid_indices(MenuWater.WATER_X_NUM, MenuWater.WATER_Z_NUM)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = _bounds(MenuWater.WATER_X_NUM, MenuWater.WATER_Z_NUM, MenuWater.WATER_X_LEN, MenuWater.WATER_Z_LEN)
	return mesh


static func _riverbed_mesh() -> ArrayMesh:
	var grid: PackedVector3Array = positions(MenuWater.riverbed_vertices(), PackedFloat32Array())
	var at := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j: int in MenuWater.RIVERBED_Z_NUM:
		var texture_corners: PackedInt32Array = MenuWater.riverbed_corners(j)
		for i: int in MenuWater.RIVERBED_X_NUM:
			var corners: PackedInt32Array = MenuWater.quad_vertices(i, j, MenuWater.RIVERBED_X_NUM)
			var base: int = at.size()
			for corner: int in [0, 1, 3, 2]:
				at.append(grid[corners[corner]])
				uvs.append(corner_uv(texture_corners[corner]))
			for corner: int in ModelMeshBuilder.triangle_corners(4):
				indices.append(base + corner)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = at
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = _colours(at.size(), MenuWater.RIVERBED_PRIM_COLOUR)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = _bounds(MenuWater.RIVERBED_X_NUM, MenuWater.RIVERBED_Z_NUM, MenuWater.RIVERBED_X_LEN, MenuWater.RIVERBED_Z_LEN)
	return mesh
