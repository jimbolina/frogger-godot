class_name ModelPolyPieces
extends RefCounted
## The polygons of a static model's first part as separate pieces, for the
## poly-piece pop (frozen [code]CreateMeshPolyPieces[/code] and
## [code]RenderPolyPiecePop[/code], EFFECTS.C 1915–2390).
##
## The game pops part 0 of static model 0 of the entity's model (the frog
## uses its flipbook's part 0), in partcel 0. Each polygon becomes a piece
## with its own origin. A triangle's origin is the C-truncated mean of its
## three corners ([code]/ 3[/code]); a quad's is the arithmetic shift of
## the corner sum ([code]>> 2[/code]). The stored corners become relative to
## that origin, as signed shorts.
##
## Only the eight F, FT, G and GT kinds are drawn. Environment-mapped and
## line kinds are counted by the source but never rendered; they are left
## out here and counted in [member skipped_polygons].
##
## A piece is drawn unlit: the source writes the polygon's own colour into
## every corner. Textures and blends use the model builder's surface keys,
## and every material is two-sided, because the pop draws its polygons
## without a facing test.

## The model part whose polygons pop.
const PART: int = 0
## The partcel whose vertices give the piece corners.
const REST_POSE: int = 0
## Material key of untextured pieces, as the model builder names it.
const PLAIN_KEY: String = "plain"
## Kinds the pop draws.
const DRAWN_TYPES: Array[int] = [MofPolygonType.F3, MofPolygonType.F4, MofPolygonType.FT3, MofPolygonType.FT4,
	MofPolygonType.G3, MofPolygonType.G4, MofPolygonType.GT3, MofPolygonType.GT4]


## One polygon of part 0 as a separately moving piece.
class Piece:
	extends RefCounted
	## Index of the polygon in part 0.
	var polygon_index: int = -1
	## The polygon's kind (see [MofPolygonType]).
	var type: int = MofPolygonType.F3
	## Centroid of the corners in model units, as the source computes it.
	var origin: Vector3i = Vector3i.ZERO
	## Corners relative to [member origin], in stored order.
	var vertices: Array[Vector3i] = []
	## u then v of each corner, 0 to 255 across the image; empty when untextured.
	var uvs := PackedByteArray()
	## Global texture id, or -1 when untextured.
	var image_id: int = -1
	## The resolved image, or null when untextured or missing.
	var image: VloImage
	## The polygon's stored colour, drawn unlit on every corner.
	var colour: Color = Color.BLACK
	## How the piece is mixed with what is behind it.
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
	## The model builder's surface key: [code]plain[/code] or [code]texture <id>[ blend <n>][/code].
	var material_key: String = PLAIN_KEY
	## One surface with its material, local to [member origin]; null before [method ModelPolyPieces.build].
	var mesh: ArrayMesh


## The drawn pieces in source order.
var pieces: Array[Piece] = []
## Polygons of part 0 the pop never draws (environment-mapped and line kinds).
var skipped_polygons: int = 0
## Texture ids no loaded bank has, each once. Their pieces are drawn untextured.
var missing_image_ids := PackedInt32Array()
## One shared material per surface key.
var materials: Dictionary[String, ShaderMaterial] = {}


## Builds the pieces of [param model] with meshes and materials. Textures are
## looked up in [param library], in [param preferred] first; a null library
## draws every piece untextured. Every texture is filtered linearly with
## mipmaps when [param linear_filter], otherwise only the upscaled ones.
static func build(model: MofStatic, library: TextureLibrary, preferred: VloFile,
		linear_filter: bool = false) -> ModelPolyPieces:
	var result: ModelPolyPieces = split(model)
	var missing: Dictionary[int, bool] = {}
	for piece: Piece in result.pieces:
		if MofPolygonType.is_textured(piece.type):
			piece.image = library.image_for_id(piece.image_id, preferred) if library != null else null
			if piece.image == null:
				missing[piece.image_id] = true
		piece.blend = ModelShaders.Blend.OPAQUE
		if piece.image != null and piece.image.has_flag(VloImage.FLAG_TRANSLUCENT):
			piece.blend = ModelShaders.blend_for_mode(piece.image.blend_mode())
		piece.material_key = PLAIN_KEY if piece.image == null else "texture %d%s" % [piece.image.texture_id,
			"" if piece.blend == ModelShaders.Blend.OPAQUE else " blend %d" % piece.blend]
		if not result.materials.has(piece.material_key):
			var texture: Texture2D = library.texture_for(piece.image) if piece.image != null else null
			result.materials[piece.material_key] = ModelShaders.material(texture, piece.blend, linear_filter, true, false)
		piece.mesh = piece_mesh(piece)
		piece.mesh.surface_set_material(0, result.materials[piece.material_key])
		piece.mesh.surface_set_name(0, piece.material_key)
	result.missing_image_ids = PackedInt32Array(missing.keys())
	result.missing_image_ids.sort()
	return result


