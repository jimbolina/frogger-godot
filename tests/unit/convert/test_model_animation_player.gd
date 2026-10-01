extends GutTest
## Synthetic, asset-free checks for geometry and independent texture clocks.


func _flipbook(start: int = 1, count: int = 3, part_count: int = 1) -> MofFile:
	var file := MofFile.new()
	file.kind = MofFile.Kind.STATIC
	var model := MofStatic.new()
	for part_index: int in part_count:
		var part := MofPart.new()
		part.index = part_index
		for _cel: int in maxi(start + count, 1):
			part.partcels.append(MofPart.Partcel.new())
		var action := MofPart.FlipbookAction.new()
		action.start = start
		action.frame_count = count
		part.flipbook_actions.append(action)
		model.parts.append(part)
	file.static_models.append(model)
	return file


func _textures(file: MofFile, durations: PackedInt32Array, targets: int = 1) -> void:
	var part: MofPart = file.static_models[0].parts[0]
	var animation := MofPart.TextureAnimation.new()
	animation.durations = durations
	for entry: int in durations.size():
		animation.image_ids.append(10 + entry)
	part.texture_lists.append(animation)
	for index: int in targets:
		var polygon := MofPolygon.new()
		polygon.type = MofPolygonType.FT3
		part.polygons.append(polygon)
		var target := MofPart.TextureTarget.new()
		target.polygon_type = polygon.type
		target.polygon_index = index
		target.list_index = 0
		part.texture_targets.append(target)


func _entry(player: ModelAnimationPlayer, target: int = 0) -> int:
	return player.sample_pose().texture_entries[0][target]


func _animated() -> MofFile:
	var file: MofFile = _flipbook(0, 2, 2)
	file.kind = MofFile.Kind.ANIMATED
	file.animated = MofAnimated.new()
	file.animated.starts_at_frame_zero = true
	var model_set := MofAnimated.ModelSet.new()
	var info := MofAnimated.ModelInfo.new()
	info.static_model_index = 0
	info.part_count = 2
	model_set.models.append(info)
	var action := MofAnimated.Action.new()
	action.cel_count = 2
	action.part_count = 2
	action.frame_count = 3
	action.flags = 1
	action.cel_numbers = PackedInt32Array([0, 1, 0])
	action.transform_indices = PackedInt32Array([0, 1, 2, 3])
	model_set.actions.append(action)
	file.animated.model_sets.append(model_set)
	for index: int in 4:
		var transform := MofTransform.new()
		transform.code = 0
		transform.raw_values = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, index * 256, index * -512, index * 128])
		file.animated.transforms.append(transform)
	return file


func test_xar_virtual_frames_choose_the_authored_transform_of_each_part() -> void:
	var player := ModelAnimationPlayer.new(_animated())
	assert_eq(player.action_index, 0)
	assert_eq(player.action_frame_count(0), 3)
	var pose: ModelPose = player.sample_pose()
	assert_eq(pose.partcels, PackedInt32Array([0, 0]), "XAR uses static partcels, not flipbook actions")
	assert_eq(pose.transforms[0].origin, Vector3.ZERO)
	assert_eq(pose.transforms[1].origin, Vector3(1, 2, -0.5))
	player.advance_tick()
	pose = player.sample_pose()
	assert_eq(pose.transforms[0].origin, Vector3(2, 4, -1))
	assert_eq(pose.transforms[1].origin, Vector3(3, 6, -1.5))
	player.advance_tick()
	assert_eq(player.sample_pose().transforms[0].origin, Vector3.ZERO)


func test_invalid_xar_transform_reference_keeps_another_valid_action() -> void:
	var file: MofFile = _animated()
	var bad := MofAnimated.Action.new()
	bad.cel_count = 1
	bad.part_count = 2
	bad.frame_count = 1
	bad.flags = 1
	bad.cel_numbers = PackedInt32Array([0])
	bad.transform_indices = PackedInt32Array([999, 0])
	file.animated.model_sets[0].actions.append(bad)
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, 0)
	assert_false(player.set_action(1))
	assert_eq(player.action_index, 0)
	assert_false(player.action_error(1).is_empty())
	assert_eq(player.sample_pose().transforms[1].origin, Vector3(1, 2, -0.5))


