extends GutTest
## The EXE table readers on small synthetic executables (no game files needed).

const P: int = SyntheticExe.RAM_OFFSET


func _exe() -> SyntheticExe:
	return SyntheticExe.new()


func test_image_converts_pointers_and_finds_patterns() -> void:
	var s := _exe()
	s.s32s(0x100, [48, 7])
	var image: ExeImage = s.image()
	assert_eq(image.program_length, s.bytes.size())
	assert_eq(image.pointer_to_offset(P + 0x123), 0x123)
	assert_eq(image.offset_to_pointer(0x123), P + 0x123)
	assert_true(ExeImage.looks_like_pointer(0x0047A7E0))
	assert_false(ExeImage.looks_like_pointer(0x0147A7E0))
	var pattern := PackedByteArray([48, 0, 0, 0, 7, 0, 0, 0])
	assert_eq(image.find(pattern), 0x100)
	assert_eq(image.find(PackedByteArray([9, 9, 9])), -1)


func test_trailer_limits_reads_to_the_program() -> void:
	var s := _exe()
	var with_trailer: PackedByteArray = s.with_trailer("demoTableAddress=0x40\n")
	var image: ExeImage = ExeImage.create(with_trailer, s.version)
	assert_eq(image.error, "")
	assert_eq(image.program_length, s.bytes.size())
	assert_eq(image.trailer_value("demoTableAddress"), "0x40")
	assert_eq(image.find("frogger".to_ascii_buffer()), -1, "the build information is not searched")
	var reader: ByteReader = image.reader_at(s.bytes.size() - 2)
	reader.read_u32()
	assert_true(reader.has_error(), "reading into the appended text fails")


func test_music_list_ends_at_ff_and_keeps_unknown_tracks() -> void:
	var s := _exe()
	s.put(0x200, PackedByteArray([2, 3, 99, 0xFF, 5]))
	s.version.music_address = 0x200
	var music: MusicTable = MusicTableReader.read(s.image())
	assert_eq(music.error, "")
	assert_eq(Array(music.tracks), [2, 3, 99])
	assert_eq(music.track_for_level(1), 3)
	assert_eq(music.track_for_level(3), -1)
	assert_eq(FroggerIds.music_track_name(99), "")
	assert_eq(FroggerIds.music_track_name(2), "CAVE1")


func test_music_list_without_end_inside_the_program_is_an_error() -> void:
	var s := SyntheticExe.new(0xFF)
	for i: int in range(0xF0, 0xFF):
		s.bytes[i] = 4
	s.version.music_address = 0xF0
	var with_trailer: PackedByteArray = s.with_trailer("")
	var music: MusicTable = MusicTableReader.read(ExeImage.create(with_trailer, s.version))
	assert_ne(music.error, "", "the 0xFF-free list may not run on into the appended text")


func test_map_book_runs_up_to_the_theme_book() -> void:
	var s := _exe()
	s.s32s(0x300, [10, 11, P + 0x900, P + 0x910, 1, 0, 20, 21, 30])
	s.s32s(0x324, [0, 0, 0, 0, 0, 0, 0, 0, 0])
	s.s32s(0x348, [12, 13, P + 0x920, 0, 7, P + 0x50, 22, 23, 31])
	s.version.map_book = 0x300
	s.version.theme_book = 0x36C
	var book: MapBook = MapBookReader.read(s.image())
	assert_eq(book.error, "")
	assert_eq(book.size(), 3)
	var first: MapBookEntry = book.get_entry(0)
	assert_eq([first.high_map_id, first.low_map_id, first.high_wad_id, first.low_wad_id, first.palette_id], [10, 11, 20, 21, 30])
	assert_true(first.use_cave_lights)
	assert_eq(first.remap_pointer(true), P + 0x910)
	assert_true(book.get_entry(1).is_dummy())
	assert_false(book.get_entry(2).use_cave_lights, "only the value 1 means cave lights")
	assert_eq(book.get_entry(2).environment_texture_pointer, P + 0x50)
	assert_eq(book.find_by_map(13), book.get_entry(2))
	assert_eq(book.get_entry(0).code(), "CAV1")


