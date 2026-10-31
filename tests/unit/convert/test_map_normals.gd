extends GutTest
## Map corner normals: winding, flat faces and Gouraud smoothing within the crease angle.

const NEAR: Vector3 = Vector3(0.001, 0.001, 0.001)


func test_a_floor_faces_up_in_the_builder_winding() -> void:
	var floor_points := PackedVector3Array([GameSpace.position(0, 0, 256), GameSpace.position(256, 0, 256),
		GameSpace.position(0, 0, 0), GameSpace.position(256, 0, 0)])
	assert_almost_eq(MapNormals.face_normal(floor_points), Vector3.UP, NEAR)
	var triangle := PackedVector3Array([floor_points[0], floor_points[1], floor_points[2]])
	assert_almost_eq(MapNormals.face_normal(triangle), Vector3.UP, NEAR)
	var reversed := PackedVector3Array([floor_points[0], floor_points[2], floor_points[1]])
	assert_almost_eq(MapNormals.face_normal(reversed), Vector3.DOWN, NEAR, "the other winding faces down")
	var degenerate := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	assert_eq(MapNormals.face_normal(degenerate), Vector3.UP)


func test_floor_and_wall_keep_a_hard_crease() -> void:
	var normals := MapNormals.new()
	var vertices: Array[Vector3i] = _floor_vertices()
	vertices.append_array([Vector3i(0, -256, 256), Vector3i(256, -256, 256)])
	var polygons: Array[MapPolygon] = [_polygon(7, [0, 1, 2, 3]), _polygon(7, [4, 5, 0, 1])]
	normals.configure(vertices, polygons)
	assert_almost_eq(normals.face(1), Vector3.BACK, NEAR, "the wall faces over the floor")
	for corner: int in 4:
		assert_almost_eq(normals.corner_normal(0, corner), Vector3.UP, NEAR, "floor corner %d" % corner)
		assert_almost_eq(normals.corner_normal(1, corner), Vector3.BACK, NEAR, "wall corner %d" % corner)


func test_a_shallow_bend_smooths_shared_vertices() -> void:
	var normals := MapNormals.new()
	var vertices: Array[Vector3i] = _floor_vertices()
	vertices.append_array([Vector3i(0, -148, -256), Vector3i(256, -148, -256)])
	var polygons: Array[MapPolygon] = [_polygon(7, [0, 1, 2, 3]), _polygon(5, [2, 3, 4, 5])]
	normals.configure(vertices, polygons)
	var slope: Vector3 = normals.face(1)
	assert_gt(slope.dot(Vector3.UP), 0.5, "less than sixty degrees apart")
	assert_lt(slope.dot(Vector3.UP), 0.9)
	var blended: Vector3 = (Vector3.UP + slope).normalized()
	assert_almost_eq(normals.corner_normal(0, 0), Vector3.UP, NEAR, "an unshared corner keeps its face")
	assert_almost_eq(normals.corner_normal(0, 2), blended, NEAR)
	assert_almost_eq(normals.corner_normal(0, 3), blended, NEAR)
	assert_almost_eq(normals.corner_normal(1, 0), blended, NEAR)
	assert_almost_eq(normals.corner_normal(1, 3), slope, NEAR)


func test_flat_types_use_the_face_normal_on_every_corner() -> void:
	var normals := MapNormals.new()
	var vertices: Array[Vector3i] = _floor_vertices()
	vertices.append_array([Vector3i(0, -148, -256), Vector3i(256, -148, -256)])
	var polygons: Array[MapPolygon] = [_polygon(3, [0, 1, 2, 3]), _polygon(7, [2, 3, 4, 5]), _polygon(8, [0, 1])]
	normals.configure(vertices, polygons)
	for corner: int in 4:
		assert_almost_eq(normals.corner_normal(0, corner), Vector3.UP, NEAR, "flat corner %d" % corner)
	var blended: Vector3 = (Vector3.UP + normals.face(1)).normalized()
	assert_almost_eq(normals.corner_normal(1, 0), blended, NEAR, "a Gouraud neighbour still blends with the flat face")
	assert_eq(normals.corner_normal(2, 0), Vector3.UP, "lines point up")


func test_builder_writes_corner_normals() -> void:
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.vertices = _floor_vertices()
	scene.map.polygons.append(_polygon(1, [0, 1, 2, 3]))
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	scene.map.groups.append(group)
	scene.remap = TextureRemap.new()
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var arrays: Array = built.groups[0].surface_get_arrays(0)
	var written: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(written.size(), 6)
	for normal: Vector3 in written:
		assert_almost_eq(normal, Vector3.UP, NEAR)


func _floor_vertices() -> Array[Vector3i]:
	return [Vector3i(0, 0, 256), Vector3i(256, 0, 256), Vector3i(0, 0, 0), Vector3i(256, 0, 0)]


func _polygon(type_index: int, indices: Array[int]) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = type_index
	polygon.vertex_indices = PackedInt32Array(indices)
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	return polygon
