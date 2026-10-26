extends RetailTest
## Full admitted ORG1 phases and ordered visits against independent source facts.

var _data: GameData
var _workers: Array[TerrainTickWorker] = []

func after_each() -> void:
	for worker: TerrainTickWorker in _workers:
		worker.close()
	_workers.clear()

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _scenario(preset: String = Org1ExplorationSetup.PRESET) -> TerrainScenario:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.options.reactions = ScenarioOptions.Reaction.POP
	scenario.options.reactions = ScenarioOptions.Reaction.PLATFORMS
	scenario.options.exploration_preset = preset
	scenario.error = scenario.attach_data(_data, "ORG1")
	return scenario

func test_round_trip_and_complete_dive_cycles_match_source() -> void:
	_route("org1_round_trip", 730, {0: 1, 12: 1, 34: 4, 46: 4})

func test_visibility_round_trip_and_background_lifetimes_match_source() -> void:
	_route("org1_visibility_round_trip", 730, {0: 1, 12: 1, 34: 4, 46: 4}, Org1ExplorationSetup.VISIBILITY_PRESET)

func test_visibility_pink_frog_pickup_matches_source() -> void:
	_route("org1_visibility_pickup", 490, {406: 1, 418: 1, 442: 4, 454: 4}, Org1ExplorationSetup.VISIBILITY_PRESET)

func test_visibility_pink_frog_death_matches_source() -> void:
	_route("org1_visibility_pickup_death", 472, {406: 1, 418: 1, 442: 4}, Org1ExplorationSetup.VISIBILITY_PRESET)

func test_visibility_pickup_rollback_and_full_reset() -> void:
	var scenario: TerrainScenario = _scenario(Org1ExplorationSetup.VISIBILITY_PRESET)
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	assert_true((scenario.level.tick_guard as ExplorationGuard).collectable_indices.is_empty())
	assert_true((scenario.level.tick_guard as ExplorationGuard).scripted_visibility_admitted)
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	for tick: int in 446:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = 1 if tick in [406, 418] else 4 if tick == 442 else 0
		command.held_mask = command.pressed_mask
		if tick == 445:
			var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
			assert_true(run.snapshot().attachment.entity_hit_indices.has(53))
			assert_eq(run.snapshot().entities.entities[53].custom_state.carrier_index, -1)
			run._entities._lifecycle.polygon_counts.fill(2500)
			var rejected: TickResult = run.step(command)
			assert_ne(rejected.error, "")
			assert_null(rejected.final_snapshot)
			assert_true(rejected.events.is_empty())
			assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
			run._entities._lifecycle.polygon_counts = scenario.level.entity_collision.lifecycle.polygon_counts.duplicate()
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
	assert_eq(run.snapshot().entities.entities[53].custom_state.carrier_index, 0)
	assert_eq(run.reset(scenario.initial), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)

