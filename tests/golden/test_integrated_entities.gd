extends GutTest
## Independent Python and unchanged frozen C constrain integrated POP trajectories.

func _represented(state: GameplayState) -> Array[int]:
	var camera: GameplayCameraSnapshot = state.camera
	var animation: FrogAnimationState = state.animation
	var values: Array[int] = [state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z,
		state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z,
		state.frog.cell.x, state.frog.cell.y, state.frog.remaining_ticks, state.frog.flags, state.frog.mode,
		state.frog.current_input, state.frog.direction, state.frog.no_input_timer, state.frog.death_count,
		camera.mode, camera.move_timer, camera.twist_counter,
		camera.tracked_world.x, camera.tracked_world.y, camera.tracked_world.z,
		camera.source_world.x, camera.source_world.y, camera.source_world.z,
		camera.controller_directions[0], camera.shake_timer,
		animation.script_type, animation.script_timer, animation.flags,
		animation.environment_flags, state.rng_state, state.frog.animation_condition_counter,
		animation.program_id, animation.word_offset, animation.action, animation.cel,
		animation.total_cels, animation.update_count,
		10 if state.requests.game_mode_request < 0 else state.requests.game_mode_request]
	for index: int in 2:
		if index >= state.entities.entities.size():
			values.append_array([-1, -1, -1, -1, -1, 0])
			continue
		var entity: EntitySnapshot = state.entities.entities[index]
		values.append_array([entity.matrix12[9], entity.matrix12[10], entity.matrix12[11],
			entity.path.segment_distance if entity.path != null else -1,
			entity.path.total_distance if entity.path != null else -1,
			entity.path.flags if entity.path != null else 0])
	return values

func _joined(indices: PackedInt32Array) -> String:
	if indices.is_empty():
		return "-"
	var parts := PackedStringArray()
	for index: int in indices:
		parts.append(str(index))
	return ";".join(parts)

func test_integrated_entity_trajectories_match_frozen_c() -> void:
	var fixture_text: String = FileAccess.get_file_as_string("res://tests/golden/fixtures/integrated_entities.json")
	var document: Variant = JSON.parse_string(fixture_text)
	assert_true(document is Dictionary)
	var root: Dictionary = document
	var cases: Array = root["cases"]
	assert_eq(cases.size(), 3)
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/integrated_entities.tsv").strip_edges().split("\n")
	assert_eq(lines.size(), 1279)
	var row_index: int = 1
	for scenario_index: int in cases.size():
		var case_data: Dictionary = cases[scenario_index]
		var scenario: TerrainScenario = TerrainScenario.from_object(case_data)
		assert_eq(scenario.error, "")
		scenario.level.entity_collision = scenario.entity_collision.copy()
		var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
		assert_eq(run.error, "")
		var cumulative_pops: int = 0
		for tick: int in 71:
			var result: TickResult = run.step(scenario.command_at(tick))
			assert_eq(result.error, "", "scenario %d tick %d" % [scenario_index, tick])
			if not result.error.is_empty():
				return
			var popped: bool = TickEvent.trace_lines(result.events).has("entity_pop_explosion_request")
			var stages: Array[GameplayState] = [result.control_snapshot, result.move_snapshot,
				result.collision_snapshot, result.camera_snapshot, null, result.final_snapshot]
			for phase: int in 6:
				var expected: PackedStringArray = lines[row_index].strip_edges().split("\t")
				assert_eq(expected.size(), 59)
				assert_eq(expected[0].to_int(), scenario_index)
				assert_eq(expected[1].to_int(), tick)
				if phase != 4:
					var snapshot: GameplayState = stages[phase]
					var represented: Array[int] = _represented(snapshot)
					for field: int in represented.size():
						assert_eq(represented[field], expected[field + 3].to_int(),
							"scenario %d tick %d phase %d field %d" % [scenario_index, tick, phase, field])
					assert_eq(_joined(EntityContactOrder.indices(scenario.entity_collision, snapshot.entities, snapshot.frog.world_position)), expected[54])
					assert_eq(_joined(snapshot.attachment.entity_hit_indices), expected[55])
					assert_eq(snapshot.attachment.death_entity_index, expected[56].to_int())
					assert_eq(cumulative_pops + (1 if popped and phase >= 2 else 0), expected[57].to_int())
					assert_eq(snapshot.requests.sound_requests, expected[58].to_int())
				row_index += 1
			if popped:
				cumulative_pops += 1
		assert_true(run.snapshot().completed)
	assert_eq(row_index, lines.size())
