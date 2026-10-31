extends GutTest
## Model records save as Godot resources and load back with every exported
## field, and the former inner class names still work as types.

const ROOT: String = "user://test_mof_resources"


func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	_remove_tree(ROOT)


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _round_trip(file: MofFile, name: String) -> MofFile:
	var path: String = ROOT.path_join(name)
	assert_eq(ResourceSaver.save(file, path), OK, name)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MofFile


func _animated_part() -> SyntheticMof.Part:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	part.poses.append(PackedInt32Array([0, 0, 8, 256, 0, 8, 256, 256, 8, 0, 256, 8]))
	part.flipbook_actions = 1
	part.animated_polygons = PackedInt32Array([0])
	part.animation_images = PackedInt32Array([7, 8, 9])
	part.hilites.append(Vector2i(4, 2))
	part.collprims = 2
	return part


func test_a_static_model_survives_text_and_binary_resources() -> void:
	var parsed: MofFile = SyntheticMof.static_file([_animated_part()])
	assert_eq(parsed.error, "")
	parsed.static_models[0].parts[0].matrices.append(PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 1, -2, 3]))
	for name: String in ["static.tres", "static.res"]:
		var loaded: MofFile = _round_trip(parsed, name)
		assert_not_null(loaded, name)
		assert_eq(loaded.kind, MofFile.Kind.STATIC, name)
		assert_eq(loaded.signature, parsed.signature)
		assert_eq(loaded.size, parsed.size)
		assert_eq(loaded.flags, parsed.flags)
		var expected: MofPart = parsed.static_models[0].parts[0]
		var part: MofPart = loaded.static_models[0].parts[0]
		assert_eq(part.partcels.size(), 2)
		assert_eq(part.partcels[1].vertices, expected.partcels[1].vertices)
		assert_eq(part.static_partcel().bounding_box, expected.static_partcel().bounding_box)
		assert_eq(part.hilites[0].type, 4)
		assert_eq(part.hilites[0].index, 2)
		assert_eq(part.collprims.size(), 2)
		assert_eq(part.collprims[1].flags, expected.collprims[1].flags)
		assert_eq(part.collprims[0].offset, expected.collprims[0].offset)
		assert_eq(part.matrices, expected.matrices)
		assert_eq(part.flipbook_actions[0].frame_count, expected.flipbook_actions[0].frame_count)
		assert_eq(part.texture_targets[0].list_index, 0)
		assert_eq(part.texture_lists[0].image_ids, PackedInt32Array([7, 8, 9]))
		assert_eq(part.texture_lists[0].durations, expected.texture_lists[0].durations)
		assert_eq(part.polygons[0].uvs, expected.polygons[0].uvs)
		assert_eq(part.polygons[0].image_id, 7)
		assert_eq(part.end_offset, expected.end_offset)
		assert_eq(loaded.image_ids(), parsed.image_ids())


func test_an_animated_model_samples_the_same_after_loading() -> void:
	var transforms: Array[MofTransform] = [SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1]),
		SyntheticMofAnimation.transform(5, [0, 0, 0, 4096, 100, -101, 0, 64, 16, -32, 1])]
	var statics: Array[MofStatic] = [SyntheticMof.static_model([SyntheticMof.square(MofPolygonType.F4)])]
	var parsed: MofFile = SyntheticMofAnimation.animated_file(statics, 5, transforms,
		[SyntheticMofAnimation.action(1, 2, [0, 1, 0, 0, 1, 2048, 0, 1, 4096], [0, 1], true)])
	assert_eq(parsed.error, "")
	parsed.animated.bounding_boxes.append(PackedInt32Array([1, 2, 3]))
	var loaded: MofFile = _round_trip(parsed, "animated.res")
	assert_eq(loaded.kind, MofFile.Kind.ANIMATED)
	assert_eq(loaded.animated.static_ranges, parsed.animated.static_ranges)
	assert_eq(loaded.animated.transforms[1].raw_values, transforms[1].raw_values)
	assert_eq(loaded.animated.bounding_boxes, parsed.animated.bounding_boxes)
	assert_eq(loaded.animated.model_sets[0].models[0].part_count, 1)
	assert_eq(loaded.animated.actions_for(0)[0].error, "")
	for frame: int in 3:
		assert_false(loaded.animated.sample_matrix(0, 0, frame, 0).is_empty())
		assert_eq(loaded.animated.sample_matrix(0, 0, frame, 0), parsed.animated.sample_matrix(0, 0, frame, 0))


func test_former_inner_class_names_remain_types() -> void:
	var cel: MofPart.Partcel = MofPartcel.new()
	var hilites: Array[MofPart.Hilite] = [MofHilite.new()]
	var animated := MofAnimated.new()
	var model_set := MofAnimated.ModelSet.new()
	var action: MofAnimated.Action = MofAction.new()
	model_set.actions.append(action)
	model_set.models.append(MofModelInfo.new())
	animated.model_sets.append(model_set)
	var actions: Array[MofAnimated.Action] = animated.actions_for(0)
	assert_true(cel is MofPartcel)
	assert_true(hilites[0] is MofPart.Hilite)
	assert_eq(actions.size(), 1)
	assert_true(actions[0] is MofAction)
