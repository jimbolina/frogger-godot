class_name MapFile
extends Resource
## Decoded final PC FROG 2.00 map. Coordinates stay in game units.

const TYPE_NAMES: Array[String] = ["F3", "F4", "FT3", "FT4", "G3", "G4", "GT3", "GT4", "G2"]
const TYPE_SIZES: Array[int] = [12, 12, 28, 28, 20, 24, 36, 40, 12]
const CORNERS: Array[int] = [3, 4, 3, 4, 3, 4, 3, 4, 2]
## Failure reason, or empty on success.
@export var error: String = ""
## Nonfatal format observations.
@export var warnings: Array[String] = []
## File length and version.
@export var size: int = 0
@export var version: String = ""
## Raw coordinates.
@export var vertices: Array[Vector3i] = []
## Polygons in type order, retaining unreferenced polygons; rebuilt lazily after loading.
var polygons: Array[MapPolygon]:
	get:
		if _polygons_packed:
			_polygons = MapColumns.build_polygons(_polygon_records, _polygon_words, _polygon_colors, _polygon_uvs)
			_polygons_packed = false
			_polygon_records = PackedInt32Array()
			_polygon_words = PackedInt32Array()
			_polygon_colors = PackedColorArray()
			_polygon_uvs = PackedVector2Array()
		return _polygons
	set(value):
		_polygons = value
		_polygons_packed = false
## Visible groups followed by the invisible group.
@export var groups: Array[MapGroup] = []
@export var group_dimensions: Vector2i = Vector2i.ZERO
@export var group_size: Vector2i = Vector2i.ZERO
@export var group_base: Vector3i = Vector3i.ZERO
## Stored lights and animation tracks.
@export var lights: Array[MapLight] = []
@export var animations: Array[MapAnimation] = []
## Bounded entity payloads, without gameplay decoding.
@export var entities: Array[MapEntitySpan] = []
## Source-ordered FORM collision grids, including empty entries.
@export var forms: Array[MapForm] = []
## Source-ordered camera zones; malformed records retain diagnostics.
@export var zones: Array[MapZone] = []
## Ordered collision stacks, without gameplay conversion; rebuilt lazily after loading.
var grid_stacks: Array[MapGridStack]:
	get:
		if _grid_stacks_packed:
			_grid_stacks = MapColumns.build_grid_stacks(_grid_stack_records)
			_grid_stacks_packed = false
			_grid_stack_records = PackedInt32Array()
		return _grid_stacks
	set(value):
		_grid_stacks = value
		_grid_stacks_packed = false
## Grid layers in stack order; rebuilt lazily after loading.
var grid_squares: Array[MapGridSquare]:
	get:
		if _grid_squares_packed:
			_grid_squares = MapColumns.build_grid_squares(_grid_square_records)
			_grid_squares_packed = false
			_grid_square_records = PackedInt64Array()
		return _grid_squares
	set(value):
		_grid_squares = value
		_grid_squares_packed = false
## Source-ordered paths with raw segment data.
@export var paths: Array[MapPath] = []
## General settings.
@export var general: MapGeneral = MapGeneral.new()
## Packet bounds and retained gameplay headers.
@export var packets: Dictionary[String, MapPacket] = {}
@export var polygon_counts: PackedInt32Array = PackedInt32Array()
@export var polygon_pointers: PackedInt32Array = PackedInt32Array()
## Polygon storage columns (see [MapColumns]); assigning them replaces [member polygons].
@export_storage var polygon_records: PackedInt32Array:
	get:
		return _polygon_records if _polygons_packed else MapColumns.polygon_records(_polygons)
	set(value):
		_polygon_records = value
		_polygons_packed = true
@export_storage var polygon_words: PackedInt32Array:
	get:
		return _polygon_words if _polygons_packed else MapColumns.polygon_words(_polygons)
	set(value):
		_polygon_words = value
		_polygons_packed = true
@export_storage var polygon_colors: PackedColorArray:
	get:
		return _polygon_colors if _polygons_packed else MapColumns.polygon_colors(_polygons)
	set(value):
		_polygon_colors = value
		_polygons_packed = true
@export_storage var polygon_uvs: PackedVector2Array:
	get:
		return _polygon_uvs if _polygons_packed else MapColumns.polygon_uvs(_polygons)
	set(value):
		_polygon_uvs = value
		_polygons_packed = true
## Grid stack storage column (see [MapColumns]); assigning it replaces [member grid_stacks].
@export_storage var grid_stack_records: PackedInt32Array:
	get:
		return _grid_stack_records if _grid_stacks_packed else MapColumns.grid_stack_records(_grid_stacks)
	set(value):
		_grid_stack_records = value
		_grid_stacks_packed = true
## Grid square storage column (see [MapColumns]); assigning it replaces [member grid_squares].
@export_storage var grid_square_records: PackedInt64Array:
	get:
		return _grid_square_records if _grid_squares_packed else MapColumns.grid_square_records(_grid_squares)
	set(value):
		_grid_square_records = value
		_grid_squares_packed = true
var _polygons: Array[MapPolygon] = []
var _polygons_packed: bool = false
var _polygon_records: PackedInt32Array = PackedInt32Array()
var _polygon_words: PackedInt32Array = PackedInt32Array()
var _polygon_colors: PackedColorArray = PackedColorArray()
var _polygon_uvs: PackedVector2Array = PackedVector2Array()
var _grid_stacks: Array[MapGridStack] = []
var _grid_stacks_packed: bool = false
var _grid_stack_records: PackedInt32Array = PackedInt32Array()
var _grid_squares: Array[MapGridSquare] = []
var _grid_squares_packed: bool = false
var _grid_square_records: PackedInt64Array = PackedInt64Array()

## Parses a final map, checking error before using the result.
static func read(bytes: PackedByteArray) -> MapFile:
	return MapFileReader.read(bytes)
