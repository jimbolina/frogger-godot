extends GutTest
## Independent frozen Sky trigger, PATH_INFO, drift, Game_timer and balloon-script register facts at source widths.

## The imported FrogLord name lists of the retail build.
const NAMES: String = "res://assets/tables/names.tres"
const FACTS: String = "res://tests/golden/synthetic/sky.json"
const SKY_THEME: int = 8
const DRIFT_LABELS: Array[String] = ["sky:drift_x", "sky:drift_z"]

var _cache: Dictionary = {}

func _facts() -> Dictionary:
	if _cache.is_empty():
		_cache = JSON.parse_string(FileAccess.get_file_as_string(FACTS))
	return _cache

func _int(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(values: Variant) -> Array[int]:
	var source: Array = values
	var result: Array[int] = []
	for value: Variant in source:
		result.append(_int(value))
	return result

func _vector(values: Variant) -> Vector3i:
	var items: Array[int] = _ints(values)
	return Vector3i(items[0], items[1], items[2])

func _bytes(values: Variant) -> PackedByteArray:
	return PackedByteArray(_ints(values))

func _book(theme: int, entity_name: String) -> ThemeBook:
	var book := ThemeBook.new()
	for index: int in FroggerIds.THEMES.size():
		var entry := ThemeBookEntry.new()
		entry.theme = index
		book.entries.append(entry)
	var form := FormBookEntry.new()
	form.theme = theme
	form.local_id = 0
	form.form_name = "TEST_" + entity_name
	form.entity_name = entity_name
	book.entries[theme].forms.append(form)
	return book

func _map(theme: int, payload: PackedByteArray, path_segments: int = 0, path_length: int = 0) -> MapFile:
	var map := MapFile.new()
	map.general.theme = theme
	var entity_packet := MapPacket.new()
	entity_packet.identifier = "EMTP"
	map.packets["EMTP"] = entity_packet
	var path_packet := MapPacket.new()
	path_packet.identifier = "PATH"
	map.packets["PATH"] = path_packet
	if path_segments > 0:
		var path := MapPath.new()
		path.path_index = 0
		path.source_offset = 1000
		for index: int in path_segments:
			var segment := MapPathSegment.new()
			segment.segment_type = PathSegmentDefinition.LINE
			segment.length = path_length
			segment.source_offset = path.source_offset + 12 + 40 * index
			segment.start = Vector3i(path_length * index, 0, 0)
			segment.end = Vector3i(path_length * (index + 1), 0, 0)
			path.segments.append(segment)
		path_packet.offsets.append(path.source_offset)
		path_packet.count = 1
		map.paths.append(path)
	var span := MapEntitySpan.new()
	span.source_offset = 100
	span.end_offset = span.source_offset + 24 + payload.size()
	span.form_id = 0
	span.unique_id = 1673
	span.form_grid_id = 0
	span.payload = payload
	entity_packet.offsets.append(span.source_offset)
	entity_packet.count = 1
	map.entities.append(span)
	return map

func _identity() -> PackedInt32Array:
	return PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])

## Decodes a trigger through EntitySetup from an ENTSTR_TRIGGER record holding the authored s16 ids.
func _trigger(trigger_type: int, ids: Array[int]) -> EntityDefinition:
	var payload := PackedByteArray()
	payload.resize(56)
	for axis: int in 3:
		payload.encode_s16((axis * 3 + axis) * 2, 4096)
	payload.encode_u32(32, trigger_type)
	for index: int in ids.size():
		payload.encode_s16(36 + index * 2, ids[index])
	var setup: EntitySetup = EntitySetup.from_map(_map(SKY_THEME, payload), _book(SKY_THEME, "TRIGGER"), "sky.map", 800, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1, "trigger setup")
	return setup.definitions[0] if setup.definitions.size() == 1 else null

func _environment() -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	return environment

## Builds a live target; path targets follow one LINE so the run owns a path runner.
func _target(value: Variant, entity_index: int) -> EntityDefinition:
	var raw: Dictionary = value
	var definition := EntityDefinition.new()
	definition.entity_index = entity_index
	definition.unique_id = _int(raw.unique_id)
	definition.matrix12 = _identity()
	var stopped: bool = raw.stopped
	definition.flags = EntityDefinition.NO_MOVEMENT if stopped else 0
	var has_path: bool = raw.has_path
	if has_path:
		definition.entity_name = "MOVING"
		definition.behavior = EntityBehaviorCatalog.resolve("MOVING")
		definition.path_definition = PathDefinition.new()
		var segment := PathSegmentDefinition.new()
		segment.segment_type = PathSegmentDefinition.LINE
		segment.length = 4096
		segment.end = Vector3i(4096, 0, 0)
		definition.path_definition.segments.append(segment)
		definition.path_start = PathStart.new()
		definition.path_start.distance = 1024
		definition.path_start.speed = 8
		var backwards: bool = raw.backwards
		definition.path_start.flags = PathStart.BACKWARDS if backwards else 0
	else:
		definition.entity_name = "STATIC"
		definition.behavior = EntityBehaviorCatalog.resolve("STATIC")
	return definition

