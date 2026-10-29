extends RetailTest
## Every named sandbox preset applies fully with player data and its entities run together.

var _data: GameData
var _templates: SandboxEntityTemplates

func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	_templates = SandboxEntityTemplates.from_data(_data, assets.model, assets.action_lengths)

func after_all() -> void:
	if _data != null:
		_data.close()

func _run(spawner: SandboxSpawner, start: Vector2i, label: String) -> void:
	var level: LevelDefinition = spawner.level_definition()
	assert_eq(level.entity_collision.validate(), "", label)
	var run: GameplayRun = GameplayRun.create(level, SandboxSpawner.run_start(start, SandboxLevel.SPAWN_DIRECTION))
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

func test_every_preset_applies_fully_and_runs_30_ticks() -> void:
	assert_eq(_templates.error, "")
	for layout: SandboxPresets.Layout in SandboxPresets.all():
		var spawner := SandboxSpawner.new(SandboxLevel.build(), _templates)
		var outcome: SandboxPresets.Outcome = SandboxPresets.apply(spawner, layout, true)
		assert_eq(outcome.skipped, PackedStringArray(), outcome.summary())
		assert_eq(outcome.placed.size(), layout.entries.size(), layout.name)
		for index: int in outcome.placed.size():
			var entry: SandboxPresets.Entry = layout.entries[index]
			var placement: SandboxSpawner.Placement = outcome.placed[index]
			assert_eq(placement.entity_name, entry.entity_name, layout.name)
			assert_false(placement.level_code.is_empty(), entry.label())
			if not entry.form_name.is_empty():
				assert_eq(placement.form_name, entry.form_name, layout.name)
		_run(spawner, layout.start_cell, layout.name)

func test_sandbox_screen_loads_and_adds_presets_with_models() -> void:
	var screen := SandboxScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	assert_eq(screen.open_sandbox(_data), "")
	assert_eq(screen.load_preset("river"), "")
	assert_eq(screen.last_preset.skipped, PackedStringArray(), screen.notice)
	var river: int = SandboxPresets.named("river").entries.size()
	assert_eq(screen.spawner.placements.size(), river)
	assert_eq(screen.run.snapshot().frog.cell, SandboxPresets.named("river").start_cell)
	assert_eq(screen.entity_model_count(), river, " ".join(screen.entity_model_diagnostics))
	assert_eq(screen.load_preset("enemy lane", false), "")
	assert_eq(screen.spawner.placements.size(), river + SandboxPresets.named("enemy lane").entries.size())
	for tick: int in 30:
		var command := TickCommand.new()
		command.tick_index = screen.run.snapshot().tick_index
		assert_eq(screen.step_command(command, false).error, "", str(tick))
		screen.draw_state(0.5)
	screen.close_data()
