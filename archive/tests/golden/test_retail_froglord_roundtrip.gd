extends RetailTest
## P14's exit check: a FrogLord save of the retail files, edited as
## tests/golden/synthetic/froglord_edits.tsv specifies, is recognised,
## decoded, imported into an overlay beside the committed assets and played.
## The edited rows match froglord_roundtrip.tsv, written by the independent
## tools/golden/make_golden_froglord_roundtrip.py (tests/golden/specs/imported-assets.md).
## The watcher's cycle imports the same save and points the game at it.

const SPEC_PATH: String = "res://tests/golden/synthetic/froglord_edits.tsv"
const GOLDEN: String = "froglord_roundtrip.tsv"
const FIXTURE_ROOT: String = "user://froglord_fixture"
const OVERLAY_ROOT: String = "user://froglord_roundtrip"
const WATCH_ROOT: String = "user://froglord_roundtrip_watch"
const FALLBACK_ROOT: String = "res://assets"
const LEVELS: PackedStringArray = ["ORG1", "CAV3"]
const IMPORT_STEPS: PackedStringArray = ["names", "tables", "demos", "maps", "catalog"]

var _spec: FrogLordEditSpec
var _golden: Dictionary[String, Array] = {}
var _fixture: FrogLordModFixture
var _source: GameDataSource
var _detection: GameVersionDetector.Result
var _mod: GameData
var _retail: GameData
var _import_problems: int = -1
var _import_messages := PackedStringArray()
var _tables_cached_before_open: bool = true
var _overlay: ImportedAssets


func before_all() -> void:
	_spec = FrogLordEditSpec.read(SPEC_PATH)
	for row: PackedStringArray in GoldenFiles.rows(GOLDEN):
		if not _golden.has(row[0]):
			_golden[row[0]] = []
		_golden[row[0]].append(row.slice(1))
	_remove_tree(FIXTURE_ROOT)
	_remove_tree(OVERLAY_ROOT)
	_remove_tree(WATCH_ROOT)
	var library := FrogLordConfigLibrary.new()
	_retail = GameData.open(retail_source(), library.load_version("pc-retail-v3.0e"), library)
	_fixture = FrogLordModFixture.write(OS.get_environment(GameDataLocator.ENV_VAR), FIXTURE_ROOT, SPEC_PATH)
	if not _fixture.error.is_empty():
		return
	_source = GameDataLocator.open_directory(FIXTURE_ROOT)
	if _source == null:
		return
	_detection = GameVersionDetector.new(library).detect(_source.get_exe_bytes())
	if not _detection.is_ok():
		return
	_mod = GameData.open(_source, _detection.version, library)
	_import_problems = _import()
	_tables_cached_before_open = ResourceLoader.has_cached(OVERLAY_ROOT.path_join("tables/game_tables.tres"))
	_overlay = ImportedAssets.open(FALLBACK_ROOT, "", OVERLAY_ROOT)


func after_all() -> void:
	for data: GameData in [_mod, _retail]:
		if data != null:
			data.close()
	_mod = null
	_retail = null
	_overlay = null
	_remove_tree(FIXTURE_ROOT)
	_remove_tree(OVERLAY_ROOT)
	_remove_tree(WATCH_ROOT)


