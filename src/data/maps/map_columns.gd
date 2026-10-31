class_name MapColumns
extends RefCounted
## Packs map polygons, grid stacks and grid squares into flat storage columns and rebuilds them.

## Integers per polygon record: type, index, offset, texture, flags, visible and five lengths.
const POLYGON_STRIDE: int = 11
## Integers per grid stack record: offset, square count, cliff byte and first square.
const GRID_STACK_STRIDE: int = 4
## Integers per grid square record: offset, flags, polygon pointer and polygon index.
const GRID_SQUARE_STRIDE: int = 4


## Fixed polygon fields followed by the lengths of its variable columns; values fit 32 bits.
static func polygon_records(polygons: Array[MapPolygon]) -> PackedInt32Array:
	var records := PackedInt32Array()
	records.resize(polygons.size() * POLYGON_STRIDE)
	var at: int = 0
	for polygon: MapPolygon in polygons:
		records[at] = polygon.type_index
		records[at + 1] = polygon.index
		records[at + 2] = polygon.source_offset
		records[at + 3] = polygon.texture_id
		records[at + 4] = polygon.flags
		records[at + 5] = 1 if polygon.visible else 0
		records[at + 6] = polygon.vertex_indices.size()
		records[at + 7] = polygon.grid_vertex_indices.size()
		records[at + 8] = polygon.raw_words.size()
		records[at + 9] = polygon.colors.size()
		records[at + 10] = polygon.uvs.size()
		at += POLYGON_STRIDE
	return records


## Vertex indices, grid vertex words and raw words of every polygon, concatenated.
static func polygon_words(polygons: Array[MapPolygon]) -> PackedInt32Array:
	var words := PackedInt32Array()
	for polygon: MapPolygon in polygons:
		words.append_array(polygon.vertex_indices)
		words.append_array(polygon.grid_vertex_indices)
		words.append_array(polygon.raw_words)
	return words


## Corner colors of every polygon, concatenated.
static func polygon_colors(polygons: Array[MapPolygon]) -> PackedColorArray:
	var colors := PackedColorArray()
	for polygon: MapPolygon in polygons:
		colors.append_array(polygon.colors)
	return colors


## Corner texture coordinates of every polygon, concatenated.
static func polygon_uvs(polygons: Array[MapPolygon]) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for polygon: MapPolygon in polygons:
		uvs.append_array(polygon.uvs)
	return uvs


## Rebuilds polygons from their columns, stopping at the first record the columns cannot supply.
static func build_polygons(records: PackedInt32Array, words: PackedInt32Array,
		colors: PackedColorArray, uvs: PackedVector2Array) -> Array[MapPolygon]:
	var result: Array[MapPolygon] = []
	var word_at: int = 0
	var color_at: int = 0
	var uv_at: int = 0
	for at: int in range(0, records.size() - POLYGON_STRIDE + 1, POLYGON_STRIDE):
		var vertex_count: int = records[at + 6]
		var grid_count: int = records[at + 7]
		var raw_count: int = records[at + 8]
		var color_count: int = records[at + 9]
		var uv_count: int = records[at + 10]
		var word_count: int = vertex_count + grid_count + raw_count
		if mini(mini(vertex_count, grid_count), mini(raw_count, mini(color_count, uv_count))) < 0:
			break
		if word_at + word_count > words.size() or color_at + color_count > colors.size() or uv_at + uv_count > uvs.size():
			break
		var polygon := MapPolygon.new()
		polygon.type_index = records[at]
		polygon.index = records[at + 1]
		polygon.source_offset = records[at + 2]
		polygon.texture_id = records[at + 3]
		polygon.flags = records[at + 4]
		polygon.visible = records[at + 5] != 0
		polygon.vertex_indices = words.slice(word_at, word_at + vertex_count)
		word_at += vertex_count
		polygon.grid_vertex_indices = words.slice(word_at, word_at + grid_count)
		word_at += grid_count
		polygon.raw_words = words.slice(word_at, word_at + raw_count)
		word_at += raw_count
		polygon.colors = colors.slice(color_at, color_at + color_count)
		color_at += color_count
		polygon.uvs = uvs.slice(uv_at, uv_at + uv_count)
		uv_at += uv_count
		result.append(polygon)
	return result


## Grid square fields, four integers per square, wide enough for unsigned 32-bit flags.
static func grid_square_records(squares: Array[MapGridSquare]) -> PackedInt64Array:
	var records := PackedInt64Array()
	records.resize(squares.size() * GRID_SQUARE_STRIDE)
	var at: int = 0
	for square: MapGridSquare in squares:
		records[at] = square.source_offset
		records[at + 1] = square.flags
		records[at + 2] = square.polygon_pointer
		records[at + 3] = square.polygon_index
		at += GRID_SQUARE_STRIDE
	return records


## Rebuilds grid squares from their records, ignoring a trailing partial record.
static func build_grid_squares(records: PackedInt64Array) -> Array[MapGridSquare]:
	var result: Array[MapGridSquare] = []
	for at: int in range(0, records.size() - GRID_SQUARE_STRIDE + 1, GRID_SQUARE_STRIDE):
		var square := MapGridSquare.new()
		square.source_offset = records[at]
		square.flags = records[at + 1]
		square.polygon_pointer = records[at + 2]
		square.polygon_index = records[at + 3]
		result.append(square)
	return result


## Grid stack fields, four integers per stack; values fit 32 bits.
static func grid_stack_records(stacks: Array[MapGridStack]) -> PackedInt32Array:
	var records := PackedInt32Array()
	records.resize(stacks.size() * GRID_STACK_STRIDE)
	var at: int = 0
	for stack: MapGridStack in stacks:
		records[at] = stack.source_offset
		records[at + 1] = stack.square_count
		records[at + 2] = stack.cliff_height_byte
		records[at + 3] = stack.first_square_index
		at += GRID_STACK_STRIDE
	return records


## Rebuilds grid stacks from their records, ignoring a trailing partial record.
static func build_grid_stacks(records: PackedInt32Array) -> Array[MapGridStack]:
	var result: Array[MapGridStack] = []
	for at: int in range(0, records.size() - GRID_STACK_STRIDE + 1, GRID_STACK_STRIDE):
		var stack := MapGridStack.new()
		stack.source_offset = records[at]
		stack.square_count = records[at + 1]
		stack.cliff_height_byte = records[at + 2]
		stack.first_square_index = records[at + 3]
		result.append(stack)
	return result
