extends RetailTest
## Independent animation facts and complete retail playback coverage.

var _data: GameData


func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))


func after_all() -> void:
	if _data != null:
		_data.close()


func _digest(values: PackedInt32Array) -> String:
	return GoldenFiles.list_digest32(values) if not values.is_empty() else "-"


func _row(values: Array) -> PackedStringArray:
	var strings := PackedStringArray()
	for value: Variant in values:
		strings.append(str(value))
	return strings


func _match_rows(name: String, rows: Array[PackedStringArray]) -> void:
	var differences: PackedStringArray = GoldenFiles.differences(name, rows, GoldenFiles.rows("animation_%s.tsv" % name))
	assert_eq(differences.size(), 0, "\n".join(differences))


func test_animation_census() -> void:
	var totals: Dictionary[String, int] = {"models": 0, "animated": 0, "transforms": 0,
		"actions": 0, "virtual_frames": 0, "flipbook_actions": 0, "texture_targets": 0,
		"unsafe_flipbook_actions": 0, "transform_code_1": 0, "transform_code_2": 0}
	for entry: MwiEntry in _data.model_entries():
		var file: MofFile = _data.read_model(entry.index)
		assert_not_null(file, entry.display_name())
		if file == null:
			continue
		totals["models"] += 1
		if file.animated != null:
			totals["animated"] += 1
			totals["transforms"] += file.animated.transforms.size()
			var code_key: String = "transform_code_%d" % file.animated.transform_code
			totals[code_key] = totals.get(code_key, 0) + 1
			for model_set: MofAnimated.ModelSet in file.animated.model_sets:
				for action: MofAnimated.Action in model_set.actions:
					totals["actions"] += 1
					totals["virtual_frames"] += action.frame_count
		for model: MofStatic in file.static_models:
			if model.is_incomplete:
				continue
			for part: MofPart in model.parts:
				totals["flipbook_actions"] += part.flipbook_actions.size()
				totals["texture_targets"] += part.texture_targets.size()
				for action: MofPart.FlipbookAction in part.flipbook_actions:
					if not action.error.is_empty():
						totals["unsafe_flipbook_actions"] += 1
	var facts: Dictionary[String, String] = GoldenFiles.facts("animation_summary.txt")
	assert_eq(totals.size(), facts.size())
	for key: String in totals:
		var expected: String = facts.get(key, "missing")
		assert_eq(str(totals[key]), expected, key)


func test_all_xar_headers_transforms_and_metadata() -> void:
	var rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	var transforms: int = 0
	for entry: MwiEntry in _data.model_entries():
		var file: MofFile = _data.read_model(entry.index, problems)
		if file == null or file.animated == null:
			continue
		var anim: MofAnimated = file.animated
		var raw := PackedInt32Array()
		for transform: MofTransform in anim.transforms:
			raw.append_array(transform.raw_values)
		transforms += anim.transforms.size()
		var metadata := PackedInt32Array()
		for model_set: MofAnimated.ModelSet in anim.model_sets:
			metadata.append_array(PackedInt32Array([model_set.models.size(), model_set.actions.size()]))
			for model: MofAnimated.ModelInfo in model_set.models:
				metadata.append_array(PackedInt32Array([model.static_model_index, model.part_count, model.flags, model.bounding_box.size()]))
				metadata.append_array(model.bounding_box)
		rows.append(_row([entry.index, anim.transform_code, int(anim.starts_at_frame_zero), anim.model_sets.size(),
			anim.transforms.size(), _digest(raw), _digest(metadata)]))
	assert_eq(problems.size(), 0, "\n".join(problems))
	_match_rows("xar", rows)
	assert_eq(rows.size(), 78)
	assert_eq(transforms, 28447)


func test_every_frame_of_every_xar_action() -> void:
	var rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	var frames: int = 0
	var pose_errors: int = 0
	for entry: MwiEntry in _data.model_entries():
		var file: MofFile = _data.read_model(entry.index, problems)
		if file == null or file.animated == null:
			continue
		var anim: MofAnimated = file.animated
		for si: int in anim.model_sets.size():
			var model_set: MofAnimated.ModelSet = anim.model_sets[si]
			for model: MofAnimated.ModelInfo in model_set.models:
				var player := ModelAnimationPlayer.new(file, model.static_model_index)
				for ai: int in model_set.actions.size():
					var action: MofAnimated.Action = model_set.actions[ai]
					var samples := PackedInt32Array()
					var valid: bool = player.set_action(ai)
					if valid:
						player.restart()
						for frame: int in action.frame_count:
							var pose: ModelPose = player.sample_pose()
							if player.frame != frame:
								pose_errors += 1
							for part: int in model.part_count:
								var values: PackedInt32Array = anim.sample_matrix(model.static_model_index, ai, player.frame, part)
								samples.append_array(values)
								if values.size() != 12 or not _pose_matches(pose.transforms[part], values):
									pose_errors += 1
							player.advance_tick()
							frames += 1
						assert_eq(player.frame, 0, "%s action %d loop" % [entry.display_name(), ai])
					rows.append(_row([entry.index, model.static_model_index, si, ai, action.cel_count, action.part_count,
						action.frame_count, action.flags, int(valid), _digest(action.cel_numbers),
						_digest(action.transform_indices), _digest(samples)]))
	_match_rows("actions", rows)
	assert_eq(rows.size(), 187)
	assert_eq(frames, 4016)
	assert_eq(pose_errors, 0, "player poses convert every sampled matrix correctly")
	assert_eq(problems.size(), 0, "\n".join(problems))