func _import() -> int:
	var context := ImportContext.new()
	context.assets_root = OVERLAY_ROOT
	context.fallback_root = FALLBACK_ROOT
	context.data = GameData.open(_source, _detection.version)
	if not context.data.is_valid():
		_import_messages.append(context.data.error)
		return -1
	var problems: int = ImportRun.new().run(context, ImportStep.PHASE_RESOURCES, IMPORT_STEPS)
	_import_messages = context.problems
	context.data.close()
	return problems


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(child))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _golden_section(tag: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	if _golden.has(tag):
		for row: PackedStringArray in _golden[tag]:
			rows.append(row)
	return rows


func _match_golden(label: String, got: Array[PackedStringArray], subject: String = "") -> void:
	var named: String = label if subject.is_empty() else "%s %s" % [label, subject]
	var differences: PackedStringArray = GoldenFiles.differences(named, got, _golden_section(label))
	for difference: String in differences:
		fail_test(difference)
	assert_eq(differences.size(), 0, "%s matches %s" % [label, GOLDEN])


func _spec_row(kind: String) -> FrogLordEditSpec.Row:
	var rows: Array[FrogLordEditSpec.Row] = _spec.of_kind(kind)
	return rows[0] if not rows.is_empty() else null


func _match_edited_rows(catalog: AssetCatalog, label: String) -> void:
	var tables: GameTables = catalog.tables
	var forms: Array[PackedStringArray] = []
	var form_names: PackedStringArray = _spec.names_of("form")
	for form: FormBookEntry in tables.theme_book().all_forms:
		if form_names.has(form.form_name):
			forms.append(RetailFactRows.form_row(form))
	_match_golden("exe_forms", forms)
	var scripts: Array[PackedStringArray] = []
	for script: EntityScript in tables.scripts().scripts:
		if _spec.names_of("script").has(script.name):
			scripts.append(RetailFactRows.script_row(script))
	_match_golden("exe_scripts", scripts)
	var remaps: Array[PackedStringArray] = []
	var position: int = 0
	for remap: TextureRemap in tables.remaps().remaps:
		if _spec.names_of("remap").has(remap.name):
			remaps.append(RetailFactRows.remap_row(position, remap))
		position += 1
	_match_golden("exe_remaps", remaps)
	var demo_ids := PackedInt64Array()
	for demo_name: String in _spec.names_of("demo"):
		var entry: MwiEntry = catalog.mwi.find_by_name(demo_name)
		assert_not_null(entry, "%s: %s" % [label, demo_name])
		if entry != null:
			demo_ids.append(entry.index)
	var problems := PackedStringArray()
	_match_golden("demos", RetailFactRows.demo_rows(catalog, problems, demo_ids), ", ".join(_spec.names_of("demo")))
	var maps: Array[PackedStringArray] = []
	for code: String in LEVELS:
		maps.append(RetailFactRows.entity_row(catalog, catalog.map_book_entry(FroggerIds.level_from_code(code)).map_id(false), problems))
	_match_golden("entities_retail", maps)
	assert_eq(problems.size(), 0, "%s: %s" % [label, "\n".join(problems)])


func test_the_save_is_recognised_as_froglord_files() -> void:
	assert_eq(_fixture.error, "")
	assert_true(_source is FrogLordModSource, "the fixture folder opens as FrogLord's files")
	assert_not_null(_detection)
	if _detection == null or _mod == null:
		return
	assert_eq(_detection.method, GameVersionDetector.METHOD_TRAILER)
	assert_eq(_detection.version.internal_name, "pc-retail-v3.0e")
	var trailer: FrogLordExeTrailer = (_source as FrogLordModSource).get_trailer()
	assert_eq(trailer.froglord_version, FrogLordMwdWriter.FROGLORD_VERSION)
	assert_eq(_mod.error, "")
	assert_true(_mod.is_valid())
	assert_true(_mod.standalone_index_checked, "the standalone MWI was compared with the executable's")
	assert_eq(_mod.warnings.size(), 0, "\n".join(_mod.warnings))
	assert_eq(_mod.exe_tables.errors().size(), 0, "\n".join(_mod.exe_tables.errors()))


func test_the_demo_table_reads_the_same_from_build_information() -> void:
	if _mod == null:
		fail_test("no modded data")
		return
	var recorded: DemoTable = _mod.tables.demo_table()
	var searched: DemoTable = _retail.tables.demo_table()
	assert_eq(recorded.found_by, DemoTable.FOUND_IN_BUILD_INFO)
	assert_eq(searched.found_by, DemoTable.FOUND_BY_SEARCH)
	assert_eq(recorded.file_offset, searched.file_offset)
	assert_eq(recorded.has_low_poly_list, searched.has_low_poly_list)
	assert_eq(recorded.entries.size(), searched.entries.size())
	for i: int in mini(recorded.entries.size(), searched.entries.size()):
		var a: DemoTableEntry = recorded.entries[i]
		var b: DemoTableEntry = searched.entries[i]
		assert_eq([a.level, a.demo_resource_id, a.low_poly_demo_resource_id, a.unlock_level],
			[b.level, b.demo_resource_id, b.low_poly_demo_resource_id, b.unlock_level], "demo row %d" % i)


func test_each_edit_lands_where_the_generator_put_it() -> void:
	assert_eq(_spec.error, "")
	_match_golden("edit", _fixture.edits)


func test_the_modded_files_decode_to_the_edited_rows() -> void:
	if _mod == null:
		fail_test("no modded data")
		return
	_match_edited_rows(_mod, "modded files")


func test_the_overlay_import_holds_the_edited_rows() -> void:
	assert_eq(_import_problems, 0, "\n".join(_import_messages))
	assert_false(_tables_cached_before_open, "the imported tables were released before the overlay opened")
	assert_not_null(_overlay)
	if _overlay == null or not _overlay.is_valid():
		fail_test("overlay: %s" % (_overlay.error if _overlay != null else "not opened"))
		return
	assert_eq(_overlay.problems.size(), 0, "\n".join(_overlay.problems))
	assert_eq(_overlay.index.source_kind, AssetIndex.SOURCE_FROGLORD_MOD)
	assert_eq(_overlay.index.froglord_version, FrogLordMwdWriter.FROGLORD_VERSION)
	assert_eq(_overlay.index.fallback_root, FALLBACK_ROOT)
	assert_eq(_overlay.version_name, "pc-retail-v3.0e")
	var bank: int = _overlay.theme_book_entry(FroggerIds.THEME_GENERAL).vlo_id()
	assert_true(_overlay.index.path_of(bank).begins_with(FALLBACK_ROOT + "/"), "texture bank %d: %s" % [bank, _overlay.index.path_of(bank)])
	var org1: int = _overlay.map_book_entry(FroggerIds.level_from_code("ORG1")).map_id(false)
	assert_true(_overlay.index.path_of(org1).begins_with(OVERLAY_ROOT + "/"), "ORG1 map: %s" % _overlay.index.path_of(org1))
	_match_edited_rows(_overlay, "overlay")


func test_the_edited_levels_set_up_from_the_overlay() -> void:
	if _overlay == null or not _overlay.is_valid():
		fail_test("no overlay catalog")
		return
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_overlay)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		return
	var book: ThemeBook = _overlay.tables.theme_book()
	for code: String in LEVELS:
		var number: int = FroggerIds.level_from_code(code)
		var scene: MapSceneData = MapSceneData.load_level(_overlay, number, false)
		assert_eq(scene.error, "", code)
		var problems := PackedStringArray()
		var map: MapFile = _overlay.read_map(_overlay.map_book_entry(number).map_id(false), problems)
		assert_not_null(map, "%s: %s" % [code, "; ".join(problems)])
		if map == null:
			continue
		var setup: GameplaySetup = GameplaySetup.from_data(_overlay, number, map, assets.model, assets.action_lengths)
		assert_eq(setup.error, "", code)
		if setup.definition == null:
			continue
		var collision: EntityCollisionDefinition = setup.definition.entity_collision
		var seen: Dictionary[String, int] = {}
		for slot: int in collision.entities.size():
			var entity: EntityDefinition = collision.entities[slot]
			var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
			var form_name: String = form.form_name if form != null else ""
			var count: int = seen.get(form_name, 0)
			seen[form_name] = count + 1
			match form_name:
				"ORG_LORRY":
					assert_true(entity.behavior.tongueable, "%s lorry entity %d is tongueable" % [code, entity.entity_index])
				"ORG_FLY":
					assert_eq(entity.bonus_kind, FormCallback.Kind.CAV_FIREFLY_SCORE, "%s fly entity %d" % [code, entity.entity_index])
				"GEN_STAT_FALL_BLOCK":
					assert_eq(collision.contacts[slot].callback_kind, FormCallback.Kind.WATERFALL_BLOCK, "%s block entity %d" % [code, entity.entity_index])
			if code == "ORG1" and entity.entity_index == _spec_row("map").index():
				assert_eq(form_name, "ORG_CAR_PURPLE", "ORG1 entity %d" % entity.entity_index)
		if code == "ORG1":
			assert_true(seen.has("ORG_LORRY"), "ORG1 places lorries")
			assert_true(seen.has("ORG_FLY"), "ORG1 places the bonus fly")
			var slot: int = _spec_row("remap").index()
			assert_eq(scene.remap.global_id(slot), _spec_row("remap").value, "ORG1 remap slot %d" % slot)
			assert_eq(_overlay.remap_for_resource(_map_id_of(code)).global_id(slot), _spec_row("remap").value)
			var demo: DemoSetup = DemoSetup.resolve(_overlay, number)
			assert_eq(demo.error, "")
			if demo.demo != null:
				assert_eq(demo.resource_name, _spec_row("demo").target)
				assert_eq(demo.demo.input_bytes[_spec_row("demo").index()], _spec_row("demo").value, "ORG1 demo input %d" % _spec_row("demo").index())
		else:
			assert_true(seen.has("GEN_STAT_FALL_BLOCK"), "CAV3 places fall blocks")


