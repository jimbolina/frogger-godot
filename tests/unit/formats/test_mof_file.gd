extends GutTest
## Model files (MOF): kinds, parts, polygons, incomplete models, animated
## files, and the files that must be refused. Needs no game files.


func _triangle_part() -> SyntheticMof.Part:
	return SyntheticMof.part([0, 0, 0, 256, 0, 0, 0, -256, 0], [0, 0, -4096],
		[SyntheticMof.polygon(MofPolygonType.F3, [0, 1, 2], [0], Color8(10, 20, 30))])


func test_kinds_are_told_apart_by_content() -> void:
	var plain: PackedByteArray = SyntheticMof.build_static([_triangle_part()])
	assert_eq(MofFile.kind_of(SyntheticMof.build_dummy()), MofFile.Kind.DUMMY)
	assert_eq(MofFile.kind_of(plain), MofFile.Kind.STATIC)
	assert_eq(MofFile.kind_of(SyntheticMof.build_animated([plain])), MofFile.Kind.ANIMATED)
	assert_eq(MofFile.kind_of("2GRPxxxxxxxxxxxx".to_ascii_buffer()), MofFile.Kind.UNKNOWN)
	assert_eq(MofFile.kind_of(PackedByteArray()), MofFile.Kind.UNKNOWN)


func test_a_placeholder_is_four_bytes_and_holds_nothing() -> void:
	var file: MofFile = MofFile.parse(SyntheticMof.build_dummy())
	assert_eq(file.error, "")
	assert_eq(file.kind_name(), "dummy")
	assert_eq(file.static_models.size(), 0)
	assert_eq(file.polygon_count(), 0)


func test_static_model() -> void:
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([_triangle_part()]))
	assert_eq(file.error, "")
	assert_eq(file.kind_name(), "static")
	assert_false(file.is_incomplete)
	assert_eq(file.part_count(), 1)
	var part: MofPart = file.static_models[0].parts[0]
	assert_eq(part.vertex_count, 3)
	assert_eq(part.normal_count, 1)
	assert_eq(part.static_partcel().vertices, PackedInt32Array([0, 0, 0, 256, 0, 0, 0, -256, 0]))
	assert_eq(part.static_partcel().normals, PackedInt32Array([0, 0, -4096]))
	assert_eq(part.static_partcel().bounding_box.size(), 24)
	assert_eq(part.bounding_box_count, 1)
	var polygon: MofPolygon = part.polygons[0]
	assert_eq(polygon.type, MofPolygonType.F3)
	assert_eq(polygon.vertices, PackedInt32Array([0, 1, 2]))
	assert_eq([polygon.red, polygon.green, polygon.blue], [10, 20, 30])
	assert_eq(polygon.image_id, -1)
	assert_false(polygon.is_textured())


func test_every_textured_kind_keeps_its_own_layout() -> void:
	for kind: int in [MofPolygonType.FT3, MofPolygonType.FT4, MofPolygonType.GT3, MofPolygonType.GT4]:
		var corners: int = MofPolygonType.vertex_count(kind)
		var vertices: Array[int] = []
		var normals: Array[int] = []
		var uvs: Array[int] = []
		var positions: Array[int] = []
		for i: int in corners:
			vertices.append(i)
			uvs.append_array([10 * i + 1, 10 * i + 2])
			positions.append_array([i * 16, 0, 0])
		for i: int in MofPolygonType.normal_count(kind):
			normals.append(0)
		var part: SyntheticMof.Part = SyntheticMof.part(positions, [0, 0, -4096],
			[SyntheticMof.polygon(kind, vertices, normals, Color8(1, 2, 3), 345, uvs)])
		var file: MofFile = MofFile.parse(SyntheticMof.build_static([part]))
		assert_eq(file.error, "", MofPolygonType.type_name(kind))
		var polygon: MofPolygon = file.static_models[0].parts[0].polygons[0]
		assert_eq(polygon.image_id, 345, MofPolygonType.type_name(kind))
		assert_eq(polygon.uvs, PackedByteArray(uvs), MofPolygonType.type_name(kind))
		assert_eq(polygon.normals.size(), MofPolygonType.normal_count(kind))
		assert_eq(polygon.blue, 3)


func test_blocks_of_several_kinds_and_parts() -> void:
	var first: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.GT4, Color8(128, 128, 128), 7)
	first.polygons.append(SyntheticMof.polygon(MofPolygonType.F3, [0, 1, 2], [0]))
	first.polygons.append(SyntheticMof.polygon(MofPolygonType.F3, [0, 2, 3], [0]))
	first.hilites.append(Vector2i(4, 2))
	first.collprims = 2
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([first, _triangle_part()]))
	assert_eq(file.error, "")
	assert_eq(file.part_count(), 2)
	assert_eq(file.polygon_count(), 4)
	var part: MofPart = file.static_models[0].parts[0]
	assert_eq(part.polygons_by_type()[MofPolygonType.GT4], 1)
	assert_eq(part.polygons_by_type()[MofPolygonType.F3], 2)
	assert_eq(part.hilites.size(), 1)
	assert_eq(part.hilites[0].type, 4)
	assert_eq(part.hilites[0].index, 2)
	assert_eq(part.collprims.size(), 2)
	assert_eq(part.collprims[0].matrix_index, -1)
	assert_eq(file.image_ids(), PackedInt32Array([7]))
	assert_eq(file.static_models[0].parts[1].static_partcel().vertices.size(), 9)


