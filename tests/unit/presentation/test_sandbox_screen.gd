extends GutTest
## Asset-free sandbox scene: arena drawing, palette availability and the actions behind its buttons and hotkeys.

var _screen: SandboxScreen

func before_each() -> void:
	_screen = SandboxScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)
	assert_eq(_screen.open_sandbox(null), "")

func _step(pressed: int = 0) -> TickResult:
	var command := TickCommand.new()
	command.tick_index = _screen.run.snapshot().tick_index
	command.pressed_mask = pressed
	command.held_mask = pressed
	return _screen.step_command(command, false)

func test_screen_builds_the_arena_palette_and_a_component_run() -> void:
	assert_eq(_screen.last_error, "")
	assert_true(_screen.playing)
	assert_eq(_screen.level_code, SandboxScreen.LEVEL_CODE)
	assert_null(_screen.templates)
	assert_string_contains(_screen.data_status, "placeholders")
	assert_not_null(_screen.palette)
	assert_true(_screen._frog.visible)
	var state: GameplayState = _screen.run.snapshot()
	assert_eq(state.frog.cell, SandboxLevel.SPAWN_CELL)
	assert_eq(state.flow.phase, LevelFlowState.Phase.PLAY)
	assert_eq(state.camera.source_offset, SandboxLevel.DEFAULT_CAMERA_OFFSET)
	var names: Dictionary[String, bool] = {}
	for child: Node in _screen._ground.get_children():
		names[String(child.name)] = true
	for zone: SandboxLevel.Zone in _screen.sandbox.zones:
		assert_true(names.has("%s_0" % zone.name) or names.has("%s_1" % zone.name), String(zone.name))
	assert_eq(_screen.palette.legend.get_child_count(), _screen.sandbox.zones.size() * 2)
	assert_eq(_screen.palette.zones.item_count, _screen.sandbox.zones.size())
	for tick: int in 5:
		assert_eq(_step().error, "", str(tick))
		_screen.draw_state(0.5)

func test_palette_disables_unavailable_kinds_with_their_reasons() -> void:
	var palette: SandboxPalette = _screen.palette
	assert_eq(palette.kinds.item_count, SandboxSpawner.kind_names().size())
	for entity_name: String in SandboxSpawner.kind_names():
		var allowed: SandboxSpawner.Availability = _screen.spawner.availability(entity_name)
		assert_eq(palette.is_kind_disabled(entity_name), not allowed.available, entity_name)
		if not allowed.available:
			assert_eq(palette.kind_tooltip(entity_name), allowed.reason, entity_name)
	assert_true(palette.is_kind_disabled("SUB_TURTLE"))
	assert_string_contains(palette.kind_tooltip("SUB_TURTLE"), "player data")
	assert_true(palette.is_kind_disabled("ORG_BABY_FROG"))
	assert_string_contains(palette.kind_tooltip("ORG_BABY_FROG"), "parent log")
	assert_false(palette.select_kind("SUB_TURTLE"))
	assert_false(palette.selected_kind().is_empty())
	assert_false(palette.is_kind_disabled(palette.selected_kind()))
	assert_true(palette.select_kind("MOVING"))
	assert_eq(palette.selected_form(), "")
	assert_true(palette.forms.disabled)
	for step: int in palette.kinds.item_count:
		palette.cycle_kind(1)
		assert_false(palette.is_kind_disabled(palette.selected_kind()), str(step))

