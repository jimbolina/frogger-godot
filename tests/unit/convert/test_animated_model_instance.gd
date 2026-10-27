extends GutTest
## Rendering keeps reusable geometry, interpolates only motion, and resets at discontinuities.


func _flipbook() -> MofFile:
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)]))
	var part: MofPart = file.static_models[0].parts[0]
	var cel := MofPart.Partcel.new()
	cel.vertices = part.partcels[0].vertices.duplicate()
	cel.normals = part.partcels[0].normals.duplicate()
	for at: int in range(0, cel.vertices.size(), 3):
		cel.vertices[at] += 512
	part.partcels.append(cel)
	part.partcel_count = 2
	var action := MofPart.FlipbookAction.new()
	action.start = 0
	action.frame_count = 2
	part.flipbook_actions.append(action)
	return file


func _instance(file: MofFile) -> AnimatedModelInstance:
	var mesh: ModelMesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(file)
	var instance := AnimatedModelInstance.new()
	add_child_autofree(instance)
	instance.setup(mesh, ModelAnimationPlayer.new(file))
	return instance



func _weight(instance: AnimatedModelInstance, blend: int) -> float:
	var material := instance.part_nodes[0].get_surface_override_material(0) as ShaderMaterial
	var pair: Vector2i = material.get_shader_parameter("cel_pair")
	var weight: float = material.get_shader_parameter("cel_weight")
	return (weight if pair.y == blend + 1 else 0.0) + (1.0 - weight if pair.x == blend + 1 else 0.0)

func test_cel_atlas_geometry_and_pose_uniforms_are_shared_only_when_immutable() -> void:
	var first: AnimatedModelInstance = _instance(_flipbook())
	var second := AnimatedModelInstance.new()
	add_child_autofree(second)
	second.setup(first.model_mesh, ModelAnimationPlayer.new(_flipbook()))
	var morph: ModelMorphMesh = first.model_mesh.morph_meshes[0]
	assert_eq(morph.mesh.get_blend_shape_count(), 0)
	assert_same(first.part_nodes[0].mesh, second.part_nodes[0].mesh)
	assert_eq(morph.vertex_counts, PackedInt32Array([6]))
	var image: Image = morph.textures[0].get_image()
	assert_eq(image.get_size(), Vector2i(12, 2))
	assert_eq(image.get_pixel(0, 0), Color(0, 0, 0, 0))
	assert_eq(image.get_pixel(0, 1), Color(2, 0, 0, 0))
	first.smoothing_enabled = true
	first.advance_tick()
	first.render(0.25)
	assert_eq(_weight(first, 0), 0.25)
	assert_eq(_weight(second, 0), 0.0)
	assert_ne(first.part_nodes[0].get_surface_override_material(0), second.part_nodes[0].get_surface_override_material(0))

func test_matrix_changes_both_axes_and_scales_only_translation() -> void:
	var converted: Transform3D = GameSpace.transform(PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 256, -512, 768]))
	assert_eq(converted.origin, Vector3(1, 2, -3))
	assert_eq(converted.basis * Vector3.RIGHT, Vector3.DOWN)
	assert_eq(converted.basis * Vector3.UP, Vector3.RIGHT)
	assert_eq(GameSpace.transform(PackedInt32Array()), Transform3D.IDENTITY)
	var scaled_rotation := Basis(Vector3(2, 1, 0) / sqrt(2.0), Vector3(-2, 1, 0) / sqrt(2.0), Vector3.BACK)
	assert_almost_eq(ModelMeshBuilder._basis_extent(scaled_rotation), 2.0, 0.00001, "bounds cover rotated nonuniform scales")

