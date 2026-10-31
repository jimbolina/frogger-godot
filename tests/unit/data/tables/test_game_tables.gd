extends GutTest
## GameTables and the executable table records survive a resource save and load, rebuilding their lookups.

const ROOT: String = "user://test_game_tables"


func _records() -> Array[GDScript]:
	return [GameTables, MapBook, MapBookEntry, ThemeBook, ThemeBookEntry, FormBookEntry, BmpPointers, TextureRemapList,
		TextureRemap, ScriptTable, EntityScript, EntityScriptCommand, ScoreTable, HighScoreTable, MusicTable,
		LevelSelectTable, LevelSelectEntry, DemoTable, DemoTableEntry, PickupData, SoundTables, SoundSampleEntry,
		ExeParticleGenerators, ParticleGeneratorRecord, ExeSplashAnimLists]


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))
	DirAccess.remove_absolute(ROOT)


func _round_trip(resource: Resource, file_name: String) -> Resource:
	var path: String = ROOT.path_join(file_name)
	assert_eq(ResourceSaver.save(resource, path), OK, file_name)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func test_every_public_field_is_stored() -> void:
	for record: GDScript in _records():
		for property: Dictionary in record.get_script_property_list():
			var field: String = property.name
			var usage: int = property.usage
			if field.begins_with("_") or usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			assert_true(usage & PROPERTY_USAGE_STORAGE != 0, "%s.%s is stored" % [record.get_global_name(), field])


func test_inner_class_aliases_still_name_the_records() -> void:
	var command: EntityScript.Command = EntityScript.Command.new()
	command.opcode = ScriptOpcodes.NAMES.find("STOP")
	var commands: Array[EntityScript.Command] = [command]
	var script_entry := EntityScript.new()
	script_entry.commands = commands
	assert_eq(script_entry.commands[0].name(), "STOP")
	var row: DemoTable.Entry = DemoTable.Entry.new()
	row.level = DemoTable.Entry.SKIP
	var rows: Array[DemoTable.Entry] = [row]
	var demos := DemoTable.new()
	demos.entries = rows
	assert_true(row.is_skipped())
	assert_null(demos.entry_for_level(DemoTableEntry.SKIP))


func _tables() -> GameTables:
	var tables := GameTables.new()
	tables.bmp_pointer_table = BmpPointers.new()
	tables.bmp_pointer_table.pointers = PackedInt64Array([0x401000, 0x401010, 0x401000])
	tables.remap_table = TextureRemapList.new()
	for remap_name: String in ["txl_sky_land", "txl_sub1"]:
		var remap := TextureRemap.new()
		remap.name = remap_name
		remap.resource_id = -1 if remap_name == "txl_sky_land" else 7
		remap.texture_ids = PackedInt32Array([3, 4])
		tables.remap_table.remaps.append(remap)
	tables.script_table = ScriptTable.new()
	var script_entry := EntityScript.new()
	script_entry.id = 0
	script_entry.name = "SCRIPT_A"
	var command := EntityScriptCommand.new()
	command.opcode = ScriptOpcodes.NAMES.find("SET_TIMER")
	command.arguments = PackedInt32Array([1, 2])
	script_entry.commands.append(command)
	tables.script_table.scripts.append(script_entry)
	tables.theme_book_table = ThemeBook.new()
	var theme := ThemeBookEntry.new()
	var form := FormBookEntry.new()
	form.form_name = "GEN_A"
	theme.forms.append(form)
	tables.theme_book_table.entries.append(theme)
	tables.theme_book_table.all_forms.append(form)
	tables.level_select_table = LevelSelectTable.new()
	tables.level_select_table.arcade_terminator = LevelSelectEntry.new()
	tables.level_select_table.arcade_terminator.level = LevelSelectEntry.TERMINATOR_LEVEL
	tables.demo_list = DemoTable.new()
	var demo := DemoTableEntry.new()
	demo.level = 48
	demo.demo_resource_id = 9
	tables.demo_list.entries.append(demo)
	tables.particle_generator_table = ExeParticleGenerators.c_constants()
	tables.splash_list_table = ExeSplashAnimLists.new()
	tables.splash_list_table.lists.append(PackedInt32Array([7, 3, 4, 5, 6, 2]))
	tables.sound_table = SoundTables.new()
	tables.sound_table.banks.append(Vector2i(1, 2))
	var pickup := PickupData.new()
	pickup.fly_type = 3
	tables.pickup_table.append(pickup)
	tables.pickup_problems.append("pickup SCORE_200: short")
	return tables


func test_tables_round_trip_and_rebuild_lookups() -> void:
	var loaded := _round_trip(_tables(), "tables.tres") as GameTables
	assert_not_null(loaded)
	assert_eq(loaded.bmp_pointers().texture_id_for_pointer(0x401000), 0, "the first id with that record")
	assert_eq(loaded.bmp_pointers().texture_id_for_pointer(0x401010), 1)
	assert_eq(loaded.remaps().find_by_name("txl_sub1").global_id(1), 4)
	assert_eq(loaded.remaps().for_resource(7).name, "txl_sub1")
	assert_null(loaded.remaps().for_resource(-1))
	assert_eq(loaded.scripts().get_script_by_id(0).commands[0].name(), "SET_TIMER")
	assert_eq(Array(loaded.scripts().get_script_by_id(0).words()), [7, 1, 2])
	assert_same(loaded.theme_book().all_forms[0], loaded.theme_book().get_entry(0).forms[0], "shared forms stay shared")
	assert_true(loaded.level_select().arcade_terminator.is_terminator())
	assert_null(loaded.level_select().race_terminator)
	assert_eq(loaded.demo_table().entry_for_level(48).demo_id(), 9)
	assert_eq(loaded.particle_generators().find("PGIN_hilite_dust").texture_kind, ParticleGeneratorRecord.TextureKind.TEXTURE_LIST)
	assert_eq(loaded.particle_generators().for_hilite_type(6).name, "PGIN_hilite_fire")
	assert_eq(loaded.splash_lists().ripple_texture_ids(), PackedInt32Array([7, 3, 4, 5, 6, 2]))
	assert_eq(loaded.sound_tables().banks, [Vector2i(1, 2)])
	assert_eq(loaded.pickups()[0].fly_type_name(), "SCORE_100")
	assert_eq(loaded.errors(), PackedStringArray(["pickups: pickup SCORE_200: short"]))


func test_errors_skip_unread_tables_and_name_failed_ones() -> void:
	var tables := GameTables.new()
	assert_eq(tables.errors(), PackedStringArray())
	tables.music_table = MusicTable.new()
	tables.music_table.error = "no end"
	tables.remap_table = TextureRemapList.new()
	tables.remap_table.error = "bad remap"
	assert_eq(tables.errors(), PackedStringArray(["texture remaps: bad remap", "music: no end"]))


func test_failed_remap_list_offers_no_lookups() -> void:
	var list := TextureRemapList.new()
	var remap := TextureRemap.new()
	remap.name = "txl_sub1"
	remap.resource_id = 1
	list.remaps.append(remap)
	list.error = "txl_cav1 at 9: out of range"
	assert_null(list.find_by_name("txl_sub1"), "as when reading stopped before the lookups were built")
	assert_null(list.for_resource(1))