func test_place_remove_and_clear_follow_the_palette_and_keep_the_frog() -> void:
	assert_eq(_screen.teleport_to_cell(Vector2i(10, 20)), "")
	var palette: SandboxPalette = _screen.palette
	assert_true(palette.select_kind("MOVING"))
	palette.select_preset(SandboxSpawner.Preset.LINE)
	assert_eq(_screen.place_at_frog(), "")
	assert_eq(_screen.spawner.placements.size(), 1)
	assert_eq(_screen.spawner.placements[0].cell, Vector2i(10, 20))
	assert_eq(_screen.spawner.placements[0].preset, SandboxSpawner.Preset.LINE)
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(10, 20))
	assert_eq(_screen.placeholder_count(), 1)
	assert_true(palette.select_kind("STATIC"))
	palette.select_preset(SandboxSpawner.Preset.STATIC)
	assert_eq(_screen.place_ahead(), "")
	assert_eq(_screen.spawner.placements[1].cell, Vector2i(10, 21))
	assert_eq(_screen.placeholder_count(), 2)
	assert_eq(_screen.run.snapshot().entities.entities.size(), 2)
	assert_eq(_screen.remove_last(), "")
	assert_eq(_screen.spawner.placements.size(), 1)
	assert_eq(_screen.remove_at_frog(), "")
	assert_eq(_screen.spawner.placements.size(), 0)
	assert_ne(_screen.remove_at_frog(), "")
	assert_ne(_screen.remove_last(), "")
	assert_eq(_screen.place("STATIC", Vector2i(4, 4)), "")
	assert_eq(_screen.place("DYNAMIC", Vector2i(5, 4)), "")
	assert_eq(_screen.clear_entities(), "")
	assert_eq(_screen.spawner.placements.size(), 0)
	assert_eq(_screen.placeholder_count(), 0)
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(10, 20))
	for tick: int in 5:
		assert_eq(_step().error, "", str(tick))

func test_unavailable_or_invalid_placements_report_errors_without_changing_the_run() -> void:
	var before: GameplayRun = _screen.run
	assert_string_contains(_screen.place("SUB_TURTLE", Vector2i(4, 4)), "player data")
	assert_string_contains(_screen.notice, "player data")
	assert_ne(_screen.place("STATIC", Vector2i(4, 4), SandboxSpawner.Preset.LINE), "")
	assert_ne(_screen.place("STATIC", Vector2i(40, 4)), "")
	assert_true(_screen.run == before)
	assert_eq(_screen.spawner.placements.size(), 0)
	assert_eq(_screen.last_error, "")

func test_teleport_to_cells_and_zones() -> void:
	assert_eq(_screen.teleport_to_cell(Vector2i(20, 25)), "")
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(20, 25))
	assert_ne(_screen.teleport_to_cell(Vector2i(32, 0)), "")
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(20, 25))
	assert_eq(_screen.zone_target(&"water"), Vector2i(6, 5))
	assert_eq(_screen.teleport_to_zone(&"water"), "")
	var state: GameplayState = _screen.run.snapshot()
	assert_eq(state.frog.cell, Vector2i(6, 5))
	assert_eq(state.frog.direction, SandboxLevel.SPAWN_DIRECTION)
	var camera: Rect2i = _screen.sandbox.zone_named(&"camera").cells
	assert_eq(_screen.teleport_to_zone(&"camera"), "")
	assert_true(camera.has_point(_screen.run.snapshot().frog.cell))
	assert_eq(_screen.zone_target(&"plain"), SandboxLevel.SPAWN_CELL)
	for zone: SandboxLevel.Zone in _screen.sandbox.zones:
		var target: Vector2i = _screen.zone_target(zone.name)
		assert_true(_screen.sandbox.flags_at(target) & GridSquareFlags.SAFE != 0, String(zone.name))
	assert_ne(_screen.teleport_to_zone(&"missing"), "")
	_screen.palette.select_cell(Vector2i(3, 3))
	assert_eq(_screen.palette.selected_cell(), Vector2i(3, 3))
	assert_true(_screen.palette.select_zone(&"ice"))
	assert_eq(_screen.palette.selected_zone(), &"ice")

func test_reset_and_restart_keep_placements_and_refill_lives_and_time() -> void:
	assert_eq(_screen.place("STATIC", Vector2i(4, 4)), "")
	assert_eq(_screen.teleport_to_cell(Vector2i(12, 20)), "")
	for tick: int in 30:
		assert_eq(_step().error, "", str(tick))
	assert_lt(_screen.run.snapshot().flow.remaining_time, SandboxLevel.LEVEL_TIME)
	assert_eq(_screen.reset_frog(), "")
	var state: GameplayState = _screen.run.snapshot()
	assert_eq(state.frog.cell, SandboxLevel.SPAWN_CELL)
	assert_eq(state.flow.remaining_time, SandboxLevel.LEVEL_TIME)
	assert_eq(_screen.teleport_to_cell(Vector2i(12, 20)), "")
	assert_eq(_screen.restart(), "")
	state = _screen.run.snapshot()
	assert_eq(state.frog.cell, SandboxLevel.SPAWN_CELL)
	assert_eq(state.frog.lives, 3)
	assert_eq(state.flow.phase, LevelFlowState.Phase.PLAY)
	assert_eq(state.flow.remaining_time, SandboxLevel.LEVEL_TIME)
	assert_eq(_screen.spawner.placements.size(), 1)
	assert_eq(state.entities.entities.size(), 1)