func test_source_appearance_is_instance_local_and_preserves_shared_materials() -> void:
	var first: AnimatedModelInstance = _instance(_flipbook())
	var second := AnimatedModelInstance.new()
	add_child_autofree(second)
	second.setup(first.model_mesh, ModelAnimationPlayer.new(_flipbook()))
	var source: ShaderMaterial = first.model_mesh.part_meshes[0].surface_get_material(0) as ShaderMaterial
	var original_lighting: Variant = source.get_shader_parameter("source_lighting")
	var lighting := MapLighting.new()
	lighting.ambient = Vector3(1024, 1024, 1024)
	first.set_source_lighting(lighting, Vector3i(0, 64, 255), Vector3i(64, 64, 192), true, true)
	second.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	var a: ShaderMaterial = first.part_nodes[0].get_surface_override_material(0) as ShaderMaterial
	var b: ShaderMaterial = second.part_nodes[0].get_surface_override_material(0) as ShaderMaterial
	assert_ne(a, b)
	assert_ne(a, source)
	var ambient_a: Vector3 = a.get_shader_parameter("source_ambient")
	var ambient_b: Vector3 = b.get_shader_parameter("source_ambient")
	assert_eq(ambient_a, Vector3(0, 512, 6112))
	assert_eq(ambient_b, Vector3(1024, 1024, 1024))
	var unchanged: bool = source.get_shader_parameter("source_lighting") == original_lighting
	assert_true(unchanged)
	first.advance_tick()
	assert_same(first.part_nodes[0].get_surface_override_material(0), a)
	first.set_source_lighting(lighting, Vector3i(0, 64, 255), Vector3i(64, 64, 192), true, true)
	assert_same(first.part_nodes[0].get_surface_override_material(0), a)
	lighting.ambient = Vector3(2048, 2048, 2048)
	lighting.directions.append(Vector3.RIGHT)
	lighting.colours.append(Vector3(256, 512, 1024))
	second.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	var changed_ambient: Vector3 = b.get_shader_parameter("source_ambient")
	var changed_colour: Vector3 = b.get_shader_parameter("source_colour0")
	assert_eq(changed_ambient, lighting.ambient)
	assert_eq(changed_colour, lighting.colours[0])
	lighting.colours[0] = Vector3(128, 256, 512)
	second.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	changed_colour = b.get_shader_parameter("source_colour0")
	assert_eq(changed_colour, lighting.colours[0], "in-place edits invalidate the lighting cache")
	lighting.directions[0] = Vector3.FORWARD
	second.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	var changed_direction: Vector3 = b.get_shader_parameter("source_direction0")
	assert_eq(changed_direction, Vector3.FORWARD, "direction-only changes invalidate their uniforms")
	lighting.directions.clear()
	lighting.colours.clear()
	second.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	changed_direction = b.get_shader_parameter("source_direction0")
	changed_colour = b.get_shader_parameter("source_colour0")
	assert_eq(changed_direction, Vector3.ZERO)
	assert_eq(changed_colour, Vector3.ZERO, "removed lights clear previously populated slots")


func test_flipbook_geometry_is_prebuilt_and_bounds_cover_all_cels() -> void:
	var instance: AnimatedModelInstance = _instance(_flipbook())
	var mesh: ArrayMesh = instance.model_mesh.part_meshes[0]
	assert_eq(mesh.get_blend_shape_count(), 1)
	assert_eq(mesh.blend_shape_mode, Mesh.BLEND_SHAPE_MODE_NORMALIZED)
	assert_eq(instance.model_mesh.bounds, AABB(Vector3(0, -1, 0), Vector3(3, 1, 0)))
	assert_eq(instance.model_mesh.action_bounds[0], instance.model_mesh.bounds)
	var material: Material = mesh.surface_get_material(0)
	instance.advance_tick()
	assert_eq(_weight(instance, 0), 1.0)
	assert_same(instance.part_nodes[0].mesh, instance.model_mesh.morph_meshes[0].mesh)
	assert_same(mesh.surface_get_material(0), material)
	instance.advance_tick()
	assert_eq(_weight(instance, 0), 0.0)
	assert_same(instance.part_nodes[0].mesh, instance.model_mesh.morph_meshes[0].mesh)


func test_smoothing_reset_avoids_blending_across_loop_seek_and_toggle() -> void:
	var instance: AnimatedModelInstance = _instance(_flipbook())
	assert_false(instance.smoothing_enabled)
	instance.smoothing_enabled = true
	instance.advance_tick()
	instance.render(0.25)
	assert_eq(_weight(instance, 0), 0.25)
	instance.advance_tick()
	instance.render(0.25)
	assert_eq(_weight(instance, 0), 0.0, "a loop draws its first sample exactly")
	instance.player.seek_tick(1)
	instance.render(0.25)
	assert_eq(_weight(instance, 0), 1.0, "seeks reset the interpolation history")
	instance.player.restart()
	instance.apply_exact()
	instance.advance_tick()
	instance.smoothing_enabled = false
	instance.render(0.0)
	assert_eq(_weight(instance, 0), 1.0)
	assert_eq(instance.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)

func test_skipped_pose_drawing_clears_previously_displayed_morph_weights() -> void:
	var file: MofFile = _flipbook()
	var part: MofPart = file.static_models[0].parts[0]
	part.partcels.append(part.partcels[0])
	part.partcel_count = 3
	part.flipbook_actions[0].frame_count = 3
	var instance: AnimatedModelInstance = _instance(file)
	instance.smoothing_enabled = true
	instance.advance_tick()
	instance.render(1.0)
	assert_eq(_weight(instance, 0), 1.0)
	instance.player.frame = 2
	instance.capture_pose()
	instance.player.frame = 0
	instance.capture_pose()
	instance.render(0.5)
	assert_eq(_weight(instance, 0), 0.0)
	assert_eq(_weight(instance, 1), 0.5)

