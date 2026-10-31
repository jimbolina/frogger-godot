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
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "")
	assert_not_null(scenario.level.entity_collision)
	assert_ne(scenario.level.entity_collision, scenario.entity_collision)
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	metadata = JSON.parse_string(trace.full_rows[0])
	var reaction_schema: String = metadata.schema
	var collision_metadata: Dictionary = metadata.entity_collision
	var group_base: Array = collision_metadata.group_base
	assert_eq(reaction_schema, "entity-pop-v1")
	assert_eq(group_base, [-512.0, 0.0, -512.0])
	assert_false(collision_metadata.has("lifecycle"))
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray()), "")
	assert_null(scenario.level.entity_collision)

func test_authored_legacy_platforms_still_require_reaction_opt_in() -> void:
	var authored: Dictionary = _authored()
	authored.level.entity_collision["platforms_enabled"] = true
	var scenario: TerrainScenario = TerrainScenario.from_object(authored)
	assert_eq(scenario.error, "")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray()), "")
	assert_false(scenario.options.entity_reactions)
	assert_false(scenario.options.platforms_enabled)
	assert_null(scenario.level.entity_collision)
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	var metadata: Dictionary = JSON.parse_string(trace.full_rows[0])
	var schema: String = metadata.schema
	assert_eq(schema, "terrain-run-v1")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=platforms"])), "")
	assert_true(scenario.options.platforms_enabled)
	assert_not_null(scenario.level.entity_collision)

func test_viewer_draws_committed_entity_snapshot_and_contact_overlay() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_object(_authored())
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "")
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
	var final_state: Dictionary = final_row.state
	var final_entities: Dictionary = final_state.entities
	var entity_tick: float = final_entities.tick_index
	assert_eq(entity_tick, 1.0)
	assert_false(final_entities.has("lifecycle_enabled"))
	assert_false(final_entities.has("live_order"))
	var rows: Array = final_entities.entities
	var first_entity: Dictionary = rows[0]
	assert_false(first_entity.has("live"))
	assert_false(first_entity.has("generation"))
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
	assert_string_contains(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "collision_enabled")

func test_des2_demo_defaults_preserve_authored_inputs_and_tick_override() -> void:
	var canned: TerrainScenario = TerrainScenario.builtin("normal")
	canned.level_code = "DES2"
	assert_eq(TerrainScenarioArguments.apply(canned, PackedStringArray(["--entity-reactions=pop", "--tick-limit=44"])), "")
	canned.apply_level_start()
	assert_eq(canned.initial.spawn_cell, Vector2i(17, 30))
	assert_eq(canned.initial.spawn_direction, 1)
	assert_eq(canned.tick_limit, 44)
	assert_eq(canned.command_at(0).pressed_mask, TickCommand.EAST)
	var authored: TerrainScenario = TerrainScenario.from_object(_authored())
	authored.level_code = "DES2"
	assert_eq(TerrainScenarioArguments.apply(authored, PackedStringArray(["--entity-reactions=pop"])), "")
	var original_commands: int = authored.command_at(0).pressed_mask
	authored.apply_level_start()
	assert_eq(authored.tick_limit, 3)
	assert_eq(authored.initial.spawn_cell, Vector2i(-1, -1))
	assert_eq(authored.command_at(0).pressed_mask, original_commands)

func test_authored_lifecycle_auto_selects_new_trace_without_changing_legacy_default() -> void:
	var authored: Dictionary = _authored()
	var counts: Array = []
	counts.resize(16)
	counts.fill(0)
	authored.level.entity_collision.lifecycle = {"polygon_counts": counts}
	var scenario: TerrainScenario = TerrainScenario.from_object(authored)
	assert_eq(scenario.error, "")
	assert_not_null(scenario.entity_collision.lifecycle)
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "")
	assert_true(scenario.options.entity_lifecycle)
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	var metadata: Dictionary = JSON.parse_string(trace.full_rows[0])
	var schema: String = metadata.schema
	var lifetime: String = metadata.entity_lifetime
	assert_eq(schema, "entity-lifecycle-v1")
	assert_eq(lifetime, "visibility")
	var visibility_metadata: Dictionary = metadata.entity_collision
	assert_true(visibility_metadata.has("lifecycle"))
	var legacy_facts: Dictionary = TerrainTrace.facts(EntityRunSnapshot.new())
	var lifecycle_facts: Dictionary = TerrainTrace.facts(EntityRunSnapshot.new(), true)
	assert_false(legacy_facts.has("lifecycle_enabled"))
	assert_true(lifecycle_facts.has("lifecycle_enabled"))
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop", "--entity-lifecycle=all-attached"])), "")
	assert_false(scenario.options.entity_lifecycle)
	assert_null(scenario.level.entity_collision.lifecycle)
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-lifecycle=visibility"])), "")
	assert_true(scenario.options.entity_reactions)
	assert_true(scenario.options.entity_lifecycle)
	authored.level.entity_collision.lifecycle.polygon_counts = [0]
	assert_string_contains(TerrainScenario.from_object(authored).error, "one polygon count")

func test_visibility_requires_entity_source_before_tick_execution() -> void:
	var builtin: TerrainScenario = TerrainScenario.builtin("normal")
	assert_string_contains(TerrainScenarioArguments.apply(builtin, PackedStringArray(["--entity-lifecycle=visibility"])), "authored entity fixture or player data")
	assert_eq(TerrainScenarioArguments.apply(builtin, PackedStringArray(["--entity-lifecycle=visibility", "--frog-assets"])), "Visibility lifecycle requires an authored entity fixture or player data with --level")