func test_visibility_attached_diver_matches_source() -> void:
	_route("org1_visibility_diver", 203, {170: 1}, Org1ExplorationSetup.VISIBILITY_PRESET)
	var scenario: TerrainScenario = _scenario(Org1ExplorationSetup.VISIBILITY_PRESET)
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var command := TickCommand.new()
	command.tick_index = 0
	var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	run._entities._lifecycle.polygon_counts.fill(2500)
	var rejected: TickResult = run.step(command)
	assert_false(rejected.error.is_empty())
	assert_null(rejected.control_snapshot)
	assert_null(rejected.final_snapshot)
	assert_true(rejected.events.is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	run._entities._lifecycle.polygon_counts = scenario.level.entity_collision.lifecycle.polygon_counts.duplicate()
	assert_eq(run.step(command).error, "")
	command.tick_index = 1
	run._entities._state.entities[0].script_state.cursor = 999999
	before = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	rejected = run.step(command)
	assert_false(rejected.error.is_empty())
	assert_true(rejected.events.is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	assert_eq(run.reset(scenario.initial), "")
	assert_eq(run.snapshot().entities.live_order, PackedInt32Array([63, 62, 61, 60, 59, 58, 57, 56, 55, 53]))

func test_attached_diver_drowns_before_control_matches_source() -> void:
	_route("org1_attached_diver", 1255, {1230: 1})

func test_road_to_river_crossing_matches_source() -> void:
	_road_route("org1_road_river")

func test_road_vehicle_death_matches_source() -> void:
	_road_route("org1_road_vehicle_death")

func _road_route(name: String) -> void:
	var fixture: TerrainScenario = TerrainScenario.from_file("res://tests/golden/fixtures/" + name + ".json")
	assert_eq(fixture.error, "")
	if not fixture.error.is_empty():
		return
	_route(name, fixture.tick_limit, fixture.commands, Org1ExplorationSetup.ROAD_PRESET)

func test_road_admission_and_rejected_tick_are_atomic() -> void:
	var scenario: TerrainScenario = _scenario(Org1ExplorationSetup.ROAD_PRESET)
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	assert_eq(scenario.identifier, Org1ExplorationSetup.ROAD_PRESET)
	assert_eq(scenario.initial.spawn_cell, Vector2i(10, 1))
	assert_eq(scenario.level.entity_collision.entities.size(), 64)
	assert_null(scenario.level.entity_collision.lifecycle)
	assert_not_null(scenario.level.entity_collision.frog_collision)
	var traffic_count: int = 0
	for contact: FormContactDefinition in scenario.level.entity_collision.contacts:
		if contact.entity_index >= 24 and contact.entity_index <= 47:
			assert_eq(contact.unsupported_reason, "")
			assert_eq(contact.disabled_reason, "")
			assert_eq(contact.primitives.size(), 1)
			assert_false(contact.has_form_data)
			traffic_count += 1
	assert_eq(traffic_count, 24)
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var rejected: bool = false
	for tick: int in 20:
		var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = TickCommand.SOUTH if tick == 0 else 0
		command.held_mask = command.pressed_mask
		var result: TickResult = run.step(command)
		if not result.error.is_empty():
			assert_string_contains(result.error, "boundary")
			assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
			assert_null(result.control_snapshot)
			assert_true(result.entity_contacts.is_empty())
			assert_true(result.primitive_contacts.is_empty())
			rejected = true
			break
	assert_true(rejected, "A southward hop rejects the entire candidate at the audited boundary")
	assert_eq(run.reset(scenario.initial), "")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)

func test_admission_dependencies_and_complete_reset() -> void:
	var scenario: TerrainScenario = _scenario()
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	assert_eq(scenario.commands.size(), 0)
	assert_eq(scenario.level.entity_collision.entities.size(), 64)
	assert_eq((scenario.level.tick_guard as ExplorationGuard).world_bounds, Rect2i(-512, -128, 1024, 608))
	var form: FormBookEntry = _data.tables.theme_book().get_form(5, 3)
	var old_radius: int = form.radius_squared
	form.radius_squared += 1
	var rejected: TerrainScenario = _scenario()
	form.radius_squared = old_radius
	assert_string_contains(rejected.error, "proof inputs changed")
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.SOUTH
	command.held_mask = command.pressed_mask
	assert_string_contains(run.step(command, false).error, "boundary")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)
	for tick: int in 65:
		command = TickCommand.new()
		command.tick_index = tick
		assert_eq(run.step(command, false).error, "")
	assert_ne(run.snapshot().entity_environment.covered, 0)
	assert_eq(run.reset(scenario.initial), "")
	assert_true(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)) == initial, "Every reset field matches the selected inspection start")
	scenario.initial.powerup_flags = 1
	assert_string_contains(GameplayRun.create(scenario.level, scenario.initial).error, "unpowered")
	scenario.initial.powerup_flags = 0
	scenario.level.tick_guard = null
	assert_eq(GameplayRun.create(scenario.level, scenario.initial).error, "Disabled contacts require a tick guard")