func _theme_exe() -> SyntheticExe:
	var s := _exe()
	s.version.theme_book = 0x400
	var libraries: Dictionary[int, int] = {0: 0x800, 1: 0x840, 2: 0x860}
	for theme: int in 11:
		var library: int = libraries.get(theme, 0)
		s.s32s(0x400 + 40 * theme, [100 + theme, P + library if library != 0 else 0, 200 + theme, 256,
			0, 0, 0, 300 + theme, 0, 0])
	s.s32s(0x800, [2, 128, 0, 24, 0, 0, 0, 0])
	s.s32s(0x820, [5, 129, 3, 1, P + 0x1234, 400, 2, P + 0x5678])
	s.s32s(0x840, [5, 0, 0, 0, 0, 0, 1, 0])
	s.s32s(0x860, [6, 1, 0, 0, 0, 0, 0, 0])
	return s


func test_theme_book_and_form_libraries() -> void:
	var s := _theme_exe()
	var names: GameNameLists = SyntheticExe.name_lists(
		"[GENERAL]\nGEN_A\nGEN_B\n[CAVE]\nCAV_A\n[DESERT]\nDES_A\n", "ZERO\nONE\nCHECKPOINT\nX\nY\nMOVING\nSNAIL\n[Override]\nCAV_A=SNAIL\n")
	var book: ThemeBook = ThemeBookReader.read(s.image(), names)
	assert_eq(book.error, "")
	assert_eq(book.entries.size(), 11)
	assert_eq(book.warnings.size(), 0, ", ".join(book.warnings))
	var general: ThemeBookEntry = book.get_entry(0)
	assert_eq([general.high_wad_id, general.high_vlo_id, general.low_vlo_id], [100, 200, 300])
	assert_eq(general.vlo_id(false, true), 300)
	assert_eq(book.get_entry(6).forms.size(), 0, "a theme without a library has no forms")
	assert_eq(book.form_count(), 4)
	var gen_b: FormBookEntry = general.forms[1]
	assert_eq([gen_b.global_id, gen_b.form_name, gen_b.entity_name, gen_b.script_id], [1, "GEN_B", "MOVING", 3])
	assert_eq([gen_b.collision_callback, gen_b.radius_squared, gen_b.death_type_name(), gen_b.bonus_callback],
		[P + 0x1234, 400, "DROWN", P + 0x5678])
	assert_true(gen_b.has_flag(FormBookEntry.FLAG_NO_MODEL))
	assert_eq(gen_b.wad_index(), 1)
	assert_eq(gen_b.map_form_id(), FormBookEntry.GENERAL_BIT | 1)
	var cave_a: FormBookEntry = book.get_form(1, 0)
	assert_eq([cave_a.global_id, cave_a.entity_type, cave_a.entity_name], [2, 5, "SNAIL"], "entity override applies")
	assert_eq(book.get_form(1, FormBookEntry.GENERAL_BIT | 0), general.forms[0])
	assert_eq(book.get_form(2, 0).form_name, "DES_A", "the last library is sized by its names")
	assert_null(book.get_form(1, 5))


func test_form_library_size_disagreement_is_a_warning() -> void:
	var s := _theme_exe()
	var names: GameNameLists = SyntheticExe.name_lists("[GENERAL]\nGEN_A\n[CAVE]\nCAV_A\n[DESERT]\nDES_A\n", "ZERO\n")
	var book: ThemeBook = ThemeBookReader.read(s.image(), names)
	assert_eq(book.warnings.size(), 1)
	assert_eq(book.get_entry(0).forms.size(), 1, "the name count wins, as in FrogLord")


func test_bmp_pointers_end_at_the_first_non_address() -> void:
	var s := _exe()
	s.s32s(0x500, [P + 0x1000, P + 0x1010, P + 0x1000, 0x00050004])
	s.version.bmp_pointer_address = 0x500
	var list: BmpPointers = BmpPointersReader.read(s.image())
	assert_eq(list.size(), 3)
	assert_eq(list.end_offset, 0x50C)
	assert_eq(list.texture_id_for_pointer(P + 0x1010), 1)
	assert_eq(list.texture_id_for_pointer(P + 0x1000), 0, "the first id with that record")
	assert_eq(list.texture_id_for_pointer(P + 0x2000), -1)