func test_shared_xar_actions_may_contain_more_parts_than_this_model() -> void:
	var file: MofFile = _animated()
	file.static_models[0].parts.resize(1)
	file.animated.model_sets[0].models[0].part_count = 1
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, 0)
	assert_eq(player.sample_pose().transforms.size(), 1)
	player.advance_tick()
	assert_eq(player.sample_pose().transforms[0].origin, Vector3(2, 4, -1), "transform row stride stays the authored action part count")


func test_first_valid_xar_action_is_selected_after_a_malformed_action() -> void:
	var file: MofFile = _animated()
	var bad := MofAnimated.Action.new()
	bad.error = "broken frame table"
	file.animated.model_sets[0].actions.push_front(bad)
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, 1)
	assert_eq(player.frame, 0)
	assert_eq(player.error, "")


func test_invalid_xar_virtual_cel_and_table_lengths_do_not_reach_the_sampler() -> void:
	var file: MofFile = _animated()
	file.animated.model_sets[0].actions[0].cel_numbers[0] = 99
	var bad_cel := ModelAnimationPlayer.new(file)
	assert_eq(bad_cel.action_index, -1)
	assert_false(bad_cel.action_error(0).is_empty())
	file.animated.model_sets[0].actions[0].cel_numbers = PackedInt32Array([0])
	var bad_length := ModelAnimationPlayer.new(file)
	assert_eq(bad_length.action_index, -1)
	assert_false(bad_length.action_error(0).is_empty())
	assert_eq(bad_length.sample_pose().transforms[0], Transform3D.IDENTITY)


func test_older_xar_virtual_cels_are_one_based() -> void:
	var file: MofFile = _animated()
	file.animated.starts_at_frame_zero = false
	file.animated.model_sets[0].actions[0].cel_numbers = PackedInt32Array([1, 2, 1])
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, 0)
	assert_eq(player.sample_pose().transforms[1].origin, Vector3(1, 2, -0.5))
	player.advance_tick()
	assert_eq(player.sample_pose().transforms[1].origin, Vector3(3, 6, -1.5))


func test_seek_replays_hold_and_hide_completion() -> void:
	for mode: ModelAnimationPlayer.EndMode in [ModelAnimationPlayer.EndMode.HOLD, ModelAnimationPlayer.EndMode.HIDE]:
		var player := ModelAnimationPlayer.new(_flipbook(0, 2))
		player.end_mode = mode
		assert_true(player.seek_tick(1))
		assert_false(player.completed)
		assert_true(player.visible)
		assert_true(player.seek_tick(2))
		assert_true(player.completed)
		assert_eq(player.visible, mode == ModelAnimationPlayer.EndMode.HOLD)
		assert_eq(player.frame, 1)
		assert_true(player.seek_tick(0))
		assert_false(player.completed)
		assert_true(player.visible)


func test_independent_texture_targets_follow_their_own_lists() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([2, 4]), 2)
	var second := MofPart.TextureAnimation.new()
	second.image_ids = PackedInt32Array([20, 21, 22])
	second.durations = PackedInt32Array([3, 1, 5])
	file.static_models[0].parts[0].texture_lists.append(second)
	file.static_models[0].parts[0].texture_targets[1].list_index = 1
	var player := ModelAnimationPlayer.new(file)
	player.advance_tick()
	assert_eq(_entry(player, 0), 1)
	assert_eq(_entry(player, 1), 0)
	player.advance_tick()
	assert_eq(_entry(player, 0), 1)
	assert_eq(_entry(player, 1), 1)
	player.advance_tick()
	assert_eq(_entry(player, 0), 1)
	assert_eq(_entry(player, 1), 2)