## The geometry of [param model]'s pop pieces, without images, meshes or materials.
static func split(model: MofStatic) -> ModelPolyPieces:
	var result := ModelPolyPieces.new()
	if model == null or model.parts.size() <= PART:
		return result
	var part: MofPart = model.parts[PART]
	var cel: MofPart.Partcel = part.partcels[REST_POSE] if part.partcels.size() > REST_POSE else null
	for index: int in part.polygons.size():
		var polygon: MofPolygon = part.polygons[index]
		if cel == null or not DRAWN_TYPES.has(polygon.type) or polygon.vertices.size() != MofPolygonType.vertex_count(polygon.type):
			result.skipped_polygons += 1
			continue
		var corners: Array[Vector3i] = []
		for vertex: int in polygon.vertices:
			var at: int = vertex * 3
			corners.append(Vector3i(cel.vertices[at], cel.vertices[at + 1], cel.vertices[at + 2]) if at + 2 < cel.vertices.size() else Vector3i.ZERO)
		var piece: Piece = from_corners(corners)
		piece.polygon_index = index
		piece.type = polygon.type
		piece.uvs = polygon.uvs.duplicate()
		piece.image_id = polygon.image_id if polygon.is_textured() else -1
		piece.colour = Color(polygon.red / 255.0, polygon.green / 255.0, polygon.blue / 255.0)
		result.pieces.append(piece)
	return result


## A piece from three or four model-space [param corners]: the source
## centroid as its origin and the corners relative to it.
static func from_corners(corners: Array[Vector3i]) -> Piece:
	var piece := Piece.new()
	var sum: Vector3i = Vector3i.ZERO
	for corner: Vector3i in corners:
		sum += corner
	if corners.size() == 4:
		piece.origin = Vector3i(PlatformMath.s16(sum.x >> 2), PlatformMath.s16(sum.y >> 2), PlatformMath.s16(sum.z >> 2))
	else:
		piece.origin = Vector3i(PlatformMath.s16(PlatformMath.divide(sum.x, 3)), PlatformMath.s16(PlatformMath.divide(sum.y, 3)),
			PlatformMath.s16(PlatformMath.divide(sum.z, 3)))
	for corner: Vector3i in corners:
		piece.vertices.append(Vector3i(PlatformMath.s16(corner.x - piece.origin.x), PlatformMath.s16(corner.y - piece.origin.y),
			PlatformMath.s16(corner.z - piece.origin.z)))
	return piece


## The one-surface mesh of [param piece] around its origin, in Godot space,
## with no material. Corners follow the model builder's triangle order;
## texture coordinates are added only when the piece has an image and
## stored coordinates for every corner.
static func piece_mesh(piece: Piece) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var textured: bool = piece.image != null and piece.uvs.size() >= piece.vertices.size() * 2
	for corner: int in ModelMeshBuilder.triangle_corners(piece.vertices.size()):
		var at: Vector3i = piece.vertices[corner]
		vertices.append(GameSpace.position(at.x, at.y, at.z))
		colours.append(piece.colour)
		if textured:
			uvs.append(ModelMeshBuilder.texture_coordinate(piece.image, piece.uvs[corner * 2], piece.uvs[corner * 2 + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	if textured:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Every piece's origin, in piece order, for [method PolyPiecePopState.start].
func origins() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for piece: Piece in pieces:
		result.append(piece.origin)
	return result