func _run(trigger: EntityDefinition, targets: Variant) -> EntityRun:
	if trigger == null:
		var failed := EntityRun.new()
		failed.error = "trigger setup failed"
		return failed
	var definitions: Array[EntityDefinition] = [trigger]
	var raws: Array = targets
	for raw: Dictionary in raws:
		definitions.append(_target(raw, definitions.size()))
	return EntityRun.create(definitions)

## Reads stopped/active/backwards from a snapshot; active and backwards are null without a path.
func _state_of(entity: EntitySnapshot) -> Dictionary:
	var state: Dictionary = {"unique_id": entity.unique_id, "stopped": bool(entity.entity_flags & EntityDefinition.NO_MOVEMENT), "active": null, "backwards": null}
	if entity.path != null:
		state["active"] = bool(entity.path.flags & PathStart.ACTIVE)
		state["backwards"] = bool(entity.path.flags & PathStart.BACKWARDS)
	return state

func _expected_state(value: Variant) -> Dictionary:
	var raw: Dictionary = value
	return {"unique_id": _int(raw.unique_id), "stopped": raw.stopped, "active": raw.active, "backwards": raw.backwards}

func _check_targets(snapshot: EntityRunSnapshot, value: Variant, label: String) -> void:
	var expected: Array = value
	for index: int in expected.size():
		assert_eq(_state_of(snapshot.entities[index + 1]), _expected_state(expected[index]), "%s target %d" % [label, index])

func test_trigger_payload_match_independent_facts() -> void:
	var fixtures: Array = _facts().trigger_payload
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "trigger payload %d" % index
		var setup: EntitySetup = EntitySetup.from_map(_map(SKY_THEME, _bytes(initial.payload)), _book(SKY_THEME, "TRIGGER"), "sky.map", 800, "pc-retail-v3.0e", true)
		assert_eq(setup.error, "", label)
		if not expected.source_defined:
			assert_true(setup.definitions.is_empty(), label + " is rejected")
			assert_eq(setup.diagnostics.size(), 1, label)
			if not setup.diagnostics.is_empty():
				assert_eq(setup.diagnostics[0].code, "invalid_payload", label)
			continue
		assert_eq(setup.definitions.size(), 1, label)
		if setup.definitions.size() != 1:
			continue
		var definition: EntityDefinition = setup.definitions[0]
		assert_eq(definition.behavior.kind, EntityBehavior.Kind.TRIGGER, label)
		assert_eq(definition.trigger.trigger_type, _int(expected.type), label + " type")
		assert_eq(definition.trigger.target_ids, PackedInt32Array(_ints(expected.ids)), label + " ids")
		assert_eq(definition.matrix12.slice(9, 12), PackedInt32Array(_ints(expected.translation)), label + " translation")

func test_trigger_first_update_match_independent_facts() -> void:
	var fixtures: Array = _facts().trigger_first_update
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "trigger first update %d" % index
		var run: EntityRun = _run(_trigger(EntityTrigger.Type.BEGIN, _ints(initial.ids)), initial.targets)
		assert_eq(run.error, "", label)
		if not run.error.is_empty():
			continue
		var environment: EntityEnvironmentState = _environment()
		var random: SourceRandom = SourceRandom.create(1)
		assert_eq(run.update_custom(0, environment, random, Vector3i.ZERO, false).error, "", label)
		_check_targets(run.snapshot(), expected.targets, label)
		var expected_skips: Array[int] = _ints(expected.skipped)
		for skipped: int in expected_skips:
			for slot: int in range(1, run.snapshot().entities.size()):
				assert_ne(run.snapshot().entities[slot].unique_id, skipped, label + " skipped id is absent")
		var resumes: Array[EntityTargetEffect] = []
		for slot: int in range(1, run.snapshot().entities.size()):
			resumes.append(EntityTargetEffect.create(run.snapshot().entities[slot].unique_id, EntityTargetEffect.Kind.RESUME))
		assert_eq(run.apply_target_effects(resumes), "", label + " resumes every target before the second update")
		var before_second: Array[Dictionary] = []
		for slot: int in range(1, run.snapshot().entities.size()):
			before_second.append(_state_of(run.snapshot().entities[slot]))
		assert_eq(run.update_custom(0, environment, random, Vector3i.ZERO, false).error, "", label)
		var unchanged: bool = expected.second_update_unchanged
		for slot: int in range(1, run.snapshot().entities.size()):
			assert_eq(_state_of(run.snapshot().entities[slot]) == before_second[slot - 1], unchanged, label + " second update")
		assert_eq(random.draw_count, 0, label)

