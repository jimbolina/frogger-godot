extends GutTest
## Data-free sandbox presets: layout shape, graceful skips, valid rebuilds and replace versus append.

func _spawner() -> SandboxSpawner:
	return SandboxSpawner.new(SandboxLevel.build())

func _assert_runs(spawner: SandboxSpawner, label: String) -> void:
	var level: LevelDefinition = spawner.level_definition()
	assert_eq(level.entity_collision.validate(), "", label)
	assert_eq(level.entity_collision.entities.size(), spawner.placements.size(), label)
	var run: GameplayRun = GameplayRun.create(level, SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION))
	assert_eq(run.error, "", label)
	if not run.error.is_empty():
		return
	for tick: int in 30:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "%s tick %d" % [label, tick])
		if not result.error.is_empty():
			return

func test_layouts_have_unique_names_entries_and_cells_inside_the_arena() -> void:
	var sandbox: SandboxLevel = SandboxLevel.build()
	var layouts: Array[SandboxPresets.Layout] = SandboxPresets.all()
	assert_eq(SandboxPresets.names(), PackedStringArray(["river", "ice slide", "platform gauntlet", "enemy lane", "zone tour", "desert hazards", "jungle hazards"]))
	for layout: SandboxPresets.Layout in layouts:
		assert_false(layout.entries.is_empty(), layout.name)
		assert_false(layout.description.is_empty(), layout.name)
		assert_true(sandbox.flags_at(layout.start_cell) & GridSquareFlags.SAFE != 0, layout.name)
		assert_true(SandboxPresets.named(layout.name) != null, layout.name)
		for entry: SandboxPresets.Entry in layout.entries:
			assert_true(sandbox.flags_at(entry.cell) >= 0, "%s %s" % [layout.name, entry.label()])
			assert_ne(EntityBehaviorCatalog.resolve(entry.entity_name).kind, EntityBehavior.Kind.UNKNOWN, entry.entity_name)
	assert_null(SandboxPresets.named("missing"))

func test_zone_tour_places_an_entity_in_every_terrain_zone() -> void:
	var sandbox: SandboxLevel = SandboxLevel.build()
	var covered: Dictionary[StringName, bool] = {}
	for entry: SandboxPresets.Entry in SandboxPresets.named("zone tour").entries:
		covered[sandbox.zone_at(entry.cell).name] = true
	for zone: SandboxLevel.Zone in sandbox.zones:
		if zone.name != &"plain":
			assert_true(covered.has(zone.name), String(zone.name))

func test_every_preset_applies_on_a_data_free_spawner_and_reports_skips() -> void:
	for layout: SandboxPresets.Layout in SandboxPresets.all():
		var spawner: SandboxSpawner = _spawner()
		var outcome: SandboxPresets.Outcome = SandboxPresets.apply(spawner, layout, true)
		assert_eq(outcome.layout_name, layout.name)
		assert_eq(outcome.placed.size() + outcome.skipped.size(), layout.entries.size(), layout.name)
		assert_eq(spawner.placements.size(), outcome.placed.size(), layout.name)
		var skipped_index: int = 0
		for entry: SandboxPresets.Entry in layout.entries:
			var allowed: SandboxSpawner.Availability = spawner.availability(entry.entity_name)
			if allowed.available:
				continue
			assert_string_contains(outcome.skipped[skipped_index], entry.label(), layout.name)
			assert_string_contains(outcome.skipped[skipped_index], allowed.reason, layout.name)
			skipped_index += 1
		assert_eq(skipped_index, outcome.skipped.size(), layout.name)
		if not outcome.skipped.is_empty():
			assert_string_contains(outcome.summary(), "skipped", layout.name)
		_assert_runs(spawner, layout.name)
	var river: SandboxPresets.Outcome = SandboxPresets.apply(_spawner(), SandboxPresets.named("river"), true)
	assert_eq(river.placed.size(), 2)
	assert_string_contains(river.summary(), "SUB_TURTLE at (3, 7)")
	assert_string_contains(river.summary(), "player data")

func test_loading_replaces_and_adding_appends() -> void:
	var spawner: SandboxSpawner = _spawner()
	assert_eq(spawner.add("STATIC", Vector2i(28, 28)).error, "")
	var ice: SandboxPresets.Outcome = SandboxPresets.apply(spawner, SandboxPresets.named("ice slide"), true)
	assert_eq(spawner.placements.size(), ice.placed.size())
	assert_false(spawner.placements.any(func(placement: SandboxSpawner.Placement) -> bool: return placement.cell == Vector2i(28, 28)))
	var lane: SandboxPresets.Outcome = SandboxPresets.apply(spawner, SandboxPresets.named("enemy lane"), false)
	assert_eq(spawner.placements.size(), ice.placed.size() + lane.placed.size())
	for index: int in ice.placed.size():
		assert_eq(spawner.placements[index], ice.placed[index])
	_assert_runs(spawner, "ice slide plus enemy lane")
	SandboxPresets.apply(spawner, SandboxPresets.named("river"), true)
	assert_eq(spawner.placements.size(), 2)

func test_new_layouts_extend_with_one_entry_and_bad_input_is_reported() -> void:
	var layout := SandboxPresets.Layout.new("custom", "One added mechanic", Vector2i(16, 2))
	assert_eq(layout.add("MOVING", Vector2i(16, 4), SandboxSpawner.Preset.LOOP, 24), layout)
	layout.add("NOT_A_KIND", Vector2i(16, 6)).add("STATIC", Vector2i(40, 6))
	var spawner: SandboxSpawner = _spawner()
	var outcome: SandboxPresets.Outcome = SandboxPresets.apply(spawner, layout, true)
	assert_eq(outcome.placed.size(), 1)
	assert_eq(outcome.placed[0].speed, 24)
	assert_eq(outcome.skipped.size(), 2)
	assert_string_contains(outcome.skipped[0], "Unknown")
	assert_string_contains(outcome.skipped[1], "outside")
	_assert_runs(spawner, "custom")
	assert_eq(SandboxPresets.apply(spawner, null, true).skipped, PackedStringArray(["No such preset"]))
	assert_eq(SandboxPresets.apply(null, layout, true).skipped, PackedStringArray(["The sandbox is not open"]))
	assert_eq(spawner.placements.size(), 1)