func test_losing_every_life_restarts_the_sandbox() -> void:
	assert_eq(_screen.place("STATIC", Vector2i(4, 4)), "")
	assert_eq(_screen.teleport_to_zone(&"water"), "")
	var lowest_lives: int = 3
	var restarted: bool = false
	for tick: int in 3000:
		var result: TickResult = _step(TickCommand.NORTH if tick % 10 == 0 else 0)
		assert_eq(result.error, "", str(tick))
		if not result.error.is_empty():
			return
		assert_false(_screen._current.completed, str(tick))
		lowest_lives = mini(lowest_lives, result.final_snapshot.frog.lives)
		if _screen.notice.contains("restarted"):
			restarted = true
			break
	assert_true(restarted)
	assert_lt(lowest_lives, 3)
	assert_true(_screen.playing)
	assert_eq(_screen.run.snapshot().frog.cell, SandboxLevel.SPAWN_CELL)
	assert_eq(_screen.run.snapshot().frog.lives, 3)
	assert_eq(_screen.spawner.placements.size(), 1)

func test_completing_the_run_restarts_without_the_level_complete_page() -> void:
	var finished: GameplayState = _screen.run.snapshot()
	finished.completed = true
	finished.flow.phase = LevelFlowState.Phase.COMPLETE
	var result := TickResult.new()
	result.final_snapshot = finished
	_screen._accept(result)
	assert_null(_screen._complete_page, "the sandbox never opens the page")
	assert_true(_screen._hud.visible)
	_screen._keep_alive()
	assert_true(_screen.notice.contains("completed"))
	assert_true(_screen.playing)

func test_a_game_over_restarts_without_the_game_over_page() -> void:
	var over: GameplayState = _screen.run.snapshot()
	over.flow.phase = LevelFlowState.Phase.GAME_OVER
	var result := TickResult.new()
	result.final_snapshot = over
	_screen._accept(result)
	assert_null(_screen._game_over_page, "the sandbox never opens the page")
	assert_true(_screen._hud.visible)
	_screen._keep_alive()
	assert_true(_screen.notice.contains("ended"))
	assert_eq(_screen.run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)
	assert_true(_screen.playing)

func test_debug_overlay_reuses_the_shared_frog_facts() -> void:
	assert_false(_screen._overlay.visible)
	_screen.set_debug_visible(true)
	assert_true(_screen._overlay.visible)
	assert_true(_screen.palette.debug_toggle.button_pressed)
	assert_string_contains(_screen._overlay.text, "SANDBOX | zone plain")
	assert_string_contains(_screen._overlay.text, GameplayStateFacts.frog_lines(_screen._current, PackedStringArray()).get_slice("\n", 0))
	_screen.palette.debug_toggle.button_pressed = false
	assert_false(_screen.debug_visible)
	assert_false(_screen._overlay.visible)

func test_sandbox_hotkeys_avoid_gameplay_keys_and_drive_the_same_actions() -> void:
	for code: Key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_CTRL, KEY_Q, KEY_E, KEY_SPACE, KEY_R, KEY_ESCAPE]:
		assert_false(_screen._sandbox_key(code), str(code))
	assert_true(_screen.palette.select_kind("STATIC"))
	_send_key(KEY_P)
	assert_eq(_screen.spawner.placements.size(), 1)
	_send_key(KEY_F)
	assert_eq(_screen.spawner.placements.size(), 2)
	_send_key(KEY_BACKSPACE)
	assert_eq(_screen.spawner.placements.size(), 1)
	_send_key(KEY_X)
	assert_eq(_screen.spawner.placements.size(), 0)
	_send_key(KEY_3)
	assert_eq(_screen.palette.selected_preset(), SandboxSpawner.Preset.LOOP)
	_screen.palette.select_cell(Vector2i(8, 8))
	_send_key(KEY_T)
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(8, 8))
	_send_key(KEY_H)
	assert_eq(_screen.run.snapshot().frog.cell, SandboxLevel.SPAWN_CELL)
	_send_key(KEY_TAB)
	assert_false(_screen.palette.visible)
	_send_key(KEY_F3)
	assert_true(_screen.debug_visible)
	_send_key(KEY_R)
	assert_eq(_screen.run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)