func test_constructor_shows_the_first_update_at_tick_zero() -> void:
	var player := ModelAnimationPlayer.new(_flipbook())
	assert_eq(player.tick, 0)
	assert_eq(player.action_index, 0)
	assert_eq(player.frame, 0)
	assert_eq(player.sample_pose().partcels, PackedInt32Array([1]))
	assert_eq(player.sample_pose().transforms[0], Transform3D.IDENTITY)
	assert_true(player.visible)
	assert_false(player.completed)


func test_period_delays_later_frames_but_never_the_first_frame() -> void:
	var player := ModelAnimationPlayer.new(_flipbook())
	player.update_period = 3
	player.restart()
	assert_eq(player.frame, 0)
	player.advance_tick()
	assert_eq(player.frame, 0)
	player.advance_tick()
	assert_eq(player.frame, 0)
	player.advance_tick()
	assert_eq(player.frame, 1)
	assert_true(player.set_action(0))
	assert_eq(player.frame, -1)
	player.advance_tick()
	assert_eq(player.frame, 0, "set action forces the next update immediately")
	player.advance_tick()
	assert_eq(player.frame, 0)


func test_loop_wraps_only_after_the_last_frame() -> void:
	var player := ModelAnimationPlayer.new(_flipbook())
	player.advance_tick()
	assert_eq(player.frame, 1)
	player.advance_tick()
	assert_eq(player.frame, 2)
	assert_false(player.wrapped)
	player.advance_tick()
	assert_eq(player.frame, 0)
	assert_true(player.wrapped)
	assert_false(player.completed)
	player.advance_tick()
	assert_false(player.wrapped)


func test_hold_finishes_on_update_after_last_frame() -> void:
	var player := ModelAnimationPlayer.new(_flipbook())
	player.end_mode = ModelAnimationPlayer.EndMode.HOLD
	player.advance_tick()
	player.advance_tick()
	assert_false(player.completed)
	player.advance_tick()
	assert_true(player.completed)
	assert_true(player.visible)
	assert_eq(player.frame, 2)
	player.advance_tick()
	assert_eq(player.frame, 2)
	assert_false(player.wrapped)
	player.restart()
	assert_false(player.completed)
	assert_eq(player.frame, 0)


func test_hide_finishes_and_an_action_change_restores_visibility() -> void:
	var player := ModelAnimationPlayer.new(_flipbook(0, 1))
	player.end_mode = ModelAnimationPlayer.EndMode.HIDE
	assert_true(player.visible)
	player.advance_tick()
	assert_true(player.completed)
	assert_false(player.visible)
	assert_false(player.sample_pose().visible)
	assert_eq(player.frame, 0)
	assert_true(player.set_action(0))
	assert_true(player.visible)
	assert_false(player.completed)


func test_loop_mode_resumes_a_completed_hold_or_hide_without_resetting_textures() -> void:
	for mode: ModelAnimationPlayer.EndMode in [ModelAnimationPlayer.EndMode.HOLD, ModelAnimationPlayer.EndMode.HIDE]:
		var file: MofFile = _flipbook(0, 2)
		_textures(file, PackedInt32Array([4, 3]))
		var player := ModelAnimationPlayer.new(file)
		player.end_mode = mode
		player.advance_tick()
		player.advance_tick()
		assert_true(player.completed)
		assert_eq(player.frame, 1)
		var before: int = player.revision
		player.end_mode = ModelAnimationPlayer.EndMode.LOOP
		assert_false(player.completed)
		assert_true(player.visible)
		assert_eq(player.revision, before + 1)
		assert_eq(player.frame, 1, "switching modes retains the current geometry frame")
		assert_eq(_entry(player), 0)
		player.advance_tick()
		assert_eq(player.frame, 0)
		assert_true(player.wrapped)
		assert_eq(_entry(player), 1, "resuming keeps the independent texture duration counter")


