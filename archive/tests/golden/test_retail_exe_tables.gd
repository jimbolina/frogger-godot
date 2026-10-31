extends RetailTest
## Needs the retail files: every table decoded from FROGGER.EXE matches the
## golden facts in tests/golden/pc-retail-v3.0e/exe_*.tsv (made by an
## independent Python reader, see tests/golden/README.md).

var _data: GameData
var _tables: ExeTables


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	_data = GameData.open(retail_source(), version)
	_tables = _data.exe_tables
	var started: int = Time.get_ticks_usec()
	var problems: PackedStringArray = _tables.errors()
	print("TIMING: decoded every EXE table in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	for problem: String in problems:
		print("EXE table problem: %s" % problem)


func after_all() -> void:
	if _data != null:
		_data.close()


func _texture_id(pointer: int) -> String:
	return str(_tables.bmp_pointers().texture_id_for_pointer(pointer))


func _check(label: String, got: Array[PackedStringArray]) -> void:
	var golden: Array[PackedStringArray] = GoldenFiles.rows("exe_%s.tsv" % label)
	var problems: PackedStringArray = GoldenFiles.differences(label, got, golden)
	for problem: String in problems:
		fail_test(problem)
	assert_eq(problems.size(), 0, "%s matches the golden rows" % label)


func test_data_opens_cleanly() -> void:
	assert_eq(_data.error, "")
	var score_table: ScoreTable = _tables.scores()
	assert_eq(score_table.error, "")
	var score_facts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/rewards.json"))
	assert_eq(score_table.values.size(), score_facts.size())
	for index: int in score_facts.size():
		var row: Dictionary = score_facts[index]
		var value: int = row.value
		var flags: int = row.flags
		var texture: int = row.texture
		assert_eq(score_table.values[index], value)
		assert_eq(score_table.flags[index], flags)
		assert_eq(score_table.texture_pointers[index], texture)
	var callbacks: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/form_callbacks.json"))
	for callback: Dictionary in callbacks:
		var address: int = callback.address
		var length: int = callback.length
		var offset: int = callback.file_offset
		assert_true(_data.exe.contains(offset, length))
		var hash_context := HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(_data.exe.bytes.slice(offset, offset + length))
		assert_eq(hash_context.finish().hex_encode(), str(callback.sha256), str(callback.name))
		assert_eq(FormCallbackCatalog.NAMES[address], str(callback.name))
	var problems: PackedStringArray = _tables.errors()
	assert_eq(problems.size(), 0, ", ".join(problems))
	assert_eq(_tables.theme_book().warnings.size(), 0, ", ".join(_tables.theme_book().warnings))


func test_summary() -> void:
	var facts: Dictionary[String, String] = GoldenFiles.facts("exe_summary.txt")
	var bmp: BmpPointers = _tables.bmp_pointers()
	var remaps: TextureRemapList = _tables.remaps()
	var last: TextureRemap = remaps.remaps[0]
	for remap: TextureRemap in remaps.remaps:
		if remap.file_offset > last.file_offset:
			last = remap
	var span_start: int = remaps.remaps[0].file_offset
	var lowest: int = bmp.pointers[0]
	var highest: int = bmp.pointers[0]
	for pointer: int in bmp.pointers:
		lowest = mini(lowest, pointer)
		highest = maxi(highest, pointer)
	var got: Dictionary[String, String] = {
		"map_book_rows": str(_tables.map_book().size()),
		"themes": str(_tables.theme_book().entries.size()),
		"forms": str(_tables.theme_book().form_count()),
		"bmp_pointers": str(bmp.size()),
		"bmp_pointers_sha256": GoldenFiles.list_digest(bmp.pointers),
		"bmp_pointers_first": GoldenFiles.hex(bmp.pointers[0]),
		"bmp_pointers_last": GoldenFiles.hex(bmp.pointers[bmp.size() - 1]),
		"bmp_pointers_min": GoldenFiles.hex(lowest),
		"bmp_pointers_max": GoldenFiles.hex(highest),
		"bmp_pointers_end": GoldenFiles.hex(bmp.end_offset),
		"remaps": str(remaps.size()),
		"remap_ids": str(remaps.id_count()),
		"remap_span_offset": GoldenFiles.hex(span_start),
		"remap_span_length": str(last.file_offset + 2 * last.size() - span_start),
		"scripts": str(_tables.scripts().size()),
		"script_commands": str(_tables.scripts().command_count()),
		"music_entries": str(_tables.music().size()),
		"arcade_entries": str(_tables.level_select().arcade.size()),
		"race_entries": str(_tables.level_select().race.size()),
		"demo_table_offset": GoldenFiles.hex(_tables.demo_table().file_offset),
		"demo_low_poly": str(int(_tables.demo_table().has_low_poly_list)),
		"demo_entries": str(_tables.demo_table().size()),
		"pickups": str(_tables.pickups().size()),
	}
	assert_eq(got.size(), facts.size(), "every summary fact is checked")
	for key: String in facts:
		var want: String = facts[key]
		var have: String = got.get(key, "<missing>")
		assert_eq(have, want, key)


func test_map_book() -> void:
	var got: Array[PackedStringArray] = []
	for e: MapBookEntry in _tables.map_book().entries:
		got.append(PackedStringArray([str(e.level), e.code(), str(e.high_map_id), str(e.low_map_id),
			GoldenFiles.hex(e.high_remap_pointer), GoldenFiles.hex(e.low_remap_pointer), str(int(e.use_cave_lights)),
			GoldenFiles.hex(e.environment_texture_pointer),
			_texture_id(e.environment_texture_pointer) if e.environment_texture_pointer != 0 else "-1",
			str(e.high_wad_id), str(e.low_wad_id), str(e.palette_id), str(int(e.is_dummy()))]))
	_check("map_book", got)


func test_theme_book() -> void:
	var got: Array[PackedStringArray] = []
	for t: ThemeBookEntry in _tables.theme_book().entries:
		got.append(PackedStringArray([str(t.theme), t.theme_name(), str(t.high_wad_id),
			GoldenFiles.hex(t.form_library_pointer), str(t.high_vlo_id), str(t.death_height),
			str(t.high_multiplayer_wad_id), str(t.high_multiplayer_vlo_id), str(t.low_wad_id), str(t.low_vlo_id),
			str(t.low_multiplayer_wad_id), str(t.low_multiplayer_vlo_id), str(int(t.is_valid())), str(t.forms.size())]))
	_check("theme_book", got)


func test_forms() -> void:
	var got: Array[PackedStringArray] = []
	var covered_forms: int = 0
	var multiplayer_forms: int = 0
	for f: FormBookEntry in _tables.theme_book().all_forms:
		got.append(PackedStringArray([FroggerIds.theme_name(f.theme), str(f.local_id), str(f.global_id), f.form_name,
			str(f.entity_type), f.entity_name, str(f.model_id), str(f.script_id), str(f.flags),
			GoldenFiles.hex(f.collision_callback), str(f.radius_squared), str(f.death_type), f.death_type_name(),
			GoldenFiles.hex(f.bonus_callback)]))
		if FroggerIds.theme_name(f.theme) in ["GENERAL", "ORIGINAL"]:
			covered_forms += 1
			if f.entity_name == "MULTIPOINT":
				multiplayer_forms += 1
			else:
				assert_ne(EntityBehaviorCatalog.resolve(f.entity_name).kind, EntityBehavior.Kind.UNKNOWN, f.form_name)
				assert_ne(FormCallbackCatalog.resolve("pc-retail-v3.0e", f.collision_callback), FormCallback.Kind.UNKNOWN, f.form_name + " collision")
				assert_ne(FormCallbackCatalog.resolve("pc-retail-v3.0e", f.bonus_callback, true), FormCallback.Kind.UNKNOWN, f.form_name + " bonus")
	_check("forms", got)
	assert_eq(covered_forms, 48, "all GENERAL and ORIGINAL forms checked")
	assert_eq(multiplayer_forms, 5, "only multiplayer checkpoint forms excluded")


func test_remaps() -> void:
	var got: Array[PackedStringArray] = []
	var position: int = 0
	for r: TextureRemap in _tables.remaps().remaps:
		got.append(PackedStringArray([str(position), r.name, GoldenFiles.hex(r.file_offset), str(r.resource_id),
			str(r.size()), GoldenFiles.list_digest32(r.texture_ids), str(r.global_id(0)) if r.size() > 0 else "",
			str(r.global_id(r.size() - 1)) if r.size() > 0 else ""]))
		position += 1
	_check("remaps", got)


func test_scripts() -> void:
	var got: Array[PackedStringArray] = []
	for s: EntityScript in _tables.scripts().scripts:
		var words: PackedInt32Array = s.words()
		got.append(PackedStringArray([str(s.id), s.name, GoldenFiles.hex(s.pointer), str(s.commands.size()),
			str(words.size()), GoldenFiles.list_digest32(words),
			s.commands[0].name() if not s.is_empty() else "", s.commands[-1].name() if not s.is_empty() else ""]))
	_check("scripts", got)


func test_music() -> void:
	var got: Array[PackedStringArray] = []
	var tracks: PackedInt32Array = _tables.music().tracks
	for level: int in tracks.size():
		got.append(PackedStringArray([str(level), FroggerIds.level_code(level), str(tracks[level]),
			FroggerIds.music_track_name(tracks[level])]))
	_check("music", got)


func test_level_select() -> void:
	var got: Array[PackedStringArray] = []
	var table: LevelSelectTable = _tables.level_select()
	for list: Array in [["arcade", table.arcade, table.arcade_terminator], ["race", table.race, table.race_terminator]]:
		var rows: Array[LevelSelectEntry] = []
		var entries: Array[LevelSelectEntry] = list[1]
		var terminator: LevelSelectEntry = list[2]
		rows.append_array(entries)
		rows.append(terminator)
		for position: int in rows.size():
			var e: LevelSelectEntry = rows[position]
			var row := PackedStringArray([str(list[0]), str(position), str(e.level), str(e.world), str(e.stack_position),
				str(e.theme), str(e.local_level), str(e.levels_in_world)])
			var ids := PackedStringArray()
			for pointer: int in e.image_pointers:
				row.append(GoldenFiles.hex(pointer))
				ids.append(_texture_id(pointer))
			row.append(",".join(ids))
			got.append(row)
	_check("level_select", got)


func test_demos() -> void:
	var table: DemoTable = _tables.demo_table()
	assert_eq(table.found_by, DemoTable.FOUND_BY_SEARCH)
	var got: Array[PackedStringArray] = []
	for pass_low_poly: bool in [true, false]:
		var position: int = 0
		for e: DemoTable.Entry in table.entries:
			var demo: int = e.demo_id(pass_low_poly)
			var entry: MwiEntry = _data.mwi.get_entry(demo)
			got.append(PackedStringArray(["low_poly" if pass_low_poly else "high_poly", str(position), str(e.level),
				FroggerIds.level_code(e.level), str(demo), entry.display_name() if entry != null else "",
				str(e.unlock_level)]))
			position += 1
	_check("demos", got)


func test_pickups() -> void:
	var got: Array[PackedStringArray] = []
	for p: PickupData in _tables.pickups():
		var ids := PackedStringArray()
		for pointer: int in p.frame_pointers:
			ids.append(_texture_id(pointer))
		got.append(PackedStringArray([str(p.fly_type), p.fly_type_name(), GoldenFiles.hex(p.pointer),
			"0x%06X" % (p.glow_colour & 0xFFFFFFFF), str(p.sprite_size), str(p.frame_pointers.size()), ",".join(ids)]))
	_check("pickups", got)


func test_facade_lookups() -> void:
	var sub1: MapBookEntry = _data.map_book_entry(FroggerIds.level_from_code("SUB1"))
	assert_not_null(sub1)
	var remap: TextureRemap = _data.remap_for_resource(sub1.high_map_id)
	assert_not_null(remap)
	if remap != null:
		assert_eq(remap.name, "txl_sub1")
	var map_entry: MwiEntry = _data.mwi.get_entry(sub1.high_map_id)
	var by_name: PackedByteArray = _data.read_resource_by_name(map_entry.display_name())
	assert_eq(by_name.size(), map_entry.unpacked_size, "a map inside a WAD reads at its full size")
	var swamp: ThemeBookEntry = _data.theme_book_entry(FroggerIds.THEMES.find("SWAMP"))
	var vlo: PackedByteArray = _data.read_resource(swamp.vlo_id())
	assert_eq(vlo.slice(0, 4).get_string_from_ascii(), "2GRP")
	var general_form: FormBookEntry = _tables.theme_book().get_form(FroggerIds.THEMES.find("SWAMP"), FormBookEntry.GENERAL_BIT | 0)
	assert_eq(general_form.theme, FroggerIds.THEME_GENERAL)
