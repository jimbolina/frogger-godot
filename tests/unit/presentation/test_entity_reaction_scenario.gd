extends GutTest
## Opt-in authored entity inputs share the terrain run and viewer trace path.

func _authored() -> Dictionary:
	return {"builtin": "normal", "tick_limit": 3,
		"level": {"collision_enabled": true, "entity_collision": {
			"group_base": [-512, 0, -512], "group_dimensions": [4, 4], "group_size": [256, 256],
			"entities": [{"entity_index": 0, "unique_id": 7, "form_grid_id": 0, "form_id": 0,
				"form_name": "TEST_POP", "entity_name": "STATIC", "flags": 0,
				"matrix12": [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128]}],
			"contacts": [{"entity_index": 0, "unique_id": 7, "form_grid_id": 0, "form_id": 0,
				"form_name": "TEST_POP", "entity_flags": 0, "dimensions": [1, 1], "offsets": [-128, -128],
				"height": -100, "max_y": 100, "radius_squared": 1000000, "grid_flags": [5],
				"death_type": 5, "reaction_unsupported_reason": ""}]}},
		"commands": [{"tick": 0, "pressed": 0, "held": 0}]}

func test_opt_in_keeps_default_terrain_trace_and_detaches_definition() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_object(_authored())
	assert_eq(scenario.error, "")
	assert_not_null(scenario.entity_collision)
	assert_null(scenario.level.entity_collision)
	var original := TerrainTrace.new()
	original.configure(scenario)
	var metadata: Dictionary = JSON.parse_string(original.full_rows[0])
	var original_schema: String = metadata.schema
	assert_eq(original_schema, "terrain-run-v1")
	assert_eq(scenario.apply_arguments(PackedStringArray(["--entity-reactions=pop"])), "")
	assert_not_null(scenario.level.entity_collision)
	assert_ne(scenario.level.entity_collision, scenario.entity_collision)
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	metadata = JSON.parse_string(trace.full_rows[0])
	var reaction_schema: String = metadata.schema
	var group_base: Array = metadata.entity_collision.group_base
	assert_eq(reaction_schema, "entity-pop-v1")
	assert_eq(group_base, [-512.0, 0.0, -512.0])
	assert_eq(scenario.apply_arguments(PackedStringArray()), "")
	assert_null(scenario.level.entity_collision)

func test_viewer_draws_committed_entity_snapshot_and_contact_overlay() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_object(_authored())
	assert_eq(scenario.apply_arguments(PackedStringArray(["--entity-reactions=pop"])), "")
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	viewer.record_trace = true
	add_child_autofree(viewer)
	viewer.set_process(false)
	assert_eq(viewer.open_scenario(scenario), "")
	assert_eq(viewer._entity_inspection.marker_count(), 1)
	assert_not_null(viewer.run.snapshot().entities)
	var before: String = JSON.stringify(TerrainTrace.facts(viewer.run.snapshot()))
	viewer.draw_state(0.2)
	viewer.draw_state(0.9)
	assert_eq(JSON.stringify(TerrainTrace.facts(viewer.run.snapshot())), before)
	var result: TickResult = viewer.step_scenario()
	assert_eq(result.error, "")
	assert_eq(viewer.trace.full_rows.size(), 6)
	var final_row: Dictionary = JSON.parse_string(viewer.trace.full_rows[5])
	assert_true(final_row.has("entity_contacts"))
	var entity_tick: float = final_row.state.entities.tick_index
	assert_eq(entity_tick, 1.0)
	assert_eq(viewer._entity_inspection.marker_count(), 1)
	assert_eq(viewer.open_data(null), "")
	assert_eq(viewer._entity_models.size(), 0)

func test_invalid_fixture_and_disabled_authored_collision_are_rejected() -> void:
	var malformed: Dictionary = _authored()
	malformed.level.entity_collision.contacts[0].entity_index = 4
	assert_string_contains(TerrainScenario.from_object(malformed).error, "mismatched identity")
	var disabled: Dictionary = _authored()
	disabled.level.collision_enabled = false
	var scenario: TerrainScenario = TerrainScenario.from_object(disabled)
	assert_eq(scenario.error, "")
	assert_string_contains(scenario.apply_arguments(PackedStringArray(["--entity-reactions=pop"])), "collision_enabled")

func test_des2_demo_defaults_preserve_authored_inputs_and_tick_override() -> void:
	var canned: TerrainScenario = TerrainScenario.builtin("normal")
	canned.level_code = "DES2"
	assert_eq(canned.apply_arguments(PackedStringArray(["--entity-reactions=pop", "--tick-limit=44"])), "")
	canned.apply_des2_inspection_defaults()
	assert_eq(canned.initial.spawn_cell, Vector2i(17, 30))
	assert_eq(canned.initial.spawn_direction, 1)
	assert_eq(canned.tick_limit, 44)
	assert_eq(canned.command_at(0).pressed_mask, TickCommand.EAST)
	var authored: TerrainScenario = TerrainScenario.from_object(_authored())
	authored.level_code = "DES2"
	assert_eq(authored.apply_arguments(PackedStringArray(["--entity-reactions=pop"])), "")
	var original_commands: int = authored.command_at(0).pressed_mask
	authored.apply_des2_inspection_defaults()
	assert_eq(authored.tick_limit, 3)
	assert_eq(authored.initial.spawn_cell, Vector2i(-1, -1))
	assert_eq(authored.command_at(0).pressed_mask, original_commands)