func test_texture_clocks_increment_before_duration_comparison() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([1, 2, 3]))
	var player := ModelAnimationPlayer.new(file)
	assert_eq(_entry(player), 1, "duration one advances on the initial update")
	player.advance_tick()
	assert_eq(_entry(player), 1)
	player.advance_tick()
	assert_eq(_entry(player), 2)
	player.advance_tick()
	player.advance_tick()
	assert_eq(_entry(player), 2)
	player.advance_tick()
	assert_eq(_entry(player), 0)


func test_zero_duration_advances_once_per_update() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([0, 0, 0]))
	var player := ModelAnimationPlayer.new(file)
	assert_eq(_entry(player), 1)
	player.advance_tick()
	assert_eq(_entry(player), 2)
	player.advance_tick()
	assert_eq(_entry(player), 0)


func test_geometry_period_and_action_switch_do_not_reset_textures() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([3, 4]))
	var player := ModelAnimationPlayer.new(file)
	player.update_period = 20
	player.advance_tick()
	assert_eq(player.frame, 0)
	assert_eq(_entry(player), 0)
	assert_true(player.set_action(0))
	player.advance_tick()
	assert_eq(_entry(player), 1, "the texture clock continued across set_action")
	assert_eq(player.frame, 0)


func test_texture_disable_uses_original_texture_and_resumes_clock() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([3, 2]))
	var player := ModelAnimationPlayer.new(file)
	player.texture_animation_enabled = false
	for _tick: int in 5:
		player.advance_tick()
	assert_eq(_entry(player), -1)
	player.texture_animation_enabled = true
	assert_eq(_entry(player), 0)
	player.advance_tick()
	assert_eq(_entry(player), 0)
	player.advance_tick()
	assert_eq(_entry(player), 1, "disabled updates did not consume the duration")


func test_sampling_does_not_advance_and_returns_owned_arrays() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([3, 2]))
	var player := ModelAnimationPlayer.new(file)
	var pose: ModelPose = player.sample_pose()
	pose.partcels[0] = 999
	pose.transforms[0] = Transform3D(Basis.IDENTITY, Vector3.ONE)
	pose.texture_entries[0][0] = 999
	for _sample: int in 5:
		var next: ModelPose = player.sample_pose()
		assert_eq(next.partcels[0], 1)
		assert_eq(next.transforms[0], Transform3D.IDENTITY)
		assert_eq(next.texture_entries[0][0], 0)
	assert_eq(player.tick, 0, "pause is no calls to advance_tick")
	assert_eq(player.frame, 0)


func test_seek_replays_all_clocks_and_matches_sequential_updates() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([2, 4, 0]))
	var sequential := ModelAnimationPlayer.new(file)
	sequential.update_period = 3
	sequential.restart()
	for target: int in 30:
		var sought := ModelAnimationPlayer.new(file)
		sought.update_period = 3
		assert_true(sought.seek_tick(target))
		assert_eq(sought.tick, sequential.tick)
		assert_eq(sought.frame, sequential.frame)
		assert_eq(sought.wrapped, sequential.wrapped)
		assert_eq(_entry(sought), _entry(sequential))
		sequential.advance_tick()
	var before: int = sequential.tick
	assert_false(sequential.seek_tick(-1))
	assert_eq(sequential.tick, before)


func test_two_instances_share_source_but_not_playback_state() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([2, 4]), 2)
	var first := ModelAnimationPlayer.new(file)
	var second := ModelAnimationPlayer.new(file)
	first.advance_tick()
	first.advance_tick()
	assert_eq(first.frame, 2)
	assert_eq(second.frame, 0)
	assert_eq(_entry(first, 0), 1)
	assert_eq(_entry(first, 1), 1)
	assert_eq(_entry(second, 0), 0)
	assert_eq(file.static_models[0].parts[0].texture_lists[0].durations, PackedInt32Array([2, 4]))
	assert_eq(file.static_models[0].parts[0].flipbook_actions[0].start, 1)


