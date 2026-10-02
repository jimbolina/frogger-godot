extends GutTest
## Native Godot camera samples checked against independent frozen-C projections.

func test_native_gameplay_camera_landmarks_with_predeclared_bounds() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.current = true
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = GameplayProjection.vertical_fov_degrees(viewport.size)
	camera.near = 0.01
	camera.far = 128.0
	await get_tree().process_frame
	var projection: Projection = camera.get_camera_projection()
	var roundoff: float = 128.0 * pow(2.0, -24.0) / (1.0 - 128.0 * pow(2.0, -24.0))
	assert_almost_eq(projection.x.x * 320.0, 512.0, roundoff * 640.0)
	assert_almost_eq(projection.y.y * 240.0 * 0.9375, 480.0, roundoff * 640.0)
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/gameplay_projection.csv").strip_edges().split("\n")
	var count: int = 0
	for line: String in lines:
		if line.begins_with("pose,"):
			continue
		var row: PackedStringArray = line.split(",")
		assert_eq(row.size(), 44)
		var matrix := PackedInt32Array()
		for index: int in range(31, 40):
			matrix.append(int(row[index]))
		for index: int in range(7, 10):
			matrix.append(int(row[index]))
		var snapshot := GameplayCameraSnapshot.new()
		snapshot.axis_x_12 = Vector3i(matrix[0], matrix[3], matrix[6])
		snapshot.axis_y_12 = Vector3i(matrix[1], matrix[4], matrix[7])
		snapshot.axis_z_12 = Vector3i(matrix[2], matrix[5], matrix[8])
		snapshot.source_world = Vector3i(matrix[9], matrix[10], matrix[11])
		camera.transform = GameplayProjection.camera_transform(snapshot)
		assert_eq(camera.transform.basis.x, GameSpace.normal(matrix[0], matrix[3], matrix[6]))
		assert_eq(camera.transform.basis.y, -GameSpace.normal(matrix[1], matrix[4], matrix[7]))
		assert_eq(camera.transform.basis.z, -GameSpace.normal(matrix[2], matrix[5], matrix[8]))
		var vertex: Vector3 = GameSpace.position(int(row[10]), int(row[11]), int(row[12]))
		var projected: Vector2 = camera.unproject_position(vertex)
		projected.y = 240.0 + (projected.y - 240.0) * GameplayProjection.clip_scale(viewport.size).y
		assert_true(absf(projected.x - float(row[29])) <= float(row[42]), "X " + line)
		assert_true(absf(projected.y - float(row[30])) <= float(row[43]), "Y " + line)
		count += 1
	assert_eq(count, 40)