func _remap_exe() -> SyntheticExe:
	var s := _exe()
	s.add_mwi(0x100, [["PACKED\\FIXE_VRAM.VLO", 1, 1], ["PACKED\\SUB1.MAP", 0, 2], ["PACKED\\SUB1_WIN95.MAP", 0, 2]])
	s.version.map_book = 0x300
	s.version.theme_book = 0x348
	s.s32s(0x300, [1, 2, P + 0x600, P + 0x620, 0, 0, 0, 0, 0])
	s.s32s(0x324, [0, 0, P + 0x620, P + 0x640, 0, 0, 0, 0, 0])
	s.version.txl_sky_land = 0x640
	s.s16s(0x600, [5, 6, 7, 0, 0, 0])
	s.s16s(0x620, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23])
	s.s16s(0x640, [30, 31, 0])
	return s


func test_remaps_are_sized_by_terminators_and_neighbours() -> void:
	var s := _remap_exe()
	var image: ExeImage = s.image()
	var list: TextureRemapList = TextureRemapListReader.read(image, s.mwi(), MapBookReader.read(image))
	assert_eq(list.error, "")
	assert_eq(list.size(), 3, "the row with map id 0 adds nothing; shared addresses count once")
	var sub1: TextureRemap = list.for_resource(1)
	assert_eq(sub1.name, "txl_sub1")
	assert_eq(Array(sub1.texture_ids), [5, 6, 7])
	assert_eq(sub1.slots, 16, "zero padding up to the next remap belongs to it")
	var low: TextureRemap = list.find_by_name("txl_sub1_win95")
	assert_eq(low.size(), 16, "a remap without a terminator stops where the next begins")
	assert_eq(low.global_id(15), 23)
	assert_eq(low.global_id(16), -1)
	var sky: TextureRemap = list.find_by_name("txl_sky_land")
	assert_eq(Array(sky.texture_ids), [30, 31])
	assert_eq(sky.resource_id, -1)
	assert_eq(list.id_count(), 21)


func test_unexplained_bytes_between_remaps_become_an_unnamed_remap() -> void:
	var s := _remap_exe()
	s.s16s(0x600, [5, 0, 0, 40, 41, 0, 0, 0])
	var image: ExeImage = s.image()
	var list: TextureRemapList = TextureRemapListReader.read(image, s.mwi(), MapBookReader.read(image))
	assert_eq(list.size(), 4)
	var unknown: TextureRemap = list.remaps[1]
	assert_eq(unknown.name, "txl_unknown")
	assert_eq(unknown.file_offset, 0x606)
	assert_eq(Array(unknown.texture_ids), [40, 41])


func test_scripts_decode_until_a_final_command() -> void:
	var s := _exe()
	s.version.scripts = 0x700
	s.u32(0x700, 0)
	s.u32(0x704, P + 0x800)
	s.u32(0x708, P + 0x840)
	s.s32s(0x800, [7, 1, 2, 4, 9, 5, 6])
	s.s32s(0x840, [8, 1, 2, 3, 4, 5, 999])
	var names: GameNameLists = SyntheticExe.name_lists("", "", "SCRIPT_NONE\nSCRIPT_A\nSCRIPT_B\n[CallbackNames]\nCB_A\n")
	var table: ScriptTable = ScriptTableReader.read(s.image(), names.scripts)
	assert_eq(table.error, "")
	assert_eq(table.size(), 3, "sized by the main name list only")
	assert_true(table.get_script_by_id(0).is_empty())
	var a: EntityScript = table.get_script_by_id(1)
	assert_eq(a.name, "SCRIPT_A")
	assert_eq(a.commands.size(), 3)
	assert_eq(a.commands[0].name(), "SET_TIMER")
	assert_eq(Array(a.commands[0].arguments), [1, 2])
	assert_eq(a.commands[2].name(), "RESTART")
	assert_eq(Array(a.words()), [7, 1, 2, 4, 9, 5])
	var b: EntityScript = table.get_script_by_id(2)
	assert_eq(b.commands.size(), 1)
	assert_eq(Array(b.commands[0].arguments), [1, 2, 3, 4, 5])
	assert_eq(table.command_count(), 4)