func test_presets_load_replace_add_append_and_report_skips() -> void:
	var palette: SandboxPalette = _screen.palette
	assert_eq(palette.layouts.item_count, SandboxPresets.names().size())
	assert_eq(palette.selected_layout(), SandboxPresets.names()[0])
	assert_false(palette.layout_description.text.is_empty())
	assert_eq(_screen.place("STATIC", Vector2i(28, 28)), "")
	assert_eq(_screen.load_preset("river"), "")
	assert_eq(_screen.spawner.placements.size(), _screen.last_preset.placed.size())
	assert_eq(_screen.run.snapshot().frog.cell, SandboxPresets.named("river").start_cell)
	assert_false(_screen.last_preset.skipped.is_empty())
	assert_string_contains(_screen.notice, "Loaded river")
	assert_string_contains(_screen.notice, "skipped")
	assert_string_contains(palette.status.text, "SUB_TURTLE")
	assert_eq(_screen.placeholder_count(), _screen.spawner.placements.size())
	var river: int = _screen.spawner.placements.size()
	assert_eq(_screen.teleport_to_cell(Vector2i(20, 28)), "")
	assert_eq(_screen.load_preset("ice slide", false), "")
	assert_eq(_screen.spawner.placements.size(), river + _screen.last_preset.placed.size())
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(20, 28))
	assert_string_contains(_screen.notice, "Added ice slide")
	assert_ne(_screen.load_preset("missing"), "")
	assert_eq(_screen.spawner.placements.size(), river + _screen.last_preset.placed.size())
	for layout_name: String in SandboxPresets.names():
		assert_eq(_screen.load_preset(layout_name), "", layout_name)
		for tick: int in 5:
			assert_eq(_step().error, "", "%s %d" % [layout_name, tick])
	assert_true(palette.select_layout("enemy lane"))
	assert_eq(palette.layout_description.text, SandboxPresets.named("enemy lane").description)
	assert_false(palette.select_layout("missing"))

func test_preset_hotkeys_cycle_load_and_add() -> void:
	_send_key(KEY_O)
	assert_eq(_screen.palette.selected_layout(), SandboxPresets.names()[1])
	_send_key(KEY_L)
	assert_string_contains(_screen.notice, "Loaded %s" % SandboxPresets.names()[1])
	var loaded: int = _screen.spawner.placements.size()
	assert_gt(loaded, 0)
	_send_key(KEY_K)
	assert_eq(_screen.spawner.placements.size(), loaded * 2)
	_send_key(KEY_L)
	assert_eq(_screen.spawner.placements.size(), loaded)
	for step: int in SandboxPresets.names().size() - 1:
		_send_key(KEY_O)
	assert_eq(_screen.palette.selected_layout(), SandboxPresets.names()[0])

func _send_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_screen._unhandled_key_input(event)

func test_space_pauses_the_sandbox_without_the_pause_page() -> void:
	_send_key(KEY_SPACE)
	assert_false(_screen.playing)
	assert_null(_screen._pause_page)
	assert_eq(_screen._status.text, "Paused — Space to resume")
	_send_key(KEY_SPACE)
	assert_true(_screen.playing)

func test_boot_flags_and_scene_select_the_sandbox() -> void:
	assert_true(BootScreen.wants_sandbox(PackedStringArray(["--sandbox"])))
	assert_true(BootScreen.wants_sandbox(PackedStringArray(["--level=sandbox", "--no-audio"])))
	assert_false(BootScreen.wants_sandbox(PackedStringArray(["--level=ORG1"])))
	var scene: PackedScene = load(BootScreen.SANDBOX_SCENE)
	var instance: Node = scene.instantiate()
	assert_true(instance is SandboxScreen)
	instance.free()
