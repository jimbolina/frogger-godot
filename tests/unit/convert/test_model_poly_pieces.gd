extends GutTest
## Splitting a static model's first part into poly-pop pieces: centroids,
## relative corners, skipped kinds, meshes and material keys. Needs no game files.

class UpscaledCatalog extends AssetCatalog:
	func texture_set() -> TextureSet:
		return TextureSet.x4()

const VERTICES: Array[int] = [-64, -32, 48, 64, -32, 48, -64, -96, 48, 64, -96, 48, -1, -1, -1, -2, -2, -2, -2, -1, 0]


func _polygon(type: int, vertices: PackedInt32Array, colour: Color, image_id: int = -1) -> MofPolygon:
	var polygon := MofPolygon.new()
	polygon.type = type
	polygon.vertices = vertices
	polygon.red = colour.r8
	polygon.green = colour.g8
	polygon.blue = colour.b8
	if MofPolygonType.is_textured(type):
		polygon.image_id = image_id
		for corner: int in vertices.size():
			polygon.uvs.append_array(PackedByteArray([corner * 100, 255 - corner * 100]))
	return polygon


func _model(polygons: Array[MofPolygon]) -> MofStatic:
	var cel := MofPart.Partcel.new()
	cel.vertices = PackedInt32Array(VERTICES)
	var part := MofPart.new()
	part.partcels.append(cel)
	part.polygons = polygons
	var model := MofStatic.new()
	model.parts.append(part)
	return model


func _bank(flags: int = 0, blend_mode: int = 0) -> VloFile:
	var pixels: Array[int] = []
	for _i: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 7, flags, SyntheticVlo.abgr(pixels))
	spec.blend_mode = blend_mode
	var bank: VloFile = SyntheticVlo.bank([spec])
	assert_eq(bank.error, "")
	return bank


func _library(bank: VloFile) -> TextureLibrary:
	var library := TextureLibrary.new()
	library.add_bank(bank, "bank")
	return library


func _mixed() -> MofStatic:
	return _model([
		_polygon(MofPolygonType.G4, PackedInt32Array([0, 1, 3, 2]), Color8(10, 20, 30)),
		_polygon(MofPolygonType.NAMES.find("E3"), PackedInt32Array([0, 1, 2]), Color8(1, 2, 3)),
		_polygon(MofPolygonType.F3, PackedInt32Array([4, 5, 6]), Color8(200, 100, 50)),
	])


func test_centroids_follow_the_source_rounding() -> void:
	var quad: ModelPolyPieces.Piece = ModelPolyPieces.from_corners([Vector3i(-1, 0, 3), Vector3i(0, 0, 0), Vector3i.ZERO, Vector3i.ZERO] as Array[Vector3i])
	assert_eq(quad.origin, Vector3i(-1, 0, 0), "a quad shifts its corner sum, rounding down")
	var triangle: ModelPolyPieces.Piece = ModelPolyPieces.from_corners([Vector3i(-1, -1, -1), Vector3i(-2, -2, -2), Vector3i(-2, -1, 0)] as Array[Vector3i])
	assert_eq(triangle.origin, Vector3i(-1, -1, -1), "a triangle divides by three, truncating toward zero")
	assert_eq(triangle.vertices, [Vector3i(0, 0, 0), Vector3i(-1, -1, -1), Vector3i(-1, 0, 1)] as Array[Vector3i])


func test_part_zero_polygons_become_pieces_and_environment_kinds_are_skipped() -> void:
	var split: ModelPolyPieces = ModelPolyPieces.split(_mixed())
	assert_eq(split.pieces.size(), 2)
	assert_eq(split.skipped_polygons, 1)
	var quad: ModelPolyPieces.Piece = split.pieces[0]
	assert_eq(quad.polygon_index, 0)
	assert_eq(quad.type, MofPolygonType.G4)
	assert_eq(quad.origin, Vector3i(0, -64, 48))
	assert_eq(quad.vertices, [Vector3i(-64, 32, 0), Vector3i(64, 32, 0), Vector3i(64, -32, 0), Vector3i(-64, -32, 0)] as Array[Vector3i],
		"stored corner order, relative to the origin")
	assert_eq(quad.colour, Color8(10, 20, 30))
	assert_null(quad.mesh, "splitting builds no meshes")
	var triangle: ModelPolyPieces.Piece = split.pieces[1]
	assert_eq(triangle.polygon_index, 2)
	assert_eq(triangle.origin, Vector3i(-1, -1, -1))
	assert_eq(split.origins(), [Vector3i(0, -64, 48), Vector3i(-1, -1, -1)] as Array[Vector3i])