func test_opcode_table_matches_the_original_command_lengths() -> void:
	var lengths: Array[int] = [3, 1, 1, 2, 2, 1, 1, 3, 6, 1, 3, 1, 1, 5, 3, 1, 1, 5, 1, 4, 2, 4, 1, 1, 1, 2, 2, 2,
		2, 1, 1, 3, 1, 4, 5, 2, 6, 5, 1, 1, 1, 1, 3, 2, 2, 7, 1, 1, 1]
	assert_eq(ScriptOpcodes.count(), lengths.size())
	for opcode: int in lengths.size():
		assert_eq(ScriptOpcodes.argument_count(opcode) + 1, lengths[opcode], ScriptOpcodes.name_of(opcode))
	assert_true(ScriptOpcodes.is_final(ScriptOpcodes.NAMES.find("STOP")))


func _level_row(s: SyntheticExe, offset: int, values: Array[int]) -> int:
	s.s32s(offset, values)
	return offset + LevelSelectEntry.SIZE


func test_level_select_reads_arcade_then_race() -> void:
	var s := _exe()
	s.version.arcade_level_address = 0x900
	var at: int = _level_row(s, 0x900, [48, 0, 0, 9, 0, 5, P + 1, P + 2, P + 3, P + 4, P + 5, P + 6])
	at = _level_row(s, at, [-1, 0, 9, 255, 0, 0, 0, 0, 0, 0, 0, 0])
	at = _level_row(s, at, [53, 0, 1, 9, 0, 1, 0, 0, 0, 0, 0, 0])
	_level_row(s, at, [-1, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var table: LevelSelectTable = LevelSelectTableReader.read(s.image())
	assert_eq(table.error, "")
	assert_eq(table.arcade.size(), 1)
	assert_eq(table.race.size(), 1)
	assert_true(table.arcade_terminator.is_terminator())
	var sub1: LevelSelectEntry = table.entry_for_level(48)
	assert_eq([sub1.theme, sub1.levels_in_world, sub1.image_pointers[5]], [9, 5, P + 6])
	assert_eq(table.entry_for_level(53), table.race[0])


func test_level_select_refuses_run_time_data() -> void:
	var s := _exe()
	s.version.arcade_level_address = 0x900
	_level_row(s, 0x900, [48, 0, 0, 9, 0, 5, 0, 0, 0, 0, 0, 0])
	s.bytes[0x900 + 60] = 1
	assert_ne(LevelSelectTableReader.read(s.image()).error, "")


func _demo_exe() -> SyntheticExe:
	var s := _exe()
	s.add_mwi(0x100, [["BINARIES\\SUB1DEMO.DAT", 6, 1], ["BINARIES\\WSUB1DEMO.DAT", 6, 1], ["BINARIES\\DES1DEMO.DAT", 6, 1]])
	s.s32s(0xA00, [48, 1, 48, 6, 2, 6, -1, -1, -1])
	s.s32s(0xA24, [48, 0, 48, 6, 2, 6, -1, -1, -1])
	return s


func test_demo_table_found_by_search_with_two_lists() -> void:
	var s := _demo_exe()
	var table: DemoTable = DemoTableReader.read(s.image(), s.mwi())
	assert_eq(table.error, "")
	assert_eq(table.found_by, DemoTable.FOUND_BY_SEARCH)
	assert_eq(table.file_offset, 0xA00)
	assert_true(table.has_low_poly_list)
	assert_eq(table.size(), 2)
	var sub1: DemoTable.Entry = table.entry_for_level(48)
	assert_eq([sub1.demo_id(false), sub1.demo_id(true), sub1.unlock_level], [0, 1, 48])


func test_demo_lists_must_name_the_same_levels() -> void:
	var s := _demo_exe()
	s.s32(0xA24 + 12, 7)
	var table: DemoTable = DemoTableReader.read(s.image(), s.mwi())
	assert_ne(table.error, "")
	assert_eq(table.size(), 0)


func test_demo_table_address_from_froglord_build_information() -> void:
	var s := _demo_exe()
	s.s32s(0xB00, [6, 2, 6, -1, -1, -1])
	var bytes: PackedByteArray = s.with_trailer("demoTableAddress=0xB00\n")
	var table: DemoTable = DemoTableReader.read(ExeImage.create(bytes, s.version), s.mwi())
	assert_eq(table.error, "")
	assert_eq(table.found_by, DemoTable.FOUND_IN_BUILD_INFO)
	assert_eq(table.file_offset, 0xB00)
	assert_false(table.has_low_poly_list)
	assert_eq(table.size(), 1)
	assert_eq(table.entries[0].demo_id(true), 2, "one list serves both detail levels")


func test_demo_table_missing_is_not_an_error() -> void:
	var s := _exe()
	s.add_mwi(0x100, [["BINARIES\\OTHER.DAT", 6, 1]])
	var table: DemoTable = DemoTableReader.read(s.image(), s.mwi())
	assert_eq(table.error, "")
	assert_eq(table.file_offset, -1)
	assert_eq(table.size(), 0)


func test_pickups_read_one_record_per_bug_kind() -> void:
	var s := _exe()
	s.version.pickup_data = 0xC00
	for kind: int in FroggerIds.FLY_SCORE_TYPES.size():
		s.u32(0xC00 + 4 * kind, P + 0xD00)
	s.s32s(0xD00, [0x824682, 0x20000, P + 0x10, P + 0x20, 0])
	var problems := PackedStringArray()
	var pickups: Array[PickupData] = PickupDataReader.read_table(s.image(), problems)
	assert_eq(problems.size(), 0)
	assert_eq(pickups.size(), 19)
	assert_eq(pickups[3].fly_type_name(), "SCORE_100")
	assert_eq([pickups[3].glow_colour, pickups[3].sprite_size, pickups[3].frame_pointers.size()], [0x824682, 0x20000, 2])


func test_frogger_ids() -> void:
	assert_eq(FroggerIds.level_from_code("sub1"), 48)
	assert_eq(FroggerIds.theme_of_level(48), FroggerIds.THEMES.find("SUBURBIA"))
	assert_eq(FroggerIds.theme_of_level(0), FroggerIds.THEMES.find("CAVE"))
	assert_eq(FroggerIds.theme_of_level(60), -1)
	assert_eq(FroggerIds.world_name(7), "CAVES")


func test_tables_reader_reads_every_table_and_names_missing_inputs() -> void:
	var s := _exe()
	s.version.music_address = 0x200
	s.put(0x200, PackedByteArray([2, 0xFF]))
	var tables: GameTables = ExeTablesReader.read(s.image(), null, null)
	assert_eq(Array(tables.music().tracks), [2])
	assert_string_contains(tables.theme_book().error, "name lists")
	assert_string_contains(tables.scripts().error, "name lists")
	assert_string_contains(tables.remaps().error, "archive index")
	assert_string_contains(tables.demo_table().error, "archive index")
	for table: Resource in [tables.map_book(), tables.bmp_pointers(), tables.scores(), tables.high_scores(),
			tables.level_select(), tables.sound_tables(), tables.particle_generators(), tables.splash_lists()]:
		assert_not_null(table)
	assert_true(tables.errors().size() > 0)
	assert_null(ExeTablesReader.read(null, null, null).map_book(), "no executable leaves every table unread")


func test_exe_tables_without_an_executable_hold_supplied_tables() -> void:
	var tables := ExeTables.new()
	assert_null(tables.map_book())
	tables._bmp_pointers = BmpPointers.new()
	assert_same(tables.bmp_pointers(), tables.decoded.bmp_pointer_table)
	var row := PickupData.new()
	var rows: Array[PickupData] = [row]
	tables._pickups = rows
	assert_same(tables.pickups()[0], row)
	assert_eq(tables.errors().size(), 0)
