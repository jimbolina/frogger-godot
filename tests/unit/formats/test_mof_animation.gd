extends GutTest
## Synthetic animation readers test bounds, stored facts and authored semantics.


func _static_bytes(parts: int = 1) -> PackedByteArray:
	var made: Array[SyntheticMof.Part] = []
	for _i: int in parts:
		made.append(SyntheticMof.square(MofPolygonType.F4))
	return SyntheticMof.build_static(made)


func test_all_six_encodings_keep_signed_fields_and_expand() -> void:
	for code: int in 6:
		var fields: Array[int] = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -12, 34, -56]
		var expected: PackedInt32Array = PackedInt32Array(fields)
		if code == 1:
			fields = [127, 0, 0, 0, 127, 0, 0, 0, 127, -12, 34, -56]
			expected = PackedInt32Array([4064, 0, 0, 0, 4064, 0, 0, 0, 4064, -12, 34, -56])
		elif code >= 2:
			fields = [4096, 0, 0, 0, -12, 34, -56]
			if code == 2 or code == 4:
				fields[0] = 64
			if code >= 4:
				fields.append_array([32, 32, 32, 1])
		var authored: MofTransform = SyntheticMofAnimation.transform(code, fields)
		var bytes: PackedByteArray = SyntheticMofAnimation.build([_static_bytes()], code, [authored],
			[SyntheticMofAnimation.action(1, 1, [0], [0])])
		var file: MofFile = MofFile.parse(bytes)
		assert_eq(file.error, "", "encoding %d" % code)
		assert_eq(file.animated.transforms[0].raw_values, PackedInt32Array(fields))
		assert_eq(file.animated.sample_matrix(0, 0, 0, 0), expected)


func test_quaternion_matrix_uses_authored_values_without_normalizing() -> void:
	var authored: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 0, 0, 0])
	assert_eq(authored.matrix_values(), PackedInt32Array([2048, 4096, 0, -4096, 2048, 0, 0, 0, 4096, 0, 0, 0]))


func test_undefined_scale_flags_are_preserved_and_reported() -> void:
	var authored: MofTransform = SyntheticMofAnimation.transform(4, [64, 0, 0, 0, 0, 0, 0, 64, 64, 64, 2])
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([_static_bytes()], 4, [authored],
		[SyntheticMofAnimation.action(1, 1, [0], [0])]))
	assert_eq(file.error, "")
	assert_eq(file.animated.transforms[0].raw_values[10], 2)
	assert_eq(file.animated.diagnostics.size(), 1)
	assert_eq(file.animated.sample_matrix(0, 0, 0, 0)[0], 4096)
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.diagnostics, file.animated.diagnostics)


func test_scaling_applies_to_rows_and_wraps_short_results() -> void:
	var authored: MofTransform = SyntheticMofAnimation.transform(4, [64, 0, 0, 32, 1, 2, 3, 64, 16, -32, 1])
	assert_eq(authored.matrix_values(), PackedInt32Array([4096, 8192, 0, -2048, 1024, 0, 0, 0, -4096, 1, 2, 3]))
	var large: MofTransform = SyntheticMofAnimation.transform(5, [16384, 0, 0, 4096, 0, 0, 0, 127, 127, 127, 1])
	var values: PackedInt32Array = large.matrix_values()
	assert_eq(values[1], 1024, "32768 wraps to -32768, then scaled short wraps again")


func test_virtual_frames_repeat_cels_and_old_signatures_start_at_one() -> void:
	var transforms: Array[MofTransform] = [SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 10, 20, 30]),
		SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 50, 60, 70])]
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([_static_bytes()], 2, transforms,
		[SyntheticMofAnimation.action(1, 2, [1, 1, 2], [0, 1])], false))
	assert_eq(file.error, "")
	assert_eq(file.animated.sample_matrix(0, 0, 0, 0)[9], 10)
	assert_eq(file.animated.sample_matrix(0, 0, 1, 0)[9], 10)
	assert_eq(file.animated.sample_matrix(0, 0, 2, 0)[9], 50)
	assert_true(file.animated.sample_matrix(0, 0, -1, 0).is_empty())
	assert_true(file.animated.sample_matrix(0, 0, 3, 0).is_empty())
	assert_true(file.animated.sample_matrix(0, 0, 0, 1).is_empty())