func test_plain_pieces_get_meshes_with_their_unlit_colour() -> void:
	var built: ModelPolyPieces = ModelPolyPieces.build(_mixed(), null, null)
	assert_eq(built.pieces.size(), 2)
	var quad_arrays: Array = built.pieces[0].mesh.surface_get_arrays(0)
	var quad_vertices: PackedVector3Array = quad_arrays[Mesh.ARRAY_VERTEX]
	assert_eq(quad_vertices.size(), 6)
	var a: Vector3 = GameSpace.position(-64, 32, 0)
	var b: Vector3 = GameSpace.position(64, 32, 0)
	var c: Vector3 = GameSpace.position(64, -32, 0)
	var d: Vector3 = GameSpace.position(-64, -32, 0)
	assert_eq(quad_vertices, PackedVector3Array([a, b, d, b, c, d]), "the model builder's quad corners")
	var colours: PackedColorArray = quad_arrays[Mesh.ARRAY_COLOR]
	assert_eq(colours[5], Color8(10, 20, 30))
	assert_eq(typeof(quad_arrays[Mesh.ARRAY_TEX_UV]), TYPE_NIL)
	var triangle_vertices: PackedVector3Array = built.pieces[1].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(triangle_vertices.size(), 3)
	assert_eq(built.pieces[0].material_key, ModelPolyPieces.PLAIN_KEY)
	assert_eq(built.materials.size(), 1)
	var material: ShaderMaterial = built.pieces[0].mesh.surface_get_material(0)
	assert_eq(material, built.materials[ModelPolyPieces.PLAIN_KEY], "pieces share one material per key")
	assert_true(material.shader.code.contains("cull_disabled"), "the pop draws both sides")
	assert_eq(built.pieces[1].mesh.surface_get_material(0), material)


func test_textured_pieces_use_the_model_builder_keys() -> void:
	var model: MofStatic = _model([_polygon(MofPolygonType.FT3, PackedInt32Array([4, 5, 6]), Color8(128, 128, 128), 7)])
	var bank: VloFile = _bank()
	var built: ModelPolyPieces = ModelPolyPieces.build(model, _library(bank), bank)
	var piece: ModelPolyPieces.Piece = built.pieces[0]
	assert_eq(piece.image_id, 7)
	assert_not_null(piece.image)
	assert_eq(piece.material_key, "texture 7")
	assert_eq(piece.blend, ModelShaders.Blend.OPAQUE)
	var uvs: PackedVector2Array = piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs.size(), 3)
	assert_eq(uvs[1], ModelMeshBuilder.texture_coordinate(piece.image, 100, 155))
	var translucent: VloFile = _bank(VloImage.FLAG_TRANSLUCENT, 1)
	var blended: ModelPolyPieces = ModelPolyPieces.build(model, _library(translucent), translucent)
	assert_eq(blended.pieces[0].blend, ModelShaders.Blend.ADD)
	assert_eq(blended.pieces[0].material_key, "texture 7 blend %d" % ModelShaders.Blend.ADD)


func test_textured_pieces_filter_as_the_library_texture_set_asks() -> void:
	var model: MofStatic = _model([_polygon(MofPolygonType.FT3, PackedInt32Array([4, 5, 6]), Color8(128, 128, 128), 7)])
	var bank: VloFile = _bank()
	var library: TextureLibrary = _library(bank)
	var retail: ShaderMaterial = ModelPolyPieces.build(model, library, bank).materials["texture 7"]
	assert_true(retail.shader.code.contains("filter_nearest"))
	library.catalog = UpscaledCatalog.new()
	var upscaled: ShaderMaterial = ModelPolyPieces.build(model, library, bank).materials["texture 7"]
	assert_true(upscaled.shader.code.contains("filter_linear_mipmap"))
	var chosen: ShaderMaterial = ModelPolyPieces.build(model, library, bank, false).materials["texture 7"]
	assert_true(chosen.shader.code.contains("filter_nearest"), "an explicit choice wins")


func test_missing_images_draw_plain_and_are_reported() -> void:
	var model: MofStatic = _model([_polygon(MofPolygonType.FT3, PackedInt32Array([4, 5, 6]), Color8(128, 128, 128), 9)])
	var built: ModelPolyPieces = ModelPolyPieces.build(model, TextureLibrary.new(), null)
	assert_eq(built.missing_image_ids, PackedInt32Array([9]))
	assert_eq(built.pieces[0].material_key, ModelPolyPieces.PLAIN_KEY)
	assert_eq(typeof(built.pieces[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]), TYPE_NIL)


func test_a_model_without_parts_has_no_pieces() -> void:
	var built: ModelPolyPieces = ModelPolyPieces.build(MofStatic.new(), null, null)
	assert_eq(built.pieces.size(), 0)
	assert_eq(built.skipped_polygons, 0)
