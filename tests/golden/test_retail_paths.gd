extends RetailTest
## Compares every final-PC PATH record with independently decoded text facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _append_vec(values: PackedInt64Array, point: Vector3i) -> void:
	values.append_array(PackedInt64Array([point.x, point.y, point.z]))

func _digest(values: PackedInt64Array) -> String:
	return GoldenFiles.list_digest(values) if not values.is_empty() else "-"

func test_every_path_and_segment_matches_independent_facts() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("paths_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 78)
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var file: MapFile = _data.read_map(int(row[0]), problems)
		assert_not_null(file, row[1])
		if file == null:
			continue
		var metadata := PackedInt64Array()
		var segments := PackedInt64Array()
		var entity_lists := PackedInt64Array()
		var type_counts := PackedInt32Array([0, 0, 0])
		for path: MapPath in file.paths:
			assert_eq(path.entity_list_error, "", "%s path %d" % [row[1], path.path_index])
			entity_lists.append_array(PackedInt64Array([path.path_index, path.entity_indices.size()]))
			for entity_index: int in path.entity_indices:
				entity_lists.append(entity_index)
			metadata.append_array(PackedInt64Array([path.path_index, path.source_offset,
				path.entity_list_pointer, path.segments.size()]))
			for segment_index: int in path.segments.size():
				var segment: MapPathSegment = path.segments[segment_index]
				if segment.segment_type < 0 or segment.segment_type > 2:
					assert_true(false, "Unknown segment in %s path %d" % [row[1], path.path_index])
					continue
				type_counts[segment.segment_type] += 1
				segments.append_array(PackedInt64Array([path.path_index, segment_index,
					segment.source_offset, segment.end_offset, segment.segment_type, segment.length]))
				match segment.segment_type:
					0:
						for value: int in segment.matrix:
							segments.append(value)
						for value: int in segment.smooth_t:
							segments.append(value)
						for value: int in segment.smooth_c:
							segments.append(value)
					1:
						_append_vec(segments, segment.start)
						_append_vec(segments, segment.centre)
						_append_vec(segments, segment.normal)
						segments.append_array(PackedInt64Array([segment.radius, segment.pitch]))
					2:
						_append_vec(segments, segment.start)
						_append_vec(segments, segment.end)
		var actual: PackedStringArray = PackedStringArray([row[0], row[1], str(file.paths.size()),
			str(type_counts[0]), str(type_counts[1]), str(type_counts[2]),
			_digest(metadata), _digest(segments), _digest(entity_lists)])
		assert_eq(actual, row, row[1])
	assert_eq(problems.size(), 0, "\n".join(problems))
