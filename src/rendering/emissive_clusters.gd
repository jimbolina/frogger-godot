class_name EmissiveClusters
extends RefCounted
## Groups a map's light-casting emissive surfaces into a few point lights.
##
## Only drawn polygons count: textured faces of visible groups, not lines.
## A polygon casts light when its image, or on an animated track any frame's
## image, is an [EmissiveImage] with [member EmissiveImage.light] set; the
## first such entry, the polygon's own image before the frames, gives its
## colour and energy. Polygons are binned by area-weighted centroid into
## horizontal cells of [constant CELL_SQUARES] grid squares, and a cell with
## less than [constant MIN_AREA] square units of glowing surface is dropped.
## Each remaining cell gives a [Cluster] [constant LIGHT_HEIGHT] above its
## centroid, with a range of [constant RANGE_SCALE] times the cell's
## half-diagonal, the area-weighted entry colour and an energy of
## [constant ENERGY] times the area-weighted light energy times the share of
## the cell covered. At most [constant MAX_LIGHTS] are kept, largest area
## first, ties in cell order. Positions are Godot units: one grid square is
## one unit; UV scrolling and water motion do not move the light.

## Cell side in grid squares.
const CELL_SQUARES: float = 4.0
## Smallest glowing area of a kept cell, in square grid squares.
const MIN_AREA: float = 1.0
## Height of each light above its cell's centroid, in grid squares.
const LIGHT_HEIGHT: float = 1.0
## Light range as a multiple of the cell's half-diagonal.
const RANGE_SCALE: float = 1.5
## Energy of a fully covered cell whose entries have light energy 1.
const ENERGY: float = 0.6
## Largest number of clusters.
const MAX_LIGHTS: int = 24
## Map polygon type of line primitives, which have no area.
const LINE_TYPE: int = 8

## One light over a cell of glowing surface: Godot position, range, colour and energy.
class Cluster extends RefCounted:
	## Light position in Godot units.
	var centre := Vector3.ZERO
	## Light range in grid squares.
	var radius: float = 0.0
	## Light colour, in stored (sRGB) colour like the entries.
	var colour := Color.WHITE
	## Light energy before the profile's scale.
	var energy: float = 0.0
	## Glowing surface area in the cell, in square grid squares.
	var area: float = 0.0

	func _init(at: Vector3 = Vector3.ZERO, light_range: float = 0.0, light_colour: Color = Color.WHITE,
			light_energy: float = 0.0, glowing_area: float = 0.0) -> void:
		centre = at
		radius = light_range
		colour = light_colour
		energy = light_energy
		area = glowing_area


class _Cell extends RefCounted:
	var key := Vector2i.ZERO
	var area: float = 0.0
	var weighted_centre := Vector3.ZERO
	var weighted_colour := Color(0, 0, 0, 0)
	var weighted_energy: float = 0.0


## The light clusters of [param scene]'s drawn polygons whose images
## [member MapSceneData.emissive] lists as casting light, largest first.
static func build(scene: MapSceneData) -> Array[Cluster]:
	var clusters: Array[Cluster] = []
	if scene == null or scene.map == null or scene.remap == null or scene.emissive.is_empty():
		return clusters
	var frames: Dictionary[int, PackedInt32Array] = {}
	for animation: MapAnimation in scene.map.animations:
		for target: int in animation.target_polygon_indices:
			frames[target] = animation.texture_ids
	var cells: Dictionary[Vector2i, _Cell] = {}
	var seen: Dictionary[int, bool] = {}
	for group: MapGroup in scene.map.groups:
		if not group.visible:
			continue
		for index: int in group.polygon_indices:
			if seen.has(index) or index < 0 or index >= scene.map.polygons.size():
				continue
			seen[index] = true
			var polygon: MapPolygon = scene.map.polygons[index]
			if polygon.type_index == LINE_TYPE or polygon.texture_id < 0:
				continue
			var track: PackedInt32Array = frames.get(index, PackedInt32Array())
			var entry: EmissiveImage = _light_entry(scene, polygon.texture_id, track)
			if entry != null:
				_add(cells, scene.map.vertices, polygon, entry)
	var kept: Array[_Cell] = []
	for cell: _Cell in cells.values():
		if cell.area >= MIN_AREA:
			kept.append(cell)
	kept.sort_custom(_larger_first)
	var cell_area: float = CELL_SQUARES * CELL_SQUARES
	var radius: float = RANGE_SCALE * CELL_SQUARES * sqrt(2.0) * 0.5
	for cell: _Cell in kept.slice(0, MAX_LIGHTS):
		var colour: Color = cell.weighted_colour / cell.area
		colour.a = 1.0
		var coverage: float = minf(cell.area / cell_area, 1.0)
		clusters.append(Cluster.new(cell.weighted_centre / cell.area + Vector3.UP * LIGHT_HEIGHT, radius,
			colour, ENERGY * cell.weighted_energy / cell.area * coverage, cell.area))
	return clusters


static func _light_entry(scene: MapSceneData, local_id: int, track: PackedInt32Array) -> EmissiveImage:
	var ids := PackedInt32Array([local_id])
	ids.append_array(track)
	for id: int in ids:
		var entry: EmissiveImage = scene.emissive.get(scene.remap.global_id(id), null)
		if entry != null and entry.light:
			return entry
	return null


static func _add(cells: Dictionary[Vector2i, _Cell], vertices: Array[Vector3i], polygon: MapPolygon, entry: EmissiveImage) -> void:
	var corners: PackedInt32Array = MapMeshBuilder.triangle_corners(polygon.vertex_indices.size())
	var area: float = 0.0
	var moment := Vector3.ZERO
	for start: int in range(0, corners.size(), 3):
		var points: Array[Vector3] = []
		for offset: int in 3:
			var raw: Vector3i = vertices[polygon.vertex_indices[corners[start + offset]]]
			points.append(GameSpace.position(raw.x, raw.y, raw.z))
		var triangle: float = (points[1] - points[0]).cross(points[2] - points[0]).length() * 0.5
		area += triangle
		moment += (points[0] + points[1] + points[2]) / 3.0 * triangle
	if area <= 0.0:
		return
	var centroid: Vector3 = moment / area
	var key := Vector2i(floori(centroid.x / CELL_SQUARES), floori(centroid.z / CELL_SQUARES))
	var cell: _Cell = cells.get(key, null)
	if cell == null:
		cell = _Cell.new()
		cell.key = key
		cells[key] = cell
	cell.area += area
	cell.weighted_centre += moment
	cell.weighted_colour += entry.colour * area
	cell.weighted_energy += entry.light_energy * area


static func _larger_first(a: _Cell, b: _Cell) -> bool:
	if a.area != b.area:
		return a.area > b.area
	if a.key.y != b.key.y:
		return a.key.y < b.key.y
	return a.key.x < b.key.x