func test_trigger_callback_match_independent_facts() -> void:
	var kind: FormCallback.Kind = FormCallbackCatalog.KINDS["TriggerEntityCallback"]
	assert_eq(kind, FormCallback.Kind.TRIGGER)
	var fixtures: Array = _facts().trigger_callback
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "trigger callback %d type %d" % [index, _int(initial.type)]
		var frog := Frog.new()
		frog.candidate_entities = _run(_trigger(_int(initial.type), _ints(initial.ids)), initial.targets)
		assert_eq(frog.candidate_entities.error, "", label)
		if not frog.candidate_entities.error.is_empty():
			continue
		var state := GameplayState.new()
		state.frog.flags = FrogFlags.ACTIVE
		var events: Array[TickEvent] = []
		var issue: String = FormCallback.apply(kind, frog, state, 0, events)
		if not expected.source_defined:
			assert_ne(issue, "", label + " leaves source-defined storage (%s)" % str(expected.reason))
			continue
		assert_eq(issue, "", label)
		if not issue.is_empty() or state.entities == null:
			continue
		_check_targets(state.entities, expected.targets, label)
		var forbid: bool = expected.forbid
		var jumped: bool = expected.jump_from_collprim
		assert_eq(state.attachment.forbidden_entity_index == 0, forbid, label + " forbid")
		assert_eq(bool(state.frog.flags & FrogFlags.JUMP_FROM_COLLPRIM), jumped, label + " jump from collprim")
		assert_true(events.is_empty(), label)

func test_platform_payload_match_independent_facts() -> void:
	var family: Dictionary = _facts().platform_payload
	var path: Dictionary = family.path
	var segments: int = _int(path.segments)
	var length: int = _int(path.length)
	var fixtures: Array = family.cases
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var theme: int = _int(initial.theme)
		var label: String = "platform payload %d theme %d" % [index, theme]
		var setup: EntitySetup = EntitySetup.from_map(_map(theme, _bytes(initial.payload), segments, length), _book(theme, "MOVING_PLATFORM"), "sky.map", 800, "pc-retail-v3.0e", true)
		assert_eq(setup.error, "", label)
		if not expected.source_defined:
			assert_true(setup.definitions.is_empty(), label + " is rejected")
			continue
		assert_eq(setup.definitions.size(), 1, label)
		for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
			assert_eq(diagnostic.code, "", "%s %s" % [label, diagnostic.message])
		if setup.definitions.size() != 1:
			continue
		var definition: EntityDefinition = setup.definitions[0]
		assert_eq(definition.behavior.kind, EntityBehavior.Kind.MOVING_PLATFORM, label)
		assert_eq(definition.path_definition.path_index, _int(expected.path_id), label + " path")
		assert_eq([definition.path_start.segment_index, definition.path_start.distance, definition.path_start.flags & 14, definition.path_start.speed],
			[_int(expected.segment_id), _int(expected.segment_dist), _int(expected.motion_type), _int(expected.speed)], label + " PATH_INFO")
		assert_eq(definition.volcano.initial_movement, _int(expected.initial_movement), label + " initial movement")
		var chain: bool = expected.chain_sound
		assert_eq(definition.volcano.play_chain_sound, chain, label + " chain sound")

func test_sky_drift_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().sky_drift_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "drift %s" % str(initial.name)
		var drift := SkyDriftState.new()
		drift.position = _vector(initial.get("position", [0, 0, 0]))
		drift.velocity = _vector(initial.get("velocity", [0, 0, 0]))
		drift.acceleration = _vector(initial.get("acceleration", [0, 0, 0]))
		var random: SourceRandom = SourceRandom.create(_int(initial.seed))
		var rows: Array = expected.rows
		for row: Dictionary in rows:
			var at: String = "%s tick %d" % [label, _int(row.tick)]
			var cleared: bool = row.cleared
			if cleared:
				drift.clear()
			var before: int = random.draw_count
			random.begin_tick()
			drift.step(_int(row.game_timer), random)
			var draws: int = _int(row.draws)
			assert_eq(random.draw_count - before, draws, at + " draws")
			var labels: Array[String] = []
			if draws == 2:
				labels = DRIFT_LABELS
			assert_eq(random.consumers, labels, at + " consumers")
			assert_eq([drift.acceleration, drift.velocity, drift.position, drift.translation()],
				[_vector(row.acceleration), _vector(row.velocity), _vector(row.position), _vector(row.translation)], at)
		assert_eq(random.state, _int(expected.rng_state), label + " rng state")
		assert_eq(random.draw_count, _int(expected.draw_count), label + " draw count")

