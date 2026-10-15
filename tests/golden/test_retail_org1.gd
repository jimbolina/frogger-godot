extends RetailTest
## Full admitted ORG1 phases and ordered visits against independent source facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _scenario() -> TerrainScenario:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.entity_reactions = true
	scenario.platforms_enabled = true
	scenario.exploration_preset = Org1ExplorationSetup.PRESET
	scenario.error = scenario.attach_data(_data, "ORG1")
	return scenario

func test_round_trip_and_complete_dive_cycles_match_source() -> void:
	_route("org1_round_trip", 730, {0: 1, 12: 1, 34: 4, 46: 4})

func test_attached_diver_drowns_before_control_matches_source() -> void:
	_route("org1_attached_diver", 1255, {1230: 1})

func test_admission_dependencies_and_complete_reset() -> void:
	var scenario: TerrainScenario = _scenario()
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	assert_eq(scenario.commands.size(), 0)
	assert_eq(scenario.level.entity_collision.entities.size(), 64)
	assert_eq(scenario.level.exploration_guard.world_bounds, Rect2i(-512, -128, 1024, 608))
	var form: FormBookEntry = _data.tables.theme_book().get_form(5, 3)
	var old_radius: int = form.radius_squared
	form.radius_squared += 1
	var rejected: TerrainScenario = _scenario()
	form.radius_squared = old_radius
	assert_string_contains(rejected.error, "proof inputs changed")
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.SOUTH
	command.held_mask = command.pressed_mask
	assert_string_contains(run.step(command).error, "boundary")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)
	for tick: int in 65:
		command = TickCommand.new()
		command.tick_index = tick
		assert_eq(run.step(command).error, "")
	assert_ne(run.snapshot().entity_environment.covered, 0)
	assert_eq(run.reset(scenario.initial), "")
	assert_true(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)) == initial, "Every reset field matches the selected inspection start")
	scenario.initial.powerup_flags = 1
	assert_string_contains(TerrainRun.create(scenario.level, scenario.initial).error, "unpowered")
	scenario.initial.powerup_flags = 0
	scenario.level.exploration_guard = null
	assert_string_contains(TerrainRun.create(scenario.level, scenario.initial).error, "admission")

func _route(name: String, ticks: int, commands: Dictionary) -> void:
	var scenario: TerrainScenario = _scenario()
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
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
	var fly: EntityBackgroundState = run.snapshot().entities.entities[55].background
	for tick: int in ticks:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = commands.get(tick, 0)
		command.held_mask = command.pressed_mask
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
		var snapshots: Array[RunSnapshot] = [result.control_snapshot, result.move_snapshot, result.collision_snapshot, result.camera_snapshot, result.scripts_snapshot, result.final_snapshot]
		for index: int in 6:
			var expected: PackedStringArray = rows[tick * 6 + index + 1]
			for column: int in expected.size():
				expected[column] = expected[column].strip_edges()
			var observed: Dictionary = Org1RouteFacts.phase(snapshots[index], tick, expected[1], scenario.level.entity_collision)
			for column: int in header.size():
				if str(observed[header[column]]) != expected[column]:
					fail_test("tick %d/%s %s expected %s, observed %s" % [tick, expected[1], header[column], expected[column], observed[header[column]]])
					return
		var canonical: String = "\t".join(field_names) + "\n"
		for visit: EntityUpdateObservation in result.control_snapshot.entities.updates:
			if visit.entity.entity_index == 55:
				fly = visit.entity.background
			var observed: Dictionary = Org1RouteFacts.entity(visit, fly, tick)
			var values := PackedStringArray()
			for field: String in fields:
				values.append(str(observed[field]))
			canonical += "\t".join(values) + "\n"
		if canonical.sha256_text() != digests[tick + 1][1].strip_edges():
			fail_test("tick %d ordered entity updates differ: %s" % [tick, canonical])
			return
	assert_eq(run.snapshot().tick_index, ticks)
