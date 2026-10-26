class_name TerrainGridSetup
extends RefCounted
## Translates decoded GRID records to detached, validated gameplay definitions.

var error: String = ""
var definition: GridDefinition = null

## Preserves authored ordering and four stored vertex words; rejects unsupported geometry.
static func from_map(map: MapFile) -> TerrainGridSetup:
	var result := TerrainGridSetup.new()
	if not map.error.is_empty():
		result.error = "Cannot set up grid from an invalid map: " + map.error
		return result
	var packet: MapPacket = map.packets.get("GRID")
	if packet == null or packet.dimensions.x <= 0 or packet.dimensions.y <= 0:
		result.error = "Gameplay grid requires positive dimensions"
		return result
	if packet.cell_size != Vector2i(256, 256):
		result.error = "Gameplay grid requires 256-unit cells"
		return result
	if map.grid_stacks.size() != packet.dimensions.x * packet.dimensions.y or map.grid_squares.size() != packet.grid_square_count:
		result.error = "Gameplay grid record counts do not match its header"
		return result
	var grid := GridDefinition.new()
	grid.dimensions = packet.dimensions
	grid.base = Vector2i(-(256 * grid.dimensions.x) >> 1, -(256 * grid.dimensions.y) >> 1)
	var expected_index: int = 0
	for source: MapGridStack in map.grid_stacks:
		if source.first_square_index != expected_index or source.square_count < 0 or source.square_count > 255 or source.cliff_height_byte < 0 or source.cliff_height_byte > 255:
			result.error = "Gameplay grid stack range or cliff byte is invalid"
			return result
		expected_index += source.square_count
		var stack := GridStackDefinition.new()
		stack.source_offset = source.source_offset
		stack.first_square_index = source.first_square_index
		stack.square_count = source.square_count
		stack.cliff_height_byte = source.cliff_height_byte
		grid.stacks.append(stack)
	if expected_index != map.grid_squares.size():
		result.error = "Gameplay grid stack ranges do not cover its layers"
		return result
	for source: MapGridSquare in map.grid_squares:
		if source.polygon_index < 0 or source.polygon_index >= map.polygons.size():
			result.error = "Gameplay grid polygon identity is invalid"
			return result
		var polygon: MapPolygon = map.polygons[source.polygon_index]
		if polygon.grid_vertex_indices.size() != 4:
			result.error = "Gameplay grid requires a terrain triangle or quad"
			return result
		var square := GridSquareDefinition.new()
		square.source_offset = source.source_offset
		square.polygon_index = source.polygon_index
		square.polygon_source_offset = polygon.source_offset
		square.flags = source.flags
		for index: int in polygon.grid_vertex_indices:
			if index < 0 or index >= map.vertices.size():
				result.error = "Gameplay grid fourth or active vertex exceeds VRTX count"
				return result
			square.vertices.append(map.vertices[index])
		grid.squares.append(square)
	result.definition = grid
	return result
