extends SceneTree
## Compares native morphs and cel-shader geometry/lighting in paired offscreen views.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var folder: String = ViewerArguments.value(OS.get_cmdline_user_args(), "--output=")
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		push_error(issue)
		quit(1)
		return
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(1, -1, 0), Vector3(0, -1, 0)])
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var positions := PackedVector3Array()
	var cel_normals := PackedVector3Array()
	for vertex: Vector3 in vertices:
		normals.append(Vector3.BACK)
		colors.append(Color8(128, 64, 192))
		positions.append(vertex + Vector3.RIGHT)
		cel_normals.append(Vector3(1, 0, 1).normalized())
	var base: Array = []
	base.resize(Mesh.ARRAY_MAX)
	base[Mesh.ARRAY_VERTEX] = vertices
	base[Mesh.ARRAY_NORMAL] = normals
	base[Mesh.ARRAY_COLOR] = colors
	var cel: Array = []
	cel.resize(Mesh.ARRAY_MAX)
	cel[Mesh.ARRAY_VERTEX] = positions
	cel[Mesh.ARRAY_NORMAL] = cel_normals
	var source := ArrayMesh.new()
	source.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	source.add_blend_shape("Cel1")
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, [cel])
	source.custom_aabb = AABB(Vector3(0, -1, -0.01), Vector3(2, 1, 0.02))
	var original: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true)
	source.surface_set_material(0, original)
	var cels: Array[Array] = [[base, cel]]
	var morph: ModelMorphMesh = ModelMorphMesh.create(source, cels)
	var instances: Array[MeshInstance3D] = []
	var materials: Array[ShaderMaterial] = []
	var views: Array[SubViewport] = []
	for candidate_mesh: ArrayMesh in [source, morph.mesh]:
		var view := SubViewport.new()
		view.size = Vector2i(256, 256)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 4.0
		camera.position = Vector3(1, -0.5, 5)
		view.add_child(camera)
		var instance := MeshInstance3D.new()
		instance.mesh = candidate_mesh
		instance.custom_aabb = source.custom_aabb
		var material: ShaderMaterial = original.duplicate() as ShaderMaterial
		if candidate_mesh == morph.mesh:
			material.set_shader_parameter("cel_enabled", true)
			material.set_shader_parameter("cel_texture", morph.textures[0])
			material.set_shader_parameter("cel_vertex_count", 6)
			material.set_shader_parameter("cel_pair", Vector2i(0, 1))
		instance.set_surface_override_material(0, material)
		view.add_child(instance)
		views.append(view)
		instances.append(instance)
		materials.append(material)
	var rows: Array[Dictionary] = []
	var accepted: bool = true
	for lit: bool in [false, true]:
		if lit:
			for material: ShaderMaterial in materials:
				material.set_shader_parameter("source_lighting", true)
				material.set_shader_parameter("source_ambient", Vector3(1024, 1024, 1024))
				material.set_shader_parameter("source_direction0", Vector3.RIGHT)
				material.set_shader_parameter("source_colour0", Vector3(2048, 1024, 3072))
		for weight: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			instances[0].set_blend_shape_value(0, weight)
			materials[1].set_shader_parameter("cel_weight", weight)
			await process_frame
			await RenderingServer.frame_post_draw
			await process_frame
			await RenderingServer.frame_post_draw
			var native: Image = views[0].get_texture().get_image()
			var candidate: Image = views[1].get_texture().get_image()
			var maximum: int = 0
			var mismatches: int = 0
			for y: int in native.get_height():
				for x: int in native.get_width():
					var a: Color = native.get_pixel(x, y)
					var b: Color = candidate.get_pixel(x, y)
					var difference: int = maxi(absi(a.r8 - b.r8), maxi(absi(a.g8 - b.g8), absi(a.b8 - b.b8)))
					maximum = maxi(maximum, difference)
					mismatches += int(difference > 1)
			var name: String = "%s-%03d" % ["lit" if lit else "unlit", roundi(weight * 100)]
			if native.save_png(folder.path_join(name + "-native.png")) != OK or candidate.save_png(folder.path_join(name + "-cel.png")) != OK:
				push_error("Cannot save morph comparison captures")
				quit(1)
				return
			rows.append({"case": name, "maximum_channel_difference": maximum, "pixels_over_one": mismatches})
			accepted = accepted and mismatches == 0
	var output := FileAccess.open(folder.path_join("comparison.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"accepted": accepted, "cases": rows}, "\t"))
	output.close()
	print("model_morph: accepted=%s cases=%d" % [accepted, rows.size()])
	for view: SubViewport in views:
		view.queue_free()
	instances.clear()
	views.clear()
	await process_frame
	quit.call_deferred(0 if accepted else 1)