func _pose_matches(pose: Transform3D, matrix: PackedInt32Array) -> bool:
	var signs: Array[int] = [1, -1, -1]
	for row: int in 3:
		for column: int in 3:
			if not is_equal_approx(pose.basis[column][row], float(matrix[row * 3 + column] * signs[row] * signs[column]) / 4096.0):
				return false
		if not is_equal_approx(pose.origin[row], float(matrix[9 + row] * signs[row]) / 256.0):
			return false
	return true


func test_all_partcels_and_effective_animation_data() -> void:
	var rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	for entry: MwiEntry in _data.model_entries():
		var file: MofFile = _data.read_model(entry.index, problems)
		if file == null:
			continue
		for mi: int in file.static_models.size():
			var model: MofStatic = file.static_models[mi]
			for pi: int in model.parts.size():
				var part: MofPart = model.parts[pi]
				var geometry := PackedInt32Array()
				for cel: MofPart.Partcel in part.partcels:
					for values: PackedInt32Array in [cel.vertices, cel.normals, cel.bounding_box]:
						geometry.append(values.size())
						geometry.append_array(values)
				var flip := PackedInt32Array()
				for action: MofPart.FlipbookAction in part.flipbook_actions:
					flip.append_array(PackedInt32Array([action.start, action.frame_count]))
				var targets := PackedInt32Array()
				for target: MofPart.TextureTarget in part.texture_targets:
					targets.append_array(PackedInt32Array([target.polygon_type, target.polygon_index, target.list_index]))
				var lists := PackedInt32Array()
				for sequence: MofPart.TextureAnimation in part.texture_lists:
					lists.append(sequence.image_ids.size())
					for i: int in sequence.image_ids.size():
						lists.append_array(PackedInt32Array([sequence.image_ids[i], sequence.durations[i]]))
				rows.append(_row([entry.index, mi, pi, int(model.is_incomplete), part.partcels.size(),
					_digest(geometry), _digest(flip), _digest(targets), _digest(lists)]))
	_match_rows("parts", rows)
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_all_safe_flipbooks_and_known_unsafe_records() -> void:
	var rows: Array[PackedStringArray] = []
	var unsafe_count: int = 0
	var problems := PackedStringArray()
	var frame_errors: int = 0
	for entry: MwiEntry in _data.model_entries():
		var file: MofFile = _data.read_model(entry.index, problems)
		if file == null:
			continue
		for mi: int in file.static_models.size():
			var model: MofStatic = file.static_models[mi]
			var player := ModelAnimationPlayer.new(file, mi)
			for pi: int in model.parts.size():
				var part: MofPart = model.parts[pi]
				for ai: int in part.flipbook_actions.size():
					var action: MofPart.FlipbookAction = part.flipbook_actions[ai]
					var valid: bool = player.set_action(ai)
					if not valid and not part.borrows:
						unsafe_count += 1
					if valid:
						player.restart()
						for frame: int in action.frame_count + 1:
							var pose: ModelPose = player.sample_pose()
							if pose.partcels[pi] != action.start + frame % action.frame_count:
								frame_errors += 1
							player.advance_tick()
					rows.append(_row([entry.index, mi, pi, ai, action.start, action.frame_count, int(valid)]))
	_match_rows("flipbooks", rows)
	assert_eq(unsafe_count, 19)
	assert_eq(frame_errors, 0)
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_every_texture_target_through_a_cycle_and_wrap() -> void:
	var rows: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows("animation_texture_cycles.tsv"):
		var resource_id: int = row[0].to_int()
		var mi: int = row[1].to_int()
		var pi: int = row[2].to_int()
		var ti: int = row[3].to_int()
		var file: MofFile = _data.read_model(resource_id)
		assert_not_null(file)
		if file == null:
			continue
		var player := ModelAnimationPlayer.new(file, mi)
		var part: MofPart = file.static_models[mi].parts[pi]
		var target: MofPart.TextureTarget = part.texture_targets[ti]
		var sequence: MofPart.TextureAnimation = part.texture_lists[target.list_index]
		var total: int = 0
		for duration: int in sequence.durations:
			total += maxi(1, duration)
		var values := PackedInt32Array()
		for _i: int in total + 1:
			var pose: ModelPose = player.sample_pose()
			var selected: int = pose.texture_entries[pi][ti]
			values.append_array(PackedInt32Array([selected, sequence.image_ids[selected] if selected >= 0 else -1]))
			player.advance_tick()
		rows.append(_row([resource_id, mi, pi, ti, target.list_index, total, _digest(values)]))
	_match_rows("texture_cycles", rows)


func test_reference_frog_matrix_hashes() -> void:
	var file: MofFile = _data.read_model(_data.find_resource("GEN_FROG_WIN95.XAR").index)
	var player := ModelAnimationPlayer.new(file)
	assert_true(player.set_action(0))
	player.restart()
	assert_eq(_matrix_hash(file.animated.sample_matrix(0, 0, player.frame, 0)), 0x9655a8c6)
	for _i: int in 179:
		player.advance_tick()
	assert_eq(_matrix_hash(file.animated.sample_matrix(0, 0, player.frame, 0)), 0xa933ba38)


func _matrix_hash(matrix: PackedInt32Array) -> int:
	var bytes := PackedByteArray()
	bytes.resize(32)
	for i: int in 9:
		bytes.encode_s16(i * 2, matrix[i])
	for i: int in 3:
		bytes.encode_s32(20 + i * 4, matrix[9 + i])
	var hash_value: int = 2166136261
	for byte: int in bytes:
		hash_value = ((hash_value ^ byte) * 16777619) & 0xffffffff
	return hash_value