func test_authored_interpolation_uses_shortest_path_and_zero_based_triples() -> void:
	var transforms: Array[MofTransform] = [SyntheticMofAnimation.transform(3, [4096, 0, 0, 0, -10, 0, 0]),
		SyntheticMofAnimation.transform(3, [-4096, 0, 0, 0, 11, 0, 0])]
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([_static_bytes()], 3, transforms,
		[SyntheticMofAnimation.action(1, 2, [0, 1, 0, 0, 1, 2048, 0, 1, 4096], [0, 1], true)], false))
	assert_eq(file.error, "")
	assert_eq(file.animated.actions_for(0)[0].error, "")
	assert_eq(file.animated.sample_matrix(0, 0, 0, 0), transforms[0].matrix_values())
	assert_eq(file.animated.sample_matrix(0, 0, 1, 0), PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]))
	assert_eq(file.animated.sample_matrix(0, 0, 2, 0), transforms[1].matrix_values())


func test_interpolated_rotation_and_scaling() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1])
	var last: MofTransform = SyntheticMofAnimation.transform(5, [0, 0, 0, 4096, 100, -101, 0, 64, 16, -32, 1])
	var matrix: PackedInt32Array = first.interpolate(last, 2048)
	assert_almost_eq(matrix[1], 6144, 8)
	assert_almost_eq(matrix[3], -3072, 8)
	assert_eq(matrix[8], 0)
	assert_eq(matrix[9], 50)
	assert_eq(matrix[10], -51)


func test_unsafe_action_refs_disable_only_action() -> void:
	var transform: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 0, 0, 0])
	for authored: MofAnimated.Action in [SyntheticMofAnimation.action(1, 1, [1], [0]),
		SyntheticMofAnimation.action(1, 1, [0], [-1]), SyntheticMofAnimation.action(1, 1, [0], [1]),
		SyntheticMofAnimation.action(1, 1, [0, 0, 4097], [0], true)]:
		var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([_static_bytes(2)], 2, [transform], [authored]))
		assert_eq(file.error, "")
		assert_ne(file.animated.actions_for(0)[0].error, "")
		assert_true(file.animated.sample_matrix(0, 0, 0, 0).is_empty())


func test_shared_actions_can_have_more_parts_than_a_model() -> void:
	var transform: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 0, 0, 0])
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build([_static_bytes(), _static_bytes(2)], 2, [transform],
		[SyntheticMofAnimation.action(2, 1, [0], [0, 0])]))
	assert_eq(file.error, "")
	assert_eq(file.animated.actions_for(0)[0].error, "")
	assert_eq(file.animated.sample_matrix(1, 0, 0, 1).size(), 12)
	assert_true(file.animated.sample_matrix(0, 0, 0, 1).is_empty())


func test_static_model_metadata_and_part_mismatch_disable_action() -> void:
	var transform: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 0, 0, 0])
	var bytes: PackedByteArray = SyntheticMofAnimation.build([_static_bytes(2)], 2, [transform],
		[SyntheticMofAnimation.action(1, 1, [0], [0])])
	var file: MofFile = MofFile.parse(bytes)
	assert_eq(file.error, "")
	assert_ne(file.animated.actions_for(0)[0].error, "")
	bytes.encode_u16(54, 10)
	file = MofFile.parse(bytes)
	assert_eq(file.error, "")
	assert_ne(file.animated.actions_for(10)[0].error, "")
	bytes.encode_u16(48, 10)
	assert_ne(MofFile.parse(bytes).error, "")


