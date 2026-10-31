extends AssetTest
## The imported executable tables, name lists and demos load from assets/ and
## match the retail facts: every row of the exe_*.tsv tables, the high-score
## row counts of asset_census.txt and the demo headers of demos.tsv.

var _assets: ImportedAssets
var _tables: GameTables


func before_all() -> void:
	_assets = catalog()
	_tables = _assets.tables


func _texture_id(pointer: int) -> String:
	return str(_tables.bmp_pointers().texture_id_for_pointer(pointer))


func _check(label: String, got: Array[PackedStringArray]) -> void:
	var problems: PackedStringArray = GoldenFiles.differences(label, got, fact_rows("exe_%s.tsv" % label))
	for problem: String in problems:
		fail_test(problem)
	assert_eq(problems.size(), 0, "%s matches the golden rows" % label)


func test_catalog_opens() -> void:
	assert_eq(_assets.error, "")
	assert_eq(_assets.version_name, "pc-retail-v3.0e")
	assert_eq(_tables.errors().size(), 0, ", ".join(_tables.errors()))
	assert_not_null(_assets.names)
	assert_eq(_assets.names.errors.size(), 0)
	assert_eq(_assets.index.exe_sha256.length(), 64)
	assert_eq(_assets.index.mwd_sha256.length(), 64)


func test_tables_are_separate_files() -> void:
	for table: Resource in [_tables.map_book(), _tables.theme_book(), _tables.bmp_pointers(), _tables.remaps(),
			_tables.scripts(), _tables.scores(), _tables.high_scores(), _tables.music(), _tables.level_select(),
			_tables.demo_table(), _tables.sound_tables(), _tables.particle_generators(), _tables.splash_lists()]:
		assert_not_null(table)
		if table != null:
			assert_true(table.resource_path.begins_with("res://assets/tables/") and not table.resource_path.contains("::"),
				"%s is its own file" % table.resource_path)


func test_names() -> void:
	var names: GameNameLists = _assets.names
	for bank: NameBank in [names.forms, names.entities, names.scripts, names.sounds, names.images, names.anims]:
		assert_not_null(bank)
		if bank != null:
			assert_gt(bank.size(), 0)
	var forms: int = 0
	for theme: ThemeBookEntry in _tables.theme_book().entries:
		forms += theme.forms.size()
	assert_eq(forms, int(fact_values("asset_census.txt")["rows[exe_forms]"]))
	assert_eq(names.images.index_of("newfont") >= 0, true)


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
	for f: FormBookEntry in _tables.theme_book().all_forms:
		got.append(PackedStringArray([FroggerIds.theme_name(f.theme), str(f.local_id), str(f.global_id), f.form_name,
			str(f.entity_type), f.entity_name, str(f.model_id), str(f.script_id), str(f.flags),
			GoldenFiles.hex(f.collision_callback), str(f.radius_squared), str(f.death_type), f.death_type_name(),
			GoldenFiles.hex(f.bonus_callback)]))
	_check("forms", got)


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


func test_demo_table() -> void:
	var table: DemoTable = _tables.demo_table()
	var got: Array[PackedStringArray] = []
	for pass_low_poly: bool in [true, false]:
		var position: int = 0
		for e: DemoTableEntry in table.entries:
			var demo: int = e.demo_id(pass_low_poly)
			var entry: MwiEntry = _assets.mwi.get_entry(demo)
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


func test_high_score_rows() -> void:
	var facts: Dictionary[String, String] = fact_values("asset_census.txt")
	var scores: HighScoreTable = _tables.high_scores()
	assert_eq(scores.error, "")
	assert_eq(scores.main_scores.size(), int(facts["rows[exe_high_scores_main]"]))
	assert_eq(scores.level_scores.size(), int(facts["rows[exe_high_scores_levels]"]))


func test_demos() -> void:
	var dat_entries: int = 0
	var headers: Dictionary[int, PackedStringArray] = {}
	for row: PackedStringArray in fact_rows("demos.tsv"):
		headers[int(row[2])] = row.slice(3, 8)
	var checked: Dictionary[int, bool] = {}
	for entry: MwiEntry in _assets.mwi.entries:
		if not entry.display_name().to_upper().ends_with(".DAT"):
			continue
		dat_entries += 1
		var problems := PackedStringArray()
		var demo: SourceDemoFile = _assets.read_demo(entry.index, problems)
		assert_not_null(demo, "%s: %s" % [entry.display_name(), "; ".join(problems)])
		if demo == null:
			continue
		assert_true(demo.is_valid(), entry.display_name())
		if not headers.has(entry.index):
			continue
		var values := PackedInt64Array()
		for byte: int in demo.input_bytes:
			values.append(byte)
		assert_eq(PackedStringArray([str(demo.duration), str(demo.start_grid_x), str(demo.start_grid_z),
			str(values.size()), GoldenFiles.list_digest(values)]), headers[entry.index], entry.display_name())
		checked[entry.index] = true
	assert_eq(dat_entries, 42, "every DAT entry was imported")
	assert_eq(checked.size(), headers.size(), "every demo of demos.tsv was compared")
	assert_eq(checked.size(), int(fact_values("asset_census.txt")["demos"]))