func test_flipbook_and_texture_animation_are_counted() -> void:
	var part: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)
	part.poses.append(PackedInt32Array([0, 0, 8, 256, 0, 8, 256, 256, 8, 0, 256, 8]))
	part.flipbook_actions = 1
	part.animated_polygons = PackedInt32Array([0])
	part.animation_images = PackedInt32Array([7, 8, 9])
	var file: MofFile = MofFile.parse(SyntheticMof.build_static([part]))
	assert_eq(file.error, "")
	var read: MofPart = file.static_models[0].parts[0]
	assert_eq(file.flags, MofStatic.FLAG_FLIPBOOK | MofStatic.FLAG_ANIMATED_TEXTURES)
	assert_eq(read.partcels.size(), 2)
	assert_eq(read.partcels[1].vertices[2], 8)
	assert_eq(read.flipbook_action_count, 1)
	assert_eq(read.texture_animation_target_count, 1)
	assert_eq(read.texture_animation_count, 1)
	assert_eq(read.texture_animation_image_ids, PackedInt32Array([7, 8, 9]))


func test_an_incomplete_model_borrows_its_shape() -> void:
	var complete: MofFile = MofFile.parse(SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4, Color8(200, 0, 0))]))
	var bytes: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4, Color8(0, 0, 200))], true)
	assert_true(MofFile.needs_counterpart(bytes))
	assert_false(MofFile.needs_counterpart(SyntheticMof.build_static([_triangle_part()])))
	var alone: MofFile = MofFile.parse(bytes)
	assert_string_contains(alone.error, "no complete model")
	var file: MofFile = MofFile.parse(bytes, complete)
	assert_eq(file.error, "")
	assert_true(file.is_incomplete)
	var part: MofPart = file.static_models[0].parts[0]
	assert_true(part.borrows)
	assert_eq(part.static_partcel().vertices, complete.static_models[0].parts[0].static_partcel().vertices)
	assert_eq(part.polygons[0].blue, 200, "its own polygons")


func test_an_animated_file_holds_whole_static_models() -> void:
	var first: PackedByteArray = SyntheticMof.build_static([_triangle_part()])
	var second: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.G4), _triangle_part()])
	var file: MofFile = MofFile.parse(SyntheticMof.build_animated([first, second]))
	assert_eq(file.error, "")
	assert_eq(file.kind_name(), "animated")
	assert_eq(file.animated.model_set_count, 1)
	assert_true(file.animated.starts_at_frame_zero)
	assert_eq(file.animated.transform_code, 2)
	assert_eq(file.static_models.size(), 2)
	assert_eq(file.static_models[0].parts.size(), 1)
	assert_eq(file.static_models[1].parts.size(), 2)
	assert_eq(file.static_models[1].parts[0].polygons[0].type, MofPolygonType.G4)


func test_bad_files_are_refused() -> void:
	var good: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)])
	var polygons_at: int = good.decode_u32(16 + 16)

	var wrong_length: PackedByteArray = good.duplicate()
	wrong_length.encode_u32(4, good.size() + 4)
	assert_string_contains(MofFile.parse(wrong_length).error, "bytes")

	var cut_short: PackedByteArray = good.slice(0, good.size() - 8)
	assert_ne(MofFile.parse(cut_short).error, "")

	var wrong_kind: PackedByteArray = good.duplicate()
	wrong_kind.encode_u16(polygons_at, 16)
	assert_string_contains(MofFile.parse(wrong_kind).error, "kind 16")

	var page_word: PackedByteArray = good.duplicate()
	page_word.encode_u16(polygons_at + 4 + 10 + 2 + 2 + 2 + 2, 3)
	assert_string_contains(MofFile.parse(page_word).error, "texture page word")

	var wrong_flags: PackedByteArray = good.duplicate()
	wrong_flags.encode_u32(8, MofStatic.FLAG_FLIPBOOK)
	assert_string_contains(MofFile.parse(wrong_flags).error, "flags")

	var run_time_word: PackedByteArray = good.duplicate()
	run_time_word.encode_u32(16 + 24, 1)
	assert_string_contains(MofFile.parse(run_time_word).error, "not zero")

	var vertices_elsewhere: PackedByteArray = good.duplicate()
	var partcel_at: int = good.decode_u32(16 + 12)
	vertices_elsewhere.encode_u32(partcel_at, partcel_at)
	assert_string_contains(MofFile.parse(vertices_elsewhere).error, "vector pool")

	var animated: PackedByteArray = SyntheticMof.build_animated([good])
	animated.encode_u32(8, MofAnimated.FLAG_ANIMATED)
	assert_string_contains(MofFile.parse(animated).error, "flags")
	assert_eq(MofFile.parse("nonsense, not a model".to_ascii_buffer()).error, "not a model")


func test_polygon_kinds() -> void:
	assert_eq(MofPolygonType.type_name(MofPolygonType.GT4), "GT4")
	assert_eq(MofPolygonType.vertex_count(MofPolygonType.F3), 3)
	assert_eq(MofPolygonType.normal_count(MofPolygonType.G4), 4)
	assert_true(MofPolygonType.is_textured(MofPolygonType.FT3))
	assert_false(MofPolygonType.is_textured(MofPolygonType.G3))
	assert_false(MofPolygonType.is_valid(16))
	assert_eq(MofPolygonType.vertex_count(99), 0)