func test_lifecycle_overlay_releases_and_recreates_only_live_markers() -> void:
	var overlay := EntityInspection.new()
	add_child_autofree(overlay)
	var definition := EntityDefinition.new()
	definition.entity_index = 9
	var definitions: Array[EntityDefinition] = [definition]
	overlay.configure(definitions)
	assert_eq(overlay.marker_count(), 1)
	var snapshot := EntityRunSnapshot.new()
	snapshot.lifecycle_enabled = true
	var entity := EntitySnapshot.new()
	entity.entity_index = 9
	entity.live = false
	snapshot.entities.append(entity)
	overlay.set_snapshot(snapshot)
	assert_eq(overlay.marker_count(), 0)
	entity.live = true
	entity.generation = 1
	overlay.set_snapshot(snapshot)
	assert_eq(overlay.marker_count(), 1)
	var old: WeakRef = weakref(overlay._positions[0])
	entity.live = false
	overlay.set_snapshot(snapshot)
	assert_eq(overlay.marker_count(), 0)
	await get_tree().process_frame
	var released: Object = old.get_ref()
	assert_null(released)
	entity.live = true
	entity.generation = 2
	overlay.set_snapshot(snapshot)
	assert_eq(overlay.marker_count(), 1)
	var prior_generation: WeakRef = weakref(overlay._positions[0])
	entity.generation = 3
	overlay.set_snapshot(snapshot)
	assert_eq(overlay.marker_count(), 1)
	await get_tree().process_frame
	var released_generation: Object = prior_generation.get_ref()
	assert_null(released_generation)

func test_exploration_arguments_require_audited_level_and_all_attached_platforms() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var arguments := PackedStringArray(["--exploration=jun1-log-bank", "--level=JUN1"])
	assert_eq(TerrainScenarioArguments.apply(scenario, arguments), "")
	assert_true(scenario.options.entity_reactions)
	assert_true(scenario.options.platforms_enabled)
	assert_false(scenario.options.entity_lifecycle)
	arguments.append("--entity-lifecycle=visibility")
	assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "cannot be combined")
	arguments.remove_at(arguments.size() - 1)
	arguments.append("--entity-reactions=pop")
	assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "requires platform reactions")
	arguments.remove_at(arguments.size() - 1)
	arguments[1] = "--level=ORG1"
	assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "requires --level=JUN1")
	arguments[0] = "--exploration=unknown"
	assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "must be jun1-log-bank")

func test_integrated_lifecycle_fixture_decodes_and_selects_visibility() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_file("res://tests/golden/fixtures/lifecycle_integrated.json")
	assert_eq(scenario.error, "")
	assert_eq(scenario.tick_limit, 336)
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-lifecycle=visibility"])), "")
	assert_true(scenario.options.entity_reactions)
	assert_true(scenario.options.entity_lifecycle)
	assert_not_null(scenario.level.entity_collision)
	assert_eq(scenario.level.entity_collision.lifecycle.polygon_counts.size(), 1024)

func test_org1_presets_require_org1_all_attached_platforms() -> void:
	for preset: String in [Org1ExplorationSetup.PRESET, Org1ExplorationSetup.ROAD_PRESET]:
		var scenario: TerrainScenario = TerrainScenario.builtin("normal")
		var arguments := PackedStringArray(["--exploration=" + preset, "--level=ORG1"])
		assert_eq(TerrainScenarioArguments.apply(scenario, arguments), "")
		assert_true(scenario.options.entity_reactions)
		assert_true(scenario.options.platforms_enabled)
		assert_false(scenario.options.entity_lifecycle)
		arguments.append("--entity-lifecycle=visibility")
		assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "cannot be combined")
		arguments.remove_at(arguments.size() - 1)
		arguments.append("--entity-reactions=pop")
		assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "requires platform reactions")
		arguments.remove_at(arguments.size() - 1)
		arguments[1] = "--level=JUN1"
		assert_string_contains(TerrainScenarioArguments.apply(scenario, arguments), "requires --level=ORG1")

func test_lifecycle_model_allocation_resets_animation_on_new_generation() -> void:
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	var state := GameplayState.new()
	state.entities = EntityRunSnapshot.new()
	state.entities.lifecycle_enabled = true
	var subject := EntitySnapshot.new()
	subject.live = false
	state.entities.entities.append(subject)
	viewer._current = state
	viewer._entity_models.append(null)
	viewer._entity_meshes.append(ModelMesh.new())
	var file := MofFile.new()
	file.static_models.append(MofStatic.new())
	viewer._entity_files.append(file)
	viewer._entity_generations.append(-1)
	assert_true(viewer._sync_entity_models().is_empty())
	assert_null(viewer._entity_models[0])
	subject.live = true
	subject.generation = 1
	assert_eq(viewer._sync_entity_models(), PackedInt32Array([0]))
	var first: AnimatedModelInstance = viewer._entity_models[0]
	assert_eq(first.player.tick, 0)
	assert_true(viewer._sync_entity_models().is_empty())
	assert_eq(viewer._entity_models[0], first)
	first.advance_tick()
	assert_eq(first.player.tick, 1)
	subject.generation = 2
	assert_eq(viewer._sync_entity_models(), PackedInt32Array([0]))
	assert_ne(viewer._entity_models[0], first)
	assert_eq(viewer._entity_models[0].player.tick, 0)
	subject.live = false
	assert_true(viewer._sync_entity_models().is_empty())
	assert_null(viewer._entity_models[0])