func test_structural_counts_and_pointers_are_bounded() -> void:
	var transform: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 0, 0, 0])
	var good: PackedByteArray = SyntheticMofAnimation.build([_static_bytes()], 2, [transform],
		[SyntheticMofAnimation.action(1, 1, [0], [0])])
	var shared_at: int = good.decode_u32(20)
	var broken: PackedByteArray = good.duplicate()
	broken.encode_u16(shared_at + 4, 65535)
	assert_ne(MofFile.parse(broken).error, "")
	broken = good.duplicate()
	broken.encode_u32(shared_at + 12, good.decode_u32(24))
	assert_ne(MofFile.parse(broken).error, "")
	broken = good.duplicate()
	broken.encode_u32(88, good.size() + 100)
	assert_ne(MofFile.parse(broken).error, "")
	broken = good.duplicate()
	broken.encode_u16(80, 65535)
	assert_ne(MofFile.parse(broken).error, "")


func test_flipbook_ranges_preserved_and_bad_ranges_unavailable() -> void:
	var source: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.F4)
	source.poses.append(source.poses[0].duplicate())
	source.poses.append(source.poses[0].duplicate())
	source.flipbook_ranges = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 0)]
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([source]))
	assert_eq(file.error, "")
	var part: MofPart = file.static_models[0].parts[0]
	assert_eq(part.flipbook_action_count, 3)
	assert_eq(part.flipbook_actions[0].start, 1)
	assert_eq(part.flipbook_actions[0].frame_count, 2)
	assert_eq(part.flipbook_actions[0].error, "")
	assert_ne(part.flipbook_actions[1].error, "")
	assert_eq(part.flipbook_actions[1].frame_count, 2, "unavailable authored count is never clamped")
	assert_ne(part.flipbook_actions[2].error, "")
	var bytes: PackedByteArray = SyntheticMof.build_static([source])
	var flipbook_at: int = bytes.decode_u32(56)
	bytes.encode_u16(flipbook_at + 2, 65535)
	assert_ne(MofFile.parse(bytes).error, "", "structural count errors fail the model")


func test_texture_lists_keep_zero_durations_and_disable_empty_list() -> void:
	var source: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	source.animated_polygons = PackedInt32Array([0])
	source.animation_images = PackedInt32Array([7, 8])
	source.animation_durations = PackedInt32Array([0, 65535])
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([source]))
	assert_eq(file.error, "")
	var part: MofPart = file.static_models[0].parts[0]
	assert_eq(part.texture_targets[0].list_index, 0)
	assert_eq(part.texture_targets[0].error, "")
	assert_eq(part.texture_lists[0].image_ids, source.animation_images)
	assert_eq(part.texture_lists[0].durations, source.animation_durations)
	source.animation_images = PackedInt32Array()
	file = MofFile.parse(SyntheticMof.build_static([source]))
	assert_eq(file.error, "")
	assert_ne(file.static_models[0].parts[0].texture_targets[0].error, "")


func test_texture_target_semantic_errors_preserve_static_geometry() -> void:
	var source: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4)
	source.animated_polygons = PackedInt32Array([0])
	source.animation_images = PackedInt32Array([7])
	var good: PackedByteArray = SyntheticMof.build_static([source])
	var at: int = good.decode_u32(52)
	var broken: PackedByteArray = good.duplicate()
	broken.encode_u32(at + 8, 10)
	var file: MofFile = MofFile.parse(broken)
	assert_eq(file.error, "")
	assert_ne(file.static_models[0].parts[0].texture_targets[0].error, "")
	broken = good.duplicate()
	broken.encode_u32(at + 16, at + 21)
	file = MofFile.parse(broken)
	assert_eq(file.error, "")
	assert_ne(file.static_models[0].parts[0].texture_targets[0].error, "")
	broken = good.duplicate()
	broken.encode_u32(at + 20, 2147483647)
	assert_ne(MofFile.parse(broken).error, "")
	broken = good.duplicate()
	broken.encode_u32(at + 16, good.size() + 4)
	assert_ne(MofFile.parse(broken).error, "", "an out-of-bounds list pointer is structural corruption")


