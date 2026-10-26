extends GutTest
## Invented entity reaction inputs against independent Python and frozen C facts.

const FIXTURE: String = "res://tests/golden/fixtures/entity_reactions.json"
const GOLDEN: String = "res://tests/golden/synthetic/entity_reactions.tsv"

func test_synthetic_entity_reactions_match_independent_facts() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var cases: Array = parsed["cases"]
	var lines: PackedStringArray = FileAccess.get_file_as_string(GOLDEN).strip_edges().split("\n")
	assert_eq(lines.size(), cases.size() + 1)
	if lines.size() != cases.size() + 1:
		return
	for index: int in cases.size():
		var raw: Dictionary = cases[index]
		var name: String = str(raw["name"])
		var fields: PackedStringArray = lines[index + 1].trim_suffix("\r").split("\t")
		assert_eq(fields[0], name)
		var scenario: TerrainScenario = TerrainScenario.from_object(raw)
		assert_eq(scenario.error, "", name)
		if not scenario.error.is_empty():
			continue
		assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "", name)
		var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
		assert_eq(run.error, "", name)
		if not run.error.is_empty():
			continue
		var result: TickResult = run.step(scenario.command_at(0))
		assert_eq(result.error, "", name)
		if not result.error.is_empty():
			continue
		var observed_contacts := PackedStringArray()
		var observed_statuses := PackedStringArray()
		for reaction: FormReactionResult in result.entity_contacts:
			if reaction.contact != null and reaction.contact.status == FormContactResult.CONTACT:
				observed_contacts.append(str(reaction.contact.entity_index))
				observed_statuses.append(reaction.status)
		assert_eq(",".join(observed_contacts) if not observed_contacts.is_empty() else "-", fields[11], name + " contacts")
		assert_eq(",".join(observed_statuses) if not observed_statuses.is_empty() else "-", fields[12], name + " statuses")
		var snapshot: GameplayState = result.collision_snapshot
		assert_not_null(snapshot, name)
		if snapshot == null:
			continue
		var observed_hits := PackedStringArray()
		for entity_index: int in snapshot.attachment.entity_hit_indices:
			observed_hits.append(str(entity_index))
		var supported_hits := PackedStringArray()
		var expected_indices: PackedStringArray = fields[11].split(",")
		var expected_statuses: PackedStringArray = fields[12].split(",")
		for contact_index: int in expected_statuses.size():
			if expected_statuses[contact_index] in ["hit", "pop", "squish"]:
				supported_hits.append(expected_indices[contact_index])
		assert_eq(",".join(observed_hits) if not observed_hits.is_empty() else "-",
			",".join(supported_hits) if not supported_hits.is_empty() else "-", name + " bounded hits")
		if not fields[12].contains("unsupported"):
			assert_eq(",".join(observed_hits) if not observed_hits.is_empty() else "-", fields[10], name + " frozen C hits")
		if fields[12] == "unsupported":
			assert_eq(snapshot.attachment.death_entity_index, -1, name + " unsupported killer omitted")
			assert_eq(snapshot.frog.death_equate, 0, name + " unsupported death omitted")
			assert_eq(TickEvent.trace_lines(result.events).count("entity_pop_explosion_request"), 0, name + " unsupported effect omitted")
			assert_eq(snapshot.requests.sound_requests, 0, name + " unsupported sound omitted")
			continue
		assert_eq(snapshot.attachment.death_entity_index, int(fields[13]), name + " first killer")
		assert_eq(snapshot.frog.death_equate, int(fields[3]), name + " death animation")
		assert_eq(snapshot.frog.flags, int(fields[2]), name + " frog flags")
		assert_eq(snapshot.frog.mode, int(fields[1]), name + " frog mode")
		assert_eq(snapshot.frog.velocity_16.x, int(fields[4]), name + " vx")
		assert_eq(snapshot.frog.velocity_16.y, int(fields[5]), name + " vy")
		assert_eq(snapshot.frog.velocity_16.z, int(fields[6]), name + " vz")
		var pop_requests: int = int(fields[8]) if int(fields[3]) == 23 else 0
		var squish_notifications: int = 1 if int(fields[3]) == 2 and int(fields[13]) >= 0 else 0
		assert_eq(TickEvent.trace_lines(result.events).count("entity_pop_explosion_request"), pop_requests, name + " POP request")
		assert_eq(TickEvent.trace_lines(result.events).count("entity_squish"), squish_notifications, name + " SQUISH notification")
		assert_eq(snapshot.requests.sound_requests, int(fields[9]), name + " sound request")
		if snapshot.camera != null:
			assert_eq(snapshot.camera.mode, int(fields[7]), name + " camera mode")