func test_unchanged_geometry_settles_interpolation_and_keeps_visibility_tick_driven() -> void:
	var instance: AnimatedModelInstance = _instance(_flipbook())
	instance.smoothing_enabled = true
	instance.advance_tick()
	instance.render(0.5)
	assert_eq(_weight(instance, 0), 0.5)
	var retained: ModelPose = instance._current
	instance.player.end_mode = ModelAnimationPlayer.EndMode.HIDE
	instance.advance_tick()
	assert_same(instance._current, retained, "unchanged geometry does not allocate another pose")
	assert_false(instance.visible, "same-cel hiding still changes on its authoritative tick")
	assert_eq(_weight(instance, 0), 1.0, "holding settles the previous interpolation")
	for fraction: float in [0.25, 0.75, 1.0]:
		instance.render(fraction)
	assert_eq(instance.player.tick, 2)
	assert_eq(_weight(instance, 0), 1.0)


func test_skeletal_smoothing_retains_exact_endpoints_and_authoritative_state() -> void:
	var bytes: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)])
	var first: MofTransform = SyntheticMofAnimation.transform(0, [4095, 0, 0, 0, 4095, 0, 0, 0, 4095, 0, 0, 0])
	var second: MofTransform = SyntheticMofAnimation.transform(0, [4095, 0, 0, 0, 4095, 0, 0, 0, 4095, 512, 0, 0])
	var action: MofAnimated.Action = SyntheticMofAnimation.action(1, 2, [0, 1], [0, 1])
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([bytes], 0, [first, second], [action]))
	assert_eq(file.error, "")
	var instance: AnimatedModelInstance = _instance(file)
	var exact: Transform3D = instance.part_nodes[0].transform
	instance.smoothing_enabled = true
	instance.advance_tick()
	instance.render(0.0)
	assert_eq(instance.part_nodes[0].transform, exact, "fixed-point bases must not be normalized at interpolation endpoints")
	instance.render(0.5)
	assert_eq(instance.part_nodes[0].position.x, 1.0)
	assert_eq(instance.player.tick, 1)
	assert_eq(instance.player.frame, 1)
	instance.render(1.0)
	assert_eq(instance.part_nodes[0].transform, instance.player.sample_pose().transforms[0])
	assert_true(instance.model_mesh.bounds.has_point(Vector3(2, 0, 0)), "action bounds include translated poses")


func test_smoothing_a_zero_scale_stays_finite() -> void:
	var bytes: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)])
	var first: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1])
	var second: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 512, 0, 0, 32, 0, 32, 1])
	var action: MofAnimated.Action = SyntheticMofAnimation.action(1, 2, [0, 1], [0, 1])
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([bytes], 5, [first, second], [action]))
	var instance: AnimatedModelInstance = _instance(file)
	instance.smoothing_enabled = true
	instance.advance_tick()
	instance.render(0.5)
	assert_true(instance.part_nodes[0].transform.is_finite())
	assert_eq(instance.part_nodes[0].basis.y.length(), 0.5)
	assert_eq(instance.part_nodes[0].position.x, 1.0)


func _texture_bank(include_original: bool = true) -> VloFile:
	var first_pixels: Array[int] = []
	for _pixel: int in 10 * 6:
		first_pixels.append_array([200, 120, 40])
	var second_pixels: Array[int] = []
	for _pixel: int in 20 * 12:
		second_pixels.append_array([40, 120, 200])
	var first: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 7, VloImage.FLAG_TRANSLUCENT,
		SyntheticVlo.abgr(first_pixels))
	first.blend_mode = 0
	var second: SyntheticVlo.Spec = SyntheticVlo.spec(16, 8, 4, 8, 0, SyntheticVlo.abgr(second_pixels))
	second.blend_mode = 1
	var specs: Array[SyntheticVlo.Spec] = [second]
	if include_original:
		specs.push_front(first)
	return VloFile.parse(SyntheticVlo.build_vlo(specs))