func _sky_level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.flow_enabled = true
	level.level_time = 900
	level.theme = SKY_THEME
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i.ONE
	var stack := GridStackDefinition.new()
	stack.square_count = 1
	level.grid.stacks.append(stack)
	var square := GridSquareDefinition.new()
	square.flags = 3
	square.vertices.assign([Vector3i(0, 0, 256), Vector3i(256, 0, 256), Vector3i.ZERO, Vector3i(256, 0, 0)])
	level.grid.squares.append(square)
	return level

## Drives single-start runs or level-play runs; a play frame of n logic ticks is the post-LevelStart
## catch-up frame, modelled by holding the timer for its first n-1 ticks.
func test_game_timer_cadence_match_independent_facts() -> void:
	var fixtures: Array = _facts().game_timer_cadence
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var initial_facts: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "cadence %d" % index
		var frames: Array = initial_facts.frames
		var first: Dictionary = frames[0]
		var mode: String = first.mode
		for frame: Dictionary in frames:
			assert_eq(str(frame.mode), mode, label + " drives one mainloop mode")
		assert_true(mode in ["single_start", "play"], label + " mode is drivable")
		var initial := RunStart.new()
		initial.game_timer = _int(initial_facts.game_timer_start)
		if mode == "single_start":
			initial.start_mode = RunStart.Mode.SINGLE_START
			initial.start_timer = 120
		var run: GameplayRun = GameplayRun.create(_sky_level(), initial)
		assert_eq(run.error, "", label)
		if not run.error.is_empty():
			continue
		var per_frame: Array = expected.per_frame
		for frame_index: int in frames.size():
			var frame: Dictionary = frames[frame_index]
			var ticks: int = _int(frame.logic_ticks)
			if ticks > 1:
				run._state.frog.start_timer_hold = ticks - 1
			var seen: Array[int] = _ints(per_frame[frame_index])
			assert_eq(seen.size(), ticks, label)
			for tick: int in ticks:
				assert_eq(run.snapshot().game_timer, seen[tick], "%s frame %d tick %d" % [label, frame_index, tick])
				var command := TickCommand.new()
				command.tick_index = run.snapshot().tick_index
				var result: TickResult = run.step(command)
				assert_eq(result.error, "", label)
				if not result.error.is_empty():
					return
		assert_eq(run.snapshot().game_timer, _int(expected.final_game_timer), label + " final")

func _names() -> NameBank:
	var names: GameNameLists = load(NAMES) as GameNameLists
	assert_not_null(names)
	return names.scripts if names != null else null

## Builds a supplied-table stand-in holding the frozen-source programs under their FrogLord ids.
func _table(bank: NameBank, programs: Dictionary) -> ScriptTable:
	var table := ScriptTable.new()
	var highest: int = 0
	for key: String in programs:
		highest = maxi(highest, key.to_int())
	for id: int in range(highest + 1):
		var program := EntityScript.new()
		program.id = id
		program.name = bank.name_of(id)
		var words: Array[int] = [38]
		if programs.has(str(id)):
			words = _ints(programs[str(id)])
		var cursor: int = 0
		while cursor < words.size():
			var command := EntityScript.Command.new()
			command.opcode = words[cursor]
			var width: int = EntityScriptDefinition.WIDTHS[command.opcode]
			command.arguments = PackedInt32Array(words.slice(cursor + 1, cursor + width))
			program.commands.append(command)
			cursor += width
		table.scripts.append(program)
	return table

func test_sky_script_registers_match_independent_facts() -> void:
	var bank: NameBank = _names()
	if bank == null:
		return
	var family: Dictionary = _facts().sky_script_registers
	var programs: Dictionary = family.programs
	var table: ScriptTable = _table(bank, programs)
	var setups: Array = family.setup
	for fixture: Dictionary in setups:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "%s registers" % str(initial.name)
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(str(initial.entity))
		assert_eq(behavior.layout, EntityBehavior.Layout.MATRIX, label)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, _int(initial.root), behavior, _bytes(initial.payload))
		if not expected.source_defined:
			assert_ne(setup.error, "", label + " reads outside the entity data")
			continue
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		assert_eq(setup.definition.payload_offset, 32, label + " offset")
		assert_eq(setup.definition.payload_registers.size(), _int(expected.count), label + " count")
		assert_eq(setup.definition.payload_registers, PackedInt32Array(_ints(expected.registers)), label + " values")