func test_static_and_texture_only_models_have_no_geometry_action() -> void:
	var file: MofFile = _flipbook()
	file.static_models[0].parts[0].flipbook_actions.clear()
	_textures(file, PackedInt32Array([1, 1]))
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_count(), 0)
	assert_eq(player.action_index, -1)
	assert_eq(player.frame, -1)
	assert_eq(player.sample_pose().partcels[0], 0)
	assert_eq(_entry(player), 1)
	player.advance_tick()
	assert_eq(_entry(player), 0)
	assert_true(player.visible)


func test_no_valid_actions_keeps_static_geometry_available() -> void:
	var file: MofFile = _flipbook()
	file.static_models[0].parts[0].flipbook_actions[0].error = "bad action"
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, -1)
	assert_eq(player.action_error(0), "bad action")
	assert_eq(player.error, "no valid geometry actions")
	assert_eq(player.sample_pose().partcels[0], 0)
	assert_true(player.visible)


func test_invalid_actions_preserve_selected_action_and_state() -> void:
	var file: MofFile = _flipbook()
	var bad := MofPart.FlipbookAction.new()
	bad.start = 999
	bad.frame_count = 1
	file.static_models[0].parts[0].flipbook_actions.append(bad)
	var player := ModelAnimationPlayer.new(file)
	player.advance_tick()
	var before: int = player.revision
	assert_false(player.set_action(1))
	assert_false(player.error.is_empty())
	assert_eq(player.action_index, 0)
	assert_eq(player.frame, 1)
	assert_eq(player.revision, before)
	assert_false(player.set_action(-1))
	assert_eq(player.action_frame_count(99), 0)


func test_invalid_texture_reference_disables_only_its_target() -> void:
	var file: MofFile = _flipbook()
	_textures(file, PackedInt32Array([1, 1]), 2)
	file.static_models[0].parts[0].texture_targets[1].list_index = 9
	var player := ModelAnimationPlayer.new(file)
	assert_eq(_entry(player, 0), 1)
	assert_eq(_entry(player, 1), -1)
	assert_eq(player.diagnostics.size(), 1)
	player.advance_tick()
	assert_eq(_entry(player, 0), 0)
	assert_eq(_entry(player, 1), -1)
	player.restart()
	assert_eq(_entry(player, 1), -1)


func test_flipbook_first_part_drives_all_parts_and_reports_differing_tables() -> void:
	var file: MofFile = _flipbook(1, 3, 2)
	file.static_models[0].parts[1].flipbook_actions[0].start = 0
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.sample_pose().partcels, PackedInt32Array([1, 1]))
	assert_eq(player.diagnostics.size(), 1)
	player.advance_tick()
	assert_eq(player.sample_pose().partcels, PackedInt32Array([2, 2]))


func test_shared_flipbook_range_must_fit_every_part() -> void:
	var file: MofFile = _flipbook(1, 3, 2)
	file.static_models[0].parts[1].partcels.resize(2)
	var player := ModelAnimationPlayer.new(file)
	assert_eq(player.action_index, -1)
	assert_false(player.action_error(0).is_empty())
	assert_eq(player.sample_pose().partcels, PackedInt32Array([0, 0]))


func test_invalid_static_selection_is_safe() -> void:
	var player := ModelAnimationPlayer.new(_flipbook(), 9)
	assert_false(player.error.is_empty())
	assert_false(player.visible)
	assert_eq(player.action_count(), 0)
	assert_eq(player.sample_pose().partcels.size(), 0)
	assert_false(player.seek_tick(0))
	player.advance_tick()
	assert_eq(player.tick, -1)


func test_revision_marks_discontinuities_but_not_normal_updates() -> void:
	var player := ModelAnimationPlayer.new(_flipbook())
	var before: int = player.revision
	player.advance_tick()
	assert_eq(player.revision, before)
	assert_true(player.set_action(0))
	assert_eq(player.revision, before + 1)
	player.restart()
	assert_eq(player.revision, before + 2)
	assert_true(player.seek_tick(8))
	assert_eq(player.revision, before + 3)
