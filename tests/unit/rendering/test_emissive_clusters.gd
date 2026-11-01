extends GutTest
## Lava light clusters: drawn light-casting emissive polygons bin into cells by
## area-weighted centroid; small cells drop, the largest are kept in a stable
## order, and animated tracks count when any frame casts light.

const LAVA_ID: int = 201
const EDGE_ID: int = 202
const ROCK_ID: int = 203
const PLAIN_ID: int = 204
const LAVA_COLOUR: Color = Color(1.0, 0.6, 0.4)
const EDGE_COLOUR: Color = Color(1.0, 0.4, 0.2)

var _scene: MapSceneData


func before_each() -> void:
	_scene = MapSceneData.new()
	_scene.map = MapFile.new()
	_scene.remap = TextureRemap.new()
	_scene.remap.texture_ids = PackedInt32Array([PLAIN_ID, LAVA_ID, EDGE_ID, ROCK_ID])
	_scene.emissive = {
		LAVA_ID: _entry(LAVA_COLOUR, true, 1.0),
		EDGE_ID: _entry(EDGE_COLOUR, true, 0.5),
		ROCK_ID: _entry(Color.WHITE, false, 0.0),
	}
	_scene.map.groups.append(MapGroup.new())


func test_two_separated_patches_give_two_clusters() -> void:
	_patch(0.0, 0.0, 2, 1)
	_patch(12.0, 12.0, 2, 1)
	var clusters: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(clusters.size(), 2)
	for cluster: EmissiveClusters.Cluster in clusters:
		assert_almost_eq(cluster.area, 4.0, 1e-5)
		assert_almost_eq(cluster.energy, EmissiveClusters.ENERGY * 4.0 / 16.0, 1e-5, "light energy times the covered share")
		assert_eq(cluster.colour, LAVA_COLOUR)
		assert_almost_eq(cluster.radius, EmissiveClusters.RANGE_SCALE * EmissiveClusters.CELL_SQUARES * sqrt(2.0) / 2.0, 1e-5)
	assert_almost_eq(clusters[0].centre, Vector3(13.0, EmissiveClusters.LIGHT_HEIGHT, -13.0), Vector3.ONE * 1e-5,
		"equal areas keep cell order (far rows first), each at its centroid half a square up")
	assert_almost_eq(clusters[1].centre, Vector3(1.0, EmissiveClusters.LIGHT_HEIGHT, -1.0), Vector3.ONE * 1e-5)


func test_a_patch_under_the_minimum_area_is_dropped() -> void:
	_patch(0.0, 0.0, 2, 1)
	_quad(9.0, 9.0, 0.5, 1)
	var clusters: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(clusters.size(), 1)
	assert_almost_eq(clusters[0].area, 4.0, 1e-5)


func test_a_cell_mixes_colour_and_energy_by_area() -> void:
	_patch(0.0, 0.0, 1, 1, 3.0)
	_quad(3.0, 0.0, 1.0, 2)
	var clusters: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(clusters.size(), 1)
	assert_almost_eq(clusters[0].area, 10.0, 1e-5)
	var expected: Color = (LAVA_COLOUR * 9.0 + EDGE_COLOUR * 1.0) / 10.0
	assert_almost_eq(clusters[0].colour.g, expected.g, 1e-5)
	assert_almost_eq(clusters[0].colour.b, expected.b, 1e-5)
	assert_almost_eq(clusters[0].energy, EmissiveClusters.ENERGY * (9.0 * 1.0 + 1.0 * 0.5) / 10.0 * (10.0 / 16.0), 1e-5)


func test_the_cap_keeps_the_largest_cells_in_a_stable_order() -> void:
	for cell: int in EmissiveClusters.MAX_LIGHTS + 4:
		_quad(cell * 8.0, 0.0, 1.0 + (cell % 3) * 0.5, 1)
	var clusters: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(clusters.size(), EmissiveClusters.MAX_LIGHTS)
	for index: int in range(1, clusters.size()):
		var before: EmissiveClusters.Cluster = clusters[index - 1]
		var after: EmissiveClusters.Cluster = clusters[index]
		assert_true(before.area > after.area or (before.area == after.area and before.centre.x < after.centre.x),
			"cluster %d follows by area, then by cell" % index)
	assert_almost_eq(clusters[-1].area, 1.0, 1e-5)
	assert_almost_eq(clusters[-1].centre.x, 15 * 8.0 + 0.5, 1e-5, "the last smallest cells kept are the first in cell order")


