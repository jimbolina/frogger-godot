extends RetailTest
## L4's archive check: the synthetic FrogLord save of the round-trip test,
## imported through the [AssetImporter] seam as an overlay over a base root the
## runtime import wrote under user://, falls back to that root, rewrites the
## pointer the game follows, and plays ORG1 with the save's edits.

const SPEC_PATH: String = "res://tests/golden/synthetic/froglord_edits.tsv"
const SCRATCH: String = "user://froglord_overlay_import"
const FIXTURE_ROOT: String = SCRATCH + "/save"
const BASE_ROOT: String = SCRATCH + "/assets/base"
const OVERLAY_PARENT: String = SCRATCH + "/froglord"
const POINTER_PATH: String = OVERLAY_PARENT + "/current.cfg"

var _importer: AssetImporter
var _fixture: FrogLordModFixture
var _base_problems := PackedStringArray()
var _result: AssetImporter.OverlayResult
var _labels := PackedStringArray()
var _overlay: ImportedAssets


func before_all() -> void:
	RuntimeImport.remove_tree(SCRATCH)
	var retail_dir: String = OS.get_environment(GameDataLocator.ENV_VAR)
	_fixture = FrogLordModFixture.write(retail_dir, FIXTURE_ROOT, SPEC_PATH)
	_importer = AssetImporterFactory.create()
	_base_problems = _importer.run(retail_dir, "", BASE_ROOT, Callable(), Callable())
	if not _fixture.error.is_empty() or not _base_problems.is_empty():
		return
	_importer.overlay_parent = OVERLAY_PARENT
	_importer.pointer_path = POINTER_PATH
	_result = _importer.import_overlay(FIXTURE_ROOT, BASE_ROOT, _on_progress, Callable())
	gut.p("overlay import over a runtime root: %.2f s, %d problems" % [_result.milliseconds / 1000.0, _result.problems.size()])
	if _result.is_ok():
		_overlay = ImportedAssets.open(BASE_ROOT, "", _result.index_root)


func after_all() -> void:
	if _overlay != null:
		_overlay.close()
	_overlay = null
	RuntimeImport.remove_tree(SCRATCH)


func _on_progress(_fraction: float, label: String) -> void:
	_labels.append(label)


func test_the_save_is_detected_as_froglords_files() -> void:
	assert_eq(_fixture.error, "")
	var found: AssetImporter.Detection = _importer.detect_froglord(FIXTURE_ROOT)
	assert_true(found.is_ok(), found.error)
	assert_true(found.froglord)
	assert_eq(found.build, AssetImporter.SUPPORTED_BUILD)
	assert_eq(found.froglord_version, FrogLordMwdWriter.FROGLORD_VERSION)
	assert_eq(found.files, "%s + %s" % [FrogLordModSource.EXE_NAME, FrogLordModSource.MWD_NAME])
	var retail: AssetImporter.Detection = _importer.detect_froglord(OS.get_environment(GameDataLocator.ENV_VAR))
	assert_true(retail.is_ok(), retail.error)
	assert_false(retail.froglord, "the retail pair is not a FrogLord save")
	var empty: AssetImporter.Detection = _importer.detect_froglord(SCRATCH)
	assert_eq(empty.fingerprint, "", "a folder without a pair has no files")
	assert_ne(_importer.source_state(FIXTURE_ROOT), "")
	assert_eq(_importer.source_state(SCRATCH), "")
	assert_eq(_importer.source_state(SCRATCH.path_join("missing")), "")