func test_animated_texture_keeps_original_pixel_offsets_and_uses_current_blend_rate() -> void:
	var spec: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.F4)
	spec.polygons.append(SyntheticMof.polygon(MofPolygonType.FT3, [0, 1, 2], [0], Color8(128, 128, 128), 7, [0, 0, 255, 0, 255, 255]))
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([spec]))
	var part: MofPart = file.static_models[0].parts[0]
	var target := MofPart.TextureTarget.new()
	target.polygon_type = MofPolygonType.FT3
	target.polygon_index = 1
	target.list_index = 0
	part.texture_targets.append(target)
	var list := MofPart.TextureAnimation.new()
	list.image_ids = PackedInt32Array([8, 999])
	list.durations = PackedInt32Array([1, 1])
	part.texture_lists.append(list)
	var bank: VloFile = _texture_bank()
	assert_eq(bank.error, "")
	var library := TextureLibrary.new()
	library.add_bank(bank, "bank")
	var mesh: ModelMesh = ModelMeshBuilder.new(library, bank).build_animated(file)
	assert_eq(mesh.surface_count, 2, "mixed polygon kinds locate the target by its global index")
	var track: ModelMesh.TextureTrack = mesh.texture_tracks[0][0]
	var uvs: PackedVector2Array = mesh.part_meshes[0].surface_get_arrays(track.surface)[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[1], Vector2(8, 0), "original width stays eight pixels when replacement is sixteen")
	var scale: Vector2 = track.frames[0].get_shader_parameter("uv_scale")
	var offset: Vector2 = track.frames[0].get_shader_parameter("uv_offset")
	assert_eq(scale, Vector2(1.0 / 20.0, 1.0 / 12.0))
	assert_eq(offset, Vector2(2.0 / 20.0, 2.0 / 12.0))
	assert_string_contains(track.frames[0].shader.code, "blend_add", "original flag enables translucency, current image supplies rate")
	assert_false(track.frames[1].shader.code.contains("sampler2D image"))
	assert_eq(mesh.missing_image_ids, PackedInt32Array([999]))
	var instance := AnimatedModelInstance.new()
	add_child_autofree(instance)
	instance.setup(mesh, ModelAnimationPlayer.new(file))
	var other := AnimatedModelInstance.new()
	add_child_autofree(other)
	other.setup(mesh, ModelAnimationPlayer.new(file))
	var other_material: Material = other.part_nodes[0].get_surface_override_material(track.surface)
	var unchanged: Material = mesh.part_meshes[0].surface_get_material(1 - track.surface)
	var resources: float = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var start: int = Time.get_ticks_usec()
	for _tick: int in 300:
		instance.advance_tick()
		instance.render(0.5)
	assert_eq(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), resources, "steady playback creates no resources")
	assert_same(instance.part_nodes[0].mesh, mesh.part_meshes[0])
	assert_same(mesh.part_meshes[0].surface_get_material(1 - track.surface), unchanged)
	assert_null(instance.part_nodes[0].get_surface_override_material(1 - track.surface))
	instance.player.texture_animation_enabled = false
	instance.apply_exact()
	assert_same(instance.part_nodes[0].get_surface_override_material(track.surface), track.original)
	assert_same(other.part_nodes[0].get_surface_override_material(track.surface), other_material, "each instance owns its surface override state")
	print("animated render: 300 ticks and draws in %d us, resource count %d unchanged" % [Time.get_ticks_usec() - start, int(resources)])
	var lighting := MapLighting.new()
	lighting.ambient = Vector3(1024, 1024, 1024)
	instance.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	var prepared: Dictionary[ShaderMaterial, ShaderMaterial] = instance._materials.duplicate()
	for original: ShaderMaterial in track.frames:
		assert_true(prepared.has(original), "even unseen texture frames are prepared before playback")
		assert_ne(prepared[original], original)
	instance.player.texture_animation_enabled = true
	resources = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	for _tick: int in 300:
		instance.advance_tick()
	assert_eq(instance._materials, prepared, "cycling texture frames reuses all prepared materials")
	assert_eq(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), resources)
	lighting.ambient *= 2.0
	instance.set_source_lighting(lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	for original: ShaderMaterial in track.frames:
		var updated: Vector3 = prepared[original].get_shader_parameter("source_ambient")
		assert_eq(updated, lighting.ambient, "inactive variants receive lighting invalidation")
	track.original.set_shader_parameter("projection_scale", Vector2(2.0, 3.0))
	instance.player.texture_animation_enabled = false
	instance.apply_exact()
	var projection: Vector2 = prepared[track.original].get_shader_parameter("projection_scale")
	assert_eq(projection, Vector2(2.0, 3.0), "prepared materials follow projection changes when bound")
	assert_same(other.part_nodes[0].get_surface_override_material(track.surface), other_material)
	var missing_original: VloFile = _texture_bank(false)
	var missing_library := TextureLibrary.new()
	missing_library.add_bank(missing_original, "replacement only")
	var fallback: ModelMesh = ModelMeshBuilder.new(missing_library, missing_original).build_animated(file)
	var fallback_track: ModelMesh.TextureTrack = fallback.texture_tracks[0][0]
	assert_eq(fallback.missing_image_ids, PackedInt32Array([7, 999]))
	assert_eq(fallback.diagnostics.size(), 1)
	assert_string_contains(fallback.diagnostics[0], "pixel UVs cannot be resolved")
	for frame_material: ShaderMaterial in fallback_track.frames:
		assert_same(frame_material, fallback_track.original)
		assert_false(frame_material.shader.code.contains("sampler2D image"), "a known replacement cannot recover missing original image dimensions")