func test_incomplete_parts_inherit_effective_animations_without_raw_counts() -> void:
	var source: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4)
	source.flipbook_ranges = [Vector2i(0, 1)]
	source.animated_polygons = PackedInt32Array([0])
	source.animation_images = PackedInt32Array([7, 8])
	var complete: MofFile = MofFile.parse(SyntheticMof.build_static([source]))
	var incomplete: MofFile = MofFile.parse(SyntheticMof.build_static([source], true), complete)
	assert_eq(incomplete.error, "")
	var part: MofPart = incomplete.static_models[0].parts[0]
	assert_eq(part.flipbook_action_count, 0)
	assert_eq(part.texture_animation_count, 0)
	assert_eq(part.texture_animation_target_count, 0)
	assert_eq(part.texture_animation_image_ids.size(), 0)
	assert_eq(part.flipbook_actions.size(), 1)
	assert_eq(part.texture_targets.size(), 1)
	assert_eq(part.texture_lists[0].image_ids, PackedInt32Array([7, 8]))


func test_multiple_model_sets_keep_independent_actions_and_global_model_ids() -> void:
	var transforms: Array[MofTransform] = [SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 10, 0, 0]),
		SyntheticMofAnimation.transform(2, [64, 0, 0, 0, 20, 0, 0])]
	var first := MofAnimated.ModelSet.new()
	var first_model := MofAnimated.ModelInfo.new()
	first_model.animation_type = 1
	first_model.static_model_index = 1
	first_model.part_count = 1
	first.actions = [SyntheticMofAnimation.action(1, 1, [0], [1])]
	first.models = [first_model]
	var second := MofAnimated.ModelSet.new()
	var second_model := MofAnimated.ModelInfo.new()
	second_model.animation_type = 1
	second_model.static_model_index = 0
	second_model.part_count = 1
	second_model.flags = 1
	second_model.bounding_box = PackedInt32Array([-1, -2, -3, 1, -2, -3, -1, 2, -3, 1, 2, -3,
		-1, -2, 3, 1, -2, 3, -1, 2, 3, 1, 2, 3])
	second.actions = [SyntheticMofAnimation.action(1, 1, [0, 0], [0])]
	second.models = [second_model]
	var file: MofFile = MofFile.parse(SyntheticMofAnimation.build_sets([_static_bytes(), _static_bytes()],
		[first, second], 2, transforms))
	assert_eq(file.error, "")
	assert_eq(file.animated.model_set_count, 2)
	assert_eq(file.animated.actions_for(0)[0].frame_count, 2)
	assert_eq(file.animated.actions_for(1)[0].frame_count, 1)
	assert_eq(file.animated.sample_matrix(0, 0, 1, 0)[9], 10)
	assert_eq(file.animated.sample_matrix(1, 0, 0, 0)[9], 20)
	assert_eq(file.animated.model_sets[1].models[0].bounding_box, second_model.bounding_box)


func test_scale_flags_apply_across_interpolation_even_at_endpoints() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 64, 32, 32, 0])
	var last: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1])
	assert_eq(first.matrix_values()[0], 4096, "flag zero ignores authored scale for ordinary samples")
	assert_eq(first.interpolate(last, 0)[0], 8192, "either endpoint flag activates scale across the segment")
	assert_eq(first.interpolate(last, 2048)[0], 6144)
	assert_eq(first.interpolate(last, 4096)[0], 4096)
	first.raw_values[10] = 2
	assert_eq(first.matrix_values()[0], 4096, "only bit zero enables scaling")


func test_byte_quaternion_interpolation_preserves_authored_magnitudes() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 0, 0, 0])
	var last: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 100, 0, 0])
	assert_eq(first.interpolate(last, 0), first.matrix_values(), "C's zero endpoint uses authored byte quaternion directly")
	var halfway: PackedInt32Array = first.interpolate(last, 2048)
	assert_eq(halfway[0], 2080)
	assert_eq(halfway[1], 4032)
	assert_eq(halfway[9], 50)
	assert_ne(last.interpolate(last, 4096)[1], last.matrix_values()[1], "nonzero C byte interpolation runs limited normalization")
