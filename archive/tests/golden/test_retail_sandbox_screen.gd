extends RetailTest
## The sandbox scene with player data offers data-backed kinds and forms and draws real models.

var _data: GameData
var _screen: SandboxScreen

func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func before_each() -> void:
	_screen = SandboxScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)

func test_palette_offers_data_backed_kinds_and_form_variants() -> void:
	assert_eq(_screen.open_sandbox(_data), "")
	assert_eq(_screen.data_status, "")
	assert_not_null(_screen.templates)
	assert_not_null(_screen._frog_model)
	assert_false(_screen._frog.visible)
	var palette: SandboxPalette = _screen.palette
	assert_false(palette.is_kind_disabled("SUB_TURTLE"))
	assert_false(palette.is_kind_disabled("VOL_COLOUR_SWITCH"))
	assert_true(palette.is_kind_disabled("ORG_BABY_FROG"))
	assert_string_contains(palette.kind_tooltip("ORG_BABY_FROG"), "parent log")
	assert_true(palette.select_kind("MOVING"))
	assert_false(palette.forms.disabled)
	assert_eq(palette.forms.item_count, _screen.templates.form_names("MOVING").size() + 1)
	assert_true(palette.select_form("ORG_CAR_BLUE"))
	assert_eq(palette.selected_form(), "ORG_CAR_BLUE")
	assert_true(palette.select_kind("STATIC"))
	assert_eq(palette.selected_form(), "")

func test_placed_entities_draw_models_and_borrowed_data_stays_open() -> void:
	assert_eq(_screen.open_sandbox(_data), "")
	var palette: SandboxPalette = _screen.palette
	assert_true(palette.select_kind("MOVING"))
	assert_true(palette.select_form("ORG_CAR_BLUE"))
	palette.select_preset(SandboxSpawner.Preset.LINE)
	assert_eq(_screen.place_ahead(), "")
	assert_eq(_screen.spawner.placements[0].form_name, "ORG_CAR_BLUE")
	assert_eq(_screen.place("SUB_TURTLE", Vector2i(4, 10), SandboxSpawner.Preset.LOOP), "")
	assert_eq(_screen.entity_model_count(), 2, " ".join(_screen.entity_model_diagnostics))
	assert_eq(_screen.placeholder_count(), 0)
	assert_eq(_screen.run.snapshot().frog.cell, SandboxLevel.SPAWN_CELL)
	for tick: int in 20:
		var command := TickCommand.new()
		command.tick_index = _screen.run.snapshot().tick_index
		assert_eq(_screen.step_command(command, false).error, "", str(tick))
		_screen.draw_state(0.5)
	assert_eq(_screen.remove_last(), "")
	assert_eq(_screen.entity_model_count(), 1)
	assert_eq(_screen.teleport_to_zone(&"water"), "")
	assert_eq(_screen.clear_entities(), "")
	assert_eq(_screen.entity_model_count(), 0)
	_screen.close_data()
	var problems := PackedStringArray()
	assert_not_null(_data.read_map(_data.map_book_entry(FroggerIds.level_from_code("ORG1")).map_id(false), problems), " ".join(problems))