func test_the_result_is_deterministic() -> void:
	for cell: int in 6:
		_quad(cell * 5.0, cell * 3.0, 1.5, 1 + cell % 2)
	var first: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	var second: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(first.size(), second.size())
	for index: int in first.size():
		assert_eq(first[index].centre, second[index].centre)
		assert_eq(first[index].energy, second[index].energy)
		assert_eq(first[index].colour, second[index].colour)


func test_an_animated_polygon_counts_when_one_frame_casts_light() -> void:
	_patch(0.0, 0.0, 2, 0)
	var track := MapAnimation.new()
	track.texture_ids = PackedInt32Array([0, 3, 1])
	for index: int in 4:
		track.target_polygon_indices.append(index)
	_scene.map.animations.append(track)
	var clusters: Array[EmissiveClusters.Cluster] = EmissiveClusters.build(_scene)
	assert_eq(clusters.size(), 1)
	assert_eq(clusters[0].colour, LAVA_COLOUR, "the casting frame, not the non-casting rock")
	track.texture_ids = PackedInt32Array([0, 3])
	assert_eq(EmissiveClusters.build(_scene).size(), 0, "no frame casts light")


func test_invisible_groups_and_unreferenced_polygons_are_ignored() -> void:
	_patch(0.0, 0.0, 2, 1)
	_scene.map.groups[0].visible = false
	assert_eq(EmissiveClusters.build(_scene).size(), 0)
	_scene.map.groups[0].visible = true
	var drawn: PackedInt32Array = _scene.map.groups[0].polygon_indices
	_scene.map.groups[0].polygon_indices = PackedInt32Array()
	assert_eq(EmissiveClusters.build(_scene).size(), 0, "polygons outside every group are not drawn")
	_scene.map.groups[0].polygon_indices = drawn
	assert_eq(EmissiveClusters.build(_scene).size(), 1)


func test_entries_without_light_lines_and_untextured_faces_are_ignored() -> void:
	_patch(0.0, 0.0, 2, 3)
	_patch(8.0, 0.0, 2, 0)
	assert_eq(EmissiveClusters.build(_scene).size(), 0, "hot rock and plain images cast no light")
	_patch(16.0, 0.0, 2, 1)
	for index: int in range(_scene.map.polygons.size() - 4, _scene.map.polygons.size()):
		_scene.map.polygons[index].type_index = EmissiveClusters.LINE_TYPE
	assert_eq(EmissiveClusters.build(_scene).size(), 0, "lines have no area")
	for index: int in range(_scene.map.polygons.size() - 4, _scene.map.polygons.size()):
		_scene.map.polygons[index].type_index = 3
		_scene.map.polygons[index].texture_id = -1
	assert_eq(EmissiveClusters.build(_scene).size(), 0, "untextured faces")


func test_a_scene_without_emissive_images_or_a_map_has_no_clusters() -> void:
	_patch(0.0, 0.0, 2, 1)
	_scene.emissive = {}
	assert_eq(EmissiveClusters.build(_scene).size(), 0)
	assert_eq(EmissiveClusters.build(MapSceneData.new()).size(), 0)
	assert_eq(EmissiveClusters.build(null).size(), 0)


func _entry(colour: Color, light: bool, energy: float) -> EmissiveImage:
	var entry := EmissiveImage.new()
	entry.colour = colour
	entry.strength = 1.0
	entry.light = light
	entry.light_energy = energy
	return entry


func _patch(x: float, z: float, squares: int, texture: int, size: float = 1.0) -> void:
	for row: int in squares:
		for column: int in squares:
			_quad(x + column * size, z + row * size, size, texture)


func _quad(x: float, z: float, size: float, texture: int) -> void:
	var first: int = _scene.map.vertices.size()
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var godot := Vector3(x + corner.x * size, 0.0, -(z + corner.y * size))
		_scene.map.vertices.append(GameSpace.to_game(godot))
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([first, first + 1, first + 2, first + 3])
	polygon.texture_id = texture
	_scene.map.groups[0].polygon_indices.append(_scene.map.polygons.size())
	_scene.map.polygons.append(polygon)