func _map_id_of(code: String) -> int:
	return _overlay.map_book_entry(FroggerIds.level_from_code(code)).map_id(false)


func test_the_support_report_adds_only_the_unplaced_probe() -> void:
	if _overlay == null or not _overlay.is_valid():
		fail_test("no overlay catalog")
		return
	var retail: LevelSupportReport = LevelSupportReport.from_catalog(_retail, LEVELS)
	var modded: LevelSupportReport = LevelSupportReport.from_catalog(_overlay, LEVELS)
	assert_eq(retail.problems.size(), 0, "\n".join(retail.problems))
	assert_eq(modded.problems.size(), 0, "\n".join(modded.problems))
	var known: Dictionary[String, bool] = {}
	for row: LevelSupportReport.Row in retail.rows:
		if not row.is_mapped():
			known[row.to_tsv()] = true
	var added: Array[PackedStringArray] = []
	for row: LevelSupportReport.Row in modded.rows:
		if not row.is_mapped() and not known.has(row.to_tsv()):
			added.append(PackedStringArray([row.kind, row.key, ",".join(row.levels), row.form]))
	_match_golden("report", added)


func test_the_watch_cycle_points_the_game_at_a_new_overlay() -> void:
	if _source == null:
		fail_test("no FrogLord fixture")
		return
	var pointer_path: String = WATCH_ROOT.path_join("current.cfg")
	var result: FrogLordWatchCycle.Result = FrogLordWatchCycle.run(FIXTURE_ROOT, IMPORT_STEPS, WATCH_ROOT, pointer_path)
	assert_true(result.is_ok(), "%s\n%s" % [result.line(), "\n".join(result.problems)])
	assert_eq(result.fingerprint, _source.fingerprint().substr(0, FrogLordWatchCycle.KEY_LENGTH))
	assert_eq(result.index_root, WATCH_ROOT.path_join(result.fingerprint))
	assert_eq(result.folders, 1)
	var pointer: FrogLordPointer = FrogLordPointer.read(pointer_path)
	assert_true(pointer.exists())
	assert_eq(pointer.index_root, result.index_root)
	assert_eq(pointer.fingerprint, result.fingerprint)
	assert_eq(pointer.source_summary, result.source_summary)
	assert_eq(pointer.report_path, result.index_root.path_join(FrogLordWatchCycle.REPORT_FILE))
	assert_gt(pointer.written_at, 0)
	assert_false(FileAccess.file_exists(pointer_path + ".tmp"))
	assert_true(FileAccess.file_exists(pointer.report_path))
	var overlay: ImportedAssets = ImportedAssets.open(FALLBACK_ROOT, "", pointer.index_root)
	assert_true(overlay.is_valid(), overlay.error)
	if overlay.is_valid():
		assert_eq(overlay.index.source_kind, AssetIndex.SOURCE_FROGLORD_MOD)
		assert_eq(overlay.source_summary(), pointer.source_summary)
	overlay.close()
	_remove_tree(WATCH_ROOT)
