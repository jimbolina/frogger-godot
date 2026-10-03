extends GutTest
## Platform phases against independently generated frozen C trajectories.

const FIXTURE: String = "res://tests/golden/fixtures/platforms.json"
const TRACE: String = "res://tests/golden/synthetic/platforms.tsv"

func _joined(indices: PackedInt32Array) -> String:
	if indices.is_empty():
		return "-"
	var parts := PackedStringArray()
	for index: int in indices:
		parts.append(str(index))
	return ";".join(parts)

func _fields(state: RunSnapshot, pgen_requests: int) -> Dictionary:
	var entity: EntitySnapshot = state.entities.entities[0]
	var fields: Dictionary = {
		"x16": state.position_16.x,
		"y16": state.position_16.y,
		"z16": state.position_16.z,
		"vx16": state.velocity_16.x,
		"vy16": state.velocity_16.y,
		"vz16": state.velocity_16.z,
		"count": state.remaining_ticks,
		"flags": state.flags,
		"mode": state.mode,
		"input": state.current_input,
		"direction": state.direction,
		"camera_mode": state.camera.mode,
		"camera_x": state.camera.tracked_world.x,
		"camera_y": state.camera.tracked_world.y,
		"camera_z": state.camera.tracked_world.z,
		"source_x": state.camera.source_world.x,
		"source_y": state.camera.source_world.y,
		"source_z": state.camera.source_world.z,
		"rng_seed": state.rng_state,
		"no_input_timer": state.no_input_timer,
		"animation_type": state.animation.script_type,
		"script_timer": state.animation.script_timer,
		"animation_flags": state.animation.flags,
		"env_flags": state.animation.environment_flags,
		"if_counter": state.animation_condition_counter,
		"program": state.animation.program_id,
		"offset": state.animation.word_offset,
		"action": state.animation.action,
		"cel": state.animation.cel,
		"total": state.animation.total_cels,
		"update_count": state.animation.update_count,
		"e0x": entity.matrix12[9],
		"e0y": entity.matrix12[10],
		"e0z": entity.matrix12[11],
		"e0segment": entity.path.segment_distance if entity.path != null else -1,
		"current_entity_index": state.current_entity_index,
		"forbidden_entity_index": state.forbidden_entity_index,
		"entity_cell_x": state.entity_cell.x,
		"entity_cell_z": state.entity_cell.y,
		"entity_offset_x16": state.entity_offset_16.x,
		"entity_offset_y16": state.entity_offset_16.y,
		"entity_offset_z16": state.entity_offset_16.z,
		"entity_angle": state.entity_angle,
		"old_y": state.old_y,
		"entity_carry_indices": _joined(state.entity_carry_indices),
		"camera_current_ytheta": state.camera.current_ytheta,
		"camera_destination_ytheta": state.camera.destination_ytheta,
		"camera_delta_ytheta": state.camera.delta_ytheta,
		"pgen_requests": pgen_requests,
		"sound_requests": state.sound_requests,
	}
	var axes: Array[String] = ["00", "01", "02", "10", "11", "12", "20", "21", "22", "_t0", "_t1", "_t2"]
	for index: int in 12:
		fields["entity_transform" + axes[index]] = state.entity_transform12[index]
		fields["camera_mod" + axes[index]] = state.camera.mod_matrix12[index]
	for index: int in 4:
		var prefix: String = ["n", "e", "s", "w"][index]
		var vector: Vector3i = state.camera.direction_vectors_12[index]
		fields["camera_direction_" + prefix + "_x"] = vector.x
		fields["camera_direction_" + prefix + "_y"] = vector.y
		fields["camera_direction_" + prefix + "_z"] = vector.z
	return fields

func test_platform_phase_trajectories_match_frozen_c() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var cases: Array = parsed["cases"]
	var lines: PackedStringArray = FileAccess.get_file_as_string(TRACE).strip_edges().split("\n")
	assert_true(lines.size() > 1)
	if lines.size() <= 1:
		return
	var header: PackedStringArray = lines[0].trim_suffix("\r").split("\t")
	var phase_names: PackedStringArray = PackedStringArray(["control", "move", "collision", "camera", "scripts", "pose"])
	var row_index: int = 1
	for scenario_index: int in cases.size():
		var case_data: Dictionary = cases[scenario_index]
		var scenario: TerrainScenario = TerrainScenario.from_object(case_data)
		assert_eq(scenario.error, "", str(case_data.get("name", scenario_index)))
		if not scenario.error.is_empty():
			continue
		scenario.level.entity_collision = scenario.entity_collision.copy()
		var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
		assert_eq(run.error, "")
		if not run.error.is_empty():
			continue
		var cumulative_pops: int = 0
		for tick: int in scenario.tick_limit:
			var result: TickResult = run.step(scenario.command_at(tick))
			assert_eq(result.error, "", "scenario %d tick %d" % [scenario_index, tick])
			if not result.error.is_empty():
				return
			var popped: bool = result.events.has("entity_pop_explosion_request")
			var stages: Array[RunSnapshot] = [result.control_snapshot, result.move_snapshot,
				result.collision_snapshot, result.camera_snapshot, result.scripts_snapshot, result.final_snapshot]
			for phase: int in 6:
				assert_true(row_index < lines.size(), "Trace is shorter than fixture")
				if row_index >= lines.size():
					return
				var expected: PackedStringArray = lines[row_index].trim_suffix("\r").split("\t")
				assert_eq(expected.size(), header.size())
				assert_eq(int(expected[0]), scenario_index)
				assert_eq(int(expected[1]), tick)
				assert_eq(expected[2], phase_names[phase])
				var snapshot: RunSnapshot = stages[phase]
				var fields: Dictionary = _fields(snapshot, cumulative_pops + (1 if popped and phase >= 2 else 0))
				for column: int in range(3, header.size()):
					var name: String = header[column]
					assert_true(fields.has(name), "Unmapped oracle field " + name)
					if fields.has(name):
						var actual: Variant = fields[name]
						assert_eq(str(actual), expected[column],
							"scenario %d tick %d phase %d column %s" % [scenario_index, tick, phase, name])
				row_index += 1
			if popped:
				cumulative_pops += 1
	assert_eq(row_index, lines.size(), "Trace has no unused platform rows")

func test_acos12_full_source_table_digest() -> void:
	var values := PackedStringArray()
	for value: int in range(-4096, 4097):
		values.append(str(PlatformMath.acos12(value)))
	var context := HashingContext.new()
	assert_eq(context.start(HashingContext.HASH_SHA256), OK)
	assert_eq(context.update(",".join(values).to_utf8_buffer()), OK)
	var expected: String = FileAccess.get_file_as_string("res://tests/golden/synthetic/platform_acos_digest.txt").strip_edges()
	assert_eq(context.finish().hex_encode(), expected)
