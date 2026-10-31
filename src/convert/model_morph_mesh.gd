class_name ModelMorphMesh
extends Resource
## Immutable cel atlases and blend-free geometry for direct vertex-shader interpolation.

## The part's surfaces in their rest pose, without blend shapes.
@export var mesh: ArrayMesh
## One atlas per surface: the position and normal of every vertex in every cel.
@export var textures: Array[Texture2D] = []
## Vertices of each surface.
@export var vertex_counts := PackedInt32Array()

## Keeps decoded positions/normals for every cel, avoiding a transform-feedback mesh instance.
static func create(source: ArrayMesh, surface_cels: Array[Array]) -> ModelMorphMesh:
	if source == null or source.get_blend_shape_count() == 0:
		return null
	var result := ModelMorphMesh.new()
	result.mesh = ArrayMesh.new()
	result.mesh.custom_aabb = source.custom_aabb
	for surface: int in source.get_surface_count():
		var cels: Array = surface_cels[surface]
		var base: Array = cels[0]
		var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
		var width: int = mini(4096, vertices.size() * 2)
		var height: int = ceili(float(vertices.size() * 2 * cels.size()) / width)
		if height > 4096:
			return null
		var data := PackedFloat32Array()
		data.resize(width * height * 4)
		var offset: int = 0
		for cel: Array in cels:
			var positions: PackedVector3Array = cel[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = cel[Mesh.ARRAY_NORMAL]
			for index: int in positions.size():
				for value: Vector3 in [positions[index], normals[index]]:
					data[offset] = value.x
					data[offset + 1] = value.y
					data[offset + 2] = value.z
					offset += 4
		result.textures.append(ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, data.to_byte_array())))
		result.vertex_counts.append(vertices.size())
		result.mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), base)
		result.mesh.surface_set_material(surface, source.surface_get_material(surface))
		result.mesh.surface_set_name(surface, source.surface_get_name(surface))
	return result
