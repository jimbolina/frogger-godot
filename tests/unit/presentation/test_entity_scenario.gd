extends GutTest
## Asset-free attached-entity scenario and trace contracts.

func test_builtin_shares_path_but_owns_independent_cursors() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_eq(scenario.error, "")
	assert_eq(scenario.definitions.size(), 4)
	assert_eq(scenario.contact_definitions.size(), 4)
	assert_eq(scenario.contact_entity_index, 1)
	assert_eq(scenario.probe_world, Vector3i(-100, 0, 0))
	assert_eq(scenario.definitions[0].entity_name, "STATIC")
	assert_eq(scenario.definitions[1].path_definition.path_index, scenario.definitions[2].path_definition.path_index)
	assert_not_same(scenario.definitions[1].path_definition, scenario.definitions[2].path_definition)
	assert_eq(scenario.definitions[2].flags, EntityDefinition.NO_MOVEMENT)
	assert_true(bool(scenario.definitions[3].path_start.flags & PathStart.BACKWARDS))
	assert_eq(scenario.definitions[3].flags, EntityDefinition.ALIGN_TO_WORLD)
	var run: EntityRun = EntityRun.create(scenario.definitions)
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	var snapshot: EntityRunSnapshot = run.snapshot()
	assert_eq(snapshot.entities[1].path.segment_distance, 10)
	assert_eq(snapshot.entities[2].path.segment_distance, 0)
	assert_eq(snapshot.entities[3].path.segment_distance, 146)

func test_invalid_selection_and_player_data_report_errors() -> void:
	assert_string_contains(EntityScenario.builtin("missing").error, "Unknown")
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_string_contains(scenario.attach_data(null), "valid player data")
	var invalid := GameData.new()
	invalid.error = "bad data"
	assert_string_contains(scenario.attach_data(invalid), "valid player data")

func test_trace_records_metadata_and_every_snapshot_deterministically() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	var run: EntityRun = EntityRun.create(scenario.definitions)
	var trace := EntityTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(run.snapshot())
	for tick: int in 3:
		assert_eq(run.step(tick), "")
		trace.append_snapshot(run.snapshot())
	assert_eq(trace.rows.size(), 5)
	var metadata: Dictionary = JSON.parse_string(trace.rows[0])
	var schema: String = metadata["schema"]
	var identities: Array = metadata["entities"]
	assert_eq(schema, "entity-contact-v1")
	assert_eq(identities.size(), 4)
	var contacts: Array = metadata["contacts"]
	assert_eq(contacts.size(), 4)
	var probe_values: Array = metadata["probe_world"]
	assert_eq(probe_values, [-100.0, 0.0, 0.0])
	var tick_one: Dictionary = JSON.parse_string(trace.rows[2])
	var tick_index: int = tick_one["tick_index"]
	var entities: Array = tick_one["entities"]
	var static_row: Dictionary = entities[0]
	var first_moving: Dictionary = entities[1]
	var stopped_moving: Dictionary = entities[2]
	var first_path: Dictionary = first_moving["path"]
	var stopped_path: Dictionary = stopped_moving["path"]
	var moving_contact: Dictionary = first_moving["contact"]
	var contact_status: String = moving_contact["status"]
	var contact_local: Array = moving_contact["local_position"]
	var contact_cell: Array = moving_contact["cell"]
	var contact_flags: int = moving_contact["cell_flags"]
	assert_eq(contact_status, FormContactResult.CONTACT)
	assert_eq(contact_local, [0.0, 0.0, -10.0])
	assert_eq(contact_cell, [1.0, 0.0])
	assert_eq(contact_flags, 1)
	var first_distance: int = first_path["segment_distance"]
	var stopped_distance: int = stopped_path["segment_distance"]
	var static_path_is_null: bool = static_row["path"] == null
	var static_matrix: Array = static_row["matrix12"]
	assert_eq(tick_index, 1)
	assert_eq(first_distance, 10)
	assert_eq(stopped_distance, 0)
	assert_true(static_path_is_null)
	assert_eq(static_matrix.size(), 12)
	assert_ne(trace.save("relative.jsonl"), "")