func test_the_overlay_falls_back_to_the_runtime_root_and_rewrites_the_pointer() -> void:
	assert_eq(_base_problems, PackedStringArray())
	assert_not_null(_result)
	if _result == null:
		return
	assert_true(_result.is_ok(), "%s %s %s" % [_result.error, _result.retry, "\n".join(_result.problems)])
	assert_eq(_result.fallback_root, BASE_ROOT)
	assert_eq(_result.index_root, OVERLAY_PARENT.path_join(_result.key))
	assert_eq(_result.source_state, _importer.source_state(FIXTURE_ROOT))
	assert_true(_labels.has("Converting maps"), ", ".join(_labels))
	assert_eq(_labels[-1] if not _labels.is_empty() else "", "Done")
	assert_true(FileAccess.file_exists(_result.report_path))
	var pointer: FrogLordPointer = FrogLordPointer.read(POINTER_PATH)
	assert_true(pointer.exists())
	assert_eq(pointer.index_root, _result.index_root)
	assert_eq(pointer.fallback_root, BASE_ROOT)
	assert_eq(pointer.data_dir, FIXTURE_ROOT)
	assert_eq(pointer.source_state, _result.source_state)
	var settings := LauncherSettings.new()
	settings.froglord_enabled = true
	settings.froglord_dir = FIXTURE_ROOT
	var choice: FrogLordOverlay = FrogLordOverlay.choose(false, settings, false, pointer, BASE_ROOT)
	assert_eq(choice.index_root, _result.index_root, "a level over the runtime root opens this overlay")
	assert_eq(FrogLordOverlay.choose(false, settings, false, pointer, "res://assets").index_root, "",
		"a level over the committed assets does not")


func test_the_overlay_index_names_the_runtime_root_for_what_it_did_not_write() -> void:
	if _overlay == null or not _overlay.is_valid():
		fail_test("overlay: %s" % (_overlay.error if _overlay != null else "not opened"))
		return
	assert_eq(_overlay.problems.size(), 0, "\n".join(_overlay.problems))
	assert_eq(_overlay.index.fallback_root, BASE_ROOT)
	assert_eq(_overlay.index.source_kind, AssetIndex.SOURCE_FROGLORD_MOD)
	var bank: int = _overlay.theme_book_entry(FroggerIds.THEME_GENERAL).vlo_id()
	assert_true(_overlay.index.path_of(bank).begins_with(BASE_ROOT + "/"), "texture bank %d: %s" % [bank, _overlay.index.path_of(bank)])
	var org1: int = _overlay.map_book_entry(FroggerIds.level_from_code("ORG1")).map_id(false)
	assert_true(_overlay.index.path_of(org1).begins_with(_result.index_root + "/"), "ORG1 map: %s" % _overlay.index.path_of(org1))
	for path: String in _overlay.index.paths.values():
		assert_false(path.begins_with("res://assets/"), "nothing falls back to the committed assets: %s" % path)
		if path.begins_with("res://assets/"):
			break


func test_org1_plays_the_edited_save_from_the_overlay() -> void:
	if _overlay == null or not _overlay.is_valid():
		fail_test("no overlay catalog")
		return
	var spec: FrogLordEditSpec = FrogLordEditSpec.read(SPEC_PATH)
	var edited: Array[FrogLordEditSpec.Row] = spec.of_kind("map")
	var number: int = FroggerIds.level_from_code("ORG1")
	var scene: MapSceneData = MapSceneData.load_level(_overlay, number, false)
	assert_eq(scene.error, "")
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_overlay)
	assert_eq(assets.error, "")
	if not scene.error.is_empty() or not assets.error.is_empty():
		return
	var setup: GameplaySetup = GameplaySetup.from_data(_overlay, number, scene.map, assets.model, assets.action_lengths)
	assert_eq(setup.error, "")
	if setup.definition == null:
		return
	var book: ThemeBook = _overlay.tables.theme_book()
	var found: bool = false
	for entity: EntityDefinition in setup.definition.entity_collision.entities:
		if not edited.is_empty() and entity.entity_index == edited[0].index():
			var form: FormBookEntry = book.get_form(scene.map.general.theme, entity.form_id)
			assert_eq(form.form_name if form != null else "", "ORG_CAR_PURPLE", "ORG1 entity %d" % entity.entity_index)
			found = true
	assert_true(found, "the edited ORG1 entity is placed")
	var run: GameplayRun = GameplayRun.create(setup.definition, RunStart.new())
	for tick: int in 30:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			break
	var report: LevelSupportReport = LevelSupportReport.from_catalog(_overlay, PackedStringArray(["ORG1"]))
	assert_eq(report.problems.size(), 0, "\n".join(report.problems))
