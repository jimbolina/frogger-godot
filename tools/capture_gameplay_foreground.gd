extends SceneTree
## Detached source-matched foreground capture; no authoritative gameplay tick runs.

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var fixture_path: String = ViewerArguments.value(args, "--fixture=")
	var output: String = ViewerArguments.value(args, "--output-directory=")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not parsed is Dictionary or output.is_empty():
		_fail("Foreground capture requires a fixture and external output directory")
		return
	var frozen: String = ProjectSettings.globalize_path("res://../froggy").replace("\\", "/").simplify_path().to_lower()
	var destination: String = output.replace("\\", "/").simplify_path().to_lower()
	if not ViewerCapture.external_folder(output) or destination == frozen or destination.begins_with(frozen + "/"):
		_fail("Foreground output must be outside both repositories")
		return
	var fixture: Dictionary = parsed
	var located: GameDataLocator.Located = ViewerArguments.locate_data(args)
	if not located.is_ok():
		_fail(located.error)
		return
	var data: GameData = GameData.open(located.source, located.version)
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(data)
	if not assets.error.is_empty():
		data.close()
		_fail(assets.error)
		return
	data.close()
	root.size = Vector2i(640, 480)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = GameplayProjection.vertical_fov_degrees(Vector2i(640, 480))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 128.0
	world.add_child(camera)
	camera.current = true
	var state := GameplayCameraSnapshot.new()
	var cb: Array = fixture["camera_basis"]
	state.axis_x_12 = Vector3i(_integer(cb[0]), _integer(cb[3]), _integer(cb[6]))
	state.axis_y_12 = Vector3i(_integer(cb[1]), _integer(cb[4]), _integer(cb[7]))
	state.axis_z_12 = Vector3i(_integer(cb[2]), _integer(cb[5]), _integer(cb[8]))
	var at: Array = fixture["camera"]
	state.source_world = Vector3i(_integer(at[0]), _integer(at[1]), _integer(at[2]))
	camera.transform = GameplayProjection.camera_transform(state)
	if not assets.player.set_action(_integer(fixture["action"])):
		_fail(assets.player.error)
		return
	assets.player.frame = _integer(fixture["cel"])
	var frog := AnimatedModelInstance.new()
	world.add_child(frog)
	frog.setup(assets.mesh, assets.player)
	var matrix := PackedInt32Array()
	for value: Variant in fixture["frog_basis"]:
		matrix.append(_integer(value))
	for value: Variant in fixture["frog"]:
		matrix.append(_integer(value))
	frog.transform = GameSpace.transform(matrix)
	for index: int in assets.hidden_parts:
		if index >= 0 and index < frog.part_nodes.size():
			frog.part_nodes[index].visible = false
	for part: MeshInstance3D in frog.part_nodes:
		if part.mesh == null:
			continue
		for surface: int in part.mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material is ShaderMaterial:
				(material as ShaderMaterial).set_shader_parameter("projection_scale", GameplayProjection.clip_scale(Vector2i(640, 480)))
	frog.apply_exact()
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var results: Array[Dictionary] = []
	var pose: ModelPose = assets.player.sample_pose()
	var model: MofStatic = assets.model.static_models[0]
	for landmark: Dictionary in fixture["landmarks"]:
		var part_index: int = _integer(landmark["part"])
		var vertex_index: int = _integer(landmark["vertex"])
		var vertices: PackedInt32Array = model.parts[part_index].partcels[0].vertices
		var offset: int = vertex_index * 3
		var local: Vector3 = GameSpace.position(vertices[offset], vertices[offset + 1], vertices[offset + 2])
		var pixel: Vector2 = camera.unproject_position(frog.transform * pose.transforms[part_index] * local)
		pixel.y = 240.0 + (pixel.y - 240.0) * GameplayProjection.clip_scale(Vector2i(640, 480)).y
		results.append({"part": part_index, "vertex": vertex_index, "screen": [pixel.x, pixel.y]})
	var image: Image = root.get_texture().get_image()
	if image.save_png(output.path_join("candidate-foreground.png")) != OK:
		_fail("Cannot save foreground image")
		return
	var facts: FileAccess = FileAccess.open(output.path_join("candidate-landmarks.json"), FileAccess.WRITE)
	facts.store_string(JSON.stringify({"landmarks": results, "size": [image.get_width(), image.get_height()]}))
	facts.close()
	world.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _integer(value: Variant) -> int:
	if value is int:
		var number: int = value
		return number
	if value is float:
		var number: float = value
		return int(number)
	return 0