func _route(name: String, ticks: int, commands: Dictionary, preset: String = Org1ExplorationSetup.PRESET) -> void:
	var scenario: TerrainScenario = _scenario(preset)
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var live: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	var worker := TerrainTickWorker.new()
	_workers.append(worker)
	assert_eq(worker.start(live), OK)
	var rows: Array[PackedStringArray] = GoldenFiles.rows(name + ".tsv")
	var digests: Array[PackedStringArray] = GoldenFiles.rows(name + "_entities.tsv")
	var fields: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/org1_entity_update_fields.json"))
	var field_names := PackedStringArray()
	for field: String in fields:
		field_names.append(field)
	var header: PackedStringArray = rows[0]
	for index: int in header.size():
		header[index] = header[index].strip_edges()
	assert_eq(rows.size(), ticks * 6 + 1)
	assert_eq(digests.size(), ticks + 1)
	var fly: EntityCustomState = run.snapshot().entities.entities[55].custom_state
	var lifecycle_rows: Array = []
	if preset == Org1ExplorationSetup.VISIBILITY_PRESET:
		lifecycle_rows = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/" + name + "_lifecycle.json"))
		assert_eq(lifecycle_rows.size(), ticks)
	var reached_river: bool = false
	var vehicle_death: bool = false
	for tick: int in ticks:
		var command := TickCommand.new()
		command.tick_index = tick
		var stimulus: Variant = commands.get(tick, 0)
		if stimulus is TickCommand:
			var authored: TickCommand = stimulus
			command.pressed_mask = authored.pressed_mask
			command.held_mask = authored.held_mask
			command.start_timer_context = authored.start_timer_context
			command.start_sequence_complete = authored.start_sequence_complete
		else:
			command.pressed_mask = stimulus
			command.held_mask = command.pressed_mask
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
		reached_river = reached_river or result.final_snapshot.attachment.current_entity_index >= 0
		vehicle_death = vehicle_death or (result.final_snapshot.attachment.death_entity_index >= 24 and result.final_snapshot.attachment.death_entity_index <= 47)
		var snapshots: Array[GameplayState] = [result.control_snapshot, result.move_snapshot, result.collision_snapshot, result.camera_snapshot, result.scripts_snapshot, result.final_snapshot]
		for index: int in 6:
			var expected: PackedStringArray = rows[tick * 6 + index + 1]
			for column: int in expected.size():
				expected[column] = expected[column].strip_edges()
			var observed: Dictionary = Org1RouteFacts.phase(snapshots[index], tick, expected[1], scenario.level.entity_collision, result.primitive_contacts)
			for column: int in header.size():
				if str(observed[header[column]]) != expected[column]:
					fail_test("tick %d/%s %s expected %s, observed %s" % [tick, expected[1], header[column], expected[column], observed[header[column]]])
					return
		var canonical: String = "\t".join(field_names) + "\n"
		for visit: EntityUpdateObservation in result.control_snapshot.entities.updates:
			if visit.entity.entity_index == 55:
				fly = visit.entity.custom_state
			var observed: Dictionary = Org1RouteFacts.entity(visit, fly, tick)
			var values := PackedStringArray()
			for field: String in fields:
				values.append(str(observed[field]))
			canonical += "\t".join(values) + "\n"
		if canonical.sha256_text() != digests[tick + 1][1].strip_edges():
			fail_test("tick %d ordered entity updates differ: %s" % [tick, canonical])
			return
		if not lifecycle_rows.is_empty():
			var expected_life: Dictionary = lifecycle_rows[tick]
			var actual_life: EntityRunSnapshot = result.final_snapshot.entities
			var expected_order: Array = expected_life.order
			var expected_groups: Array = expected_life.groups
			assert_eq(actual_life.live_order, PackedInt32Array(expected_order), "live order at %d" % tick)
			assert_eq(actual_life.selected_groups, PackedInt32Array(expected_groups), "groups at %d" % tick)
			var baby: EntityCustomState = actual_life.entities[53].custom_state
			assert_eq(baby.mode, _number(expected_life.baby_mode))
			assert_eq(baby.search_count, _number(expected_life.baby_search))
			assert_eq(baby.parent_entity_index, _number(expected_life.baby_parent))
			assert_eq(baby.carrier_index, _number(expected_life.baby_carrier))
			assert_eq(baby.carried_jump_ticks, _number(expected_life.baby_jump))
			assert_eq(int(baby.dead), _number(expected_life.baby_dead))
			assert_eq(int(baby.model_hidden), _number(expected_life.baby_hidden))
			var baby_matrix: Array = expected_life.baby_matrix
			assert_eq(actual_life.entities[53].matrix12, PackedInt32Array(baby_matrix))
			for slot: int in 64:
				var pose: EntitySnapshot = actual_life.entities[slot]
				var expected_pose: Array = expected_life.entities[slot]
				assert_eq(int(pose.live), _number(expected_pose[0]))
				assert_eq(int(pose.destroy_pending), _number(expected_pose[1]))
				assert_eq(pose.generation, _number(expected_pose[2]))
				if pose.live:
					assert_eq(pose.script_state.timer if pose.script_state != null else 0, _number(expected_pose[3]))
					assert_eq(pose.animation.cel if pose.animation != null else -1, _number(expected_pose[4]))
		assert_true(worker.submit(command))
		var live_result: TickResult = worker.finish()
		assert_eq(live_result.error, "", "live tick %d" % tick)
		if not live_result.error.is_empty():
			return
		assert_null(live_result.control_snapshot)
		assert_true(live_result.final_snapshot.entities.updates.is_empty())
		result.final_snapshot.entities.updates.clear()
		result.control_snapshot = null
		result.move_snapshot = null
		result.collision_snapshot = null
		result.camera_snapshot = null
		result.scripts_snapshot = null
		if JSON.stringify(TerrainTrace.facts(live_result, true)) != JSON.stringify(TerrainTrace.facts(result, true)):
			fail_test("tick %d live execution differs from the source-verified diagnostic run" % tick)
			return
	assert_eq(run.snapshot().tick_index, ticks)
	if preset == Org1ExplorationSetup.ROAD_PRESET:
		if name == "org1_road_river":
			assert_true(reached_river, "The crossing reaches a river platform")
			assert_false(vehicle_death)
		else:
			assert_true(vehicle_death, "The intentional contact reaches a traffic primitive death")

func _number(value: Variant) -> int:
	var number: float = value
	return int(number)
