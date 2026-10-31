extends AssetTest
## The files under assets/ hold as many of each kind of asset as the retail
## files do (asset_census.txt): archive entries, maps, texture banks, images
## and distinct texture PNGs, models by kind, sound banks and samples, demos
## and music tracks.

var _assets: ImportedAssets
var _facts: Dictionary[String, String]


func before_all() -> void:
	_assets = catalog()
	_facts = fact_values("asset_census.txt")


func _fact(key: String) -> int:
	return int(_facts[key])


func test_archive_index() -> void:
	assert_eq(_assets.error, "")
	assert_eq(_assets.mwi.size(), _fact("mwi_entries"))


func test_maps() -> void:
	var frog_maps: int = 0
	var sky_land: int = 0
	for entry: MwiEntry in _assets.mwi.entries:
		if not entry.display_name().to_upper().ends_with(".MAP"):
			continue
		var path: String = _assets.index.path_of(entry.index)
		var loaded: Resource = load(path) if not path.is_empty() else null
		if loaded is MapFile:
			frog_maps += 1
		elif loaded is SkyLandFile:
			sky_land += 1
	assert_eq(frog_maps, _fact("frog_maps"), "map resources")
	assert_eq(sky_land, _fact("sky_land_maps"), "sky-land resources")
	assert_eq(frog_maps + sky_land, _fact("maps"))


func test_texture_banks_and_images() -> void:
	var banks: PackedStringArray = files_under(ASSETS.path_join("textures/banks"), ".tres")
	assert_eq(banks.size(), _fact("vlo_banks"), "bank resources")
	var images: int = 0
	for entry: MwiEntry in _assets.texture_bank_entries():
		var bank: VloFile = _assets.read_texture_bank(entry.index)
		images += bank.size() if bank != null else 0
	assert_eq(images, _fact("images"), "images in the banks")
	assert_eq(files_under(ASSETS.path_join("textures/images"), ".png").size(), _fact("distinct_texture_ids"),
		"one PNG per distinct texture id")


func test_models() -> void:
	var counts: Dictionary[String, int] = {"static": 0, "animated": 0, "dummy": 0}
	var models: int = 0
	var incomplete: int = 0
	var parts: int = 0
	for entry: MwiEntry in _assets.model_entries():
		var model: MofFile = _assets.read_model(entry.index)
		if model == null:
			continue
		models += 1
		if counts.has(model.kind_name()):
			counts[model.kind_name()] += 1
		incomplete += int(model.is_incomplete)
		parts += model.part_count()
	assert_eq(models, _fact("models"), "model resources")
	for kind: String in counts:
		assert_eq(counts[kind], _fact("models_" + kind), kind + " models")
	assert_eq(incomplete, _fact("models_incomplete"), "incomplete models")
	assert_eq(parts, _fact("model_parts"), "model parts")


func test_sound() -> void:
	assert_eq(files_under(ASSETS.path_join("audio/sfx"), ".tres").size(), _fact("sound_banks"), "sound bank resources")
	assert_eq(files_under(ASSETS.path_join("audio/sfx"), ".wav").size(), _fact("sound_samples"), "sample WAVs")


func test_demos() -> void:
	var table: DemoTable = _assets.tables.demo_table()
	assert_eq(2 if table.has_low_poly_list else 1, _fact("demo_tables"))
	assert_eq(table.size() * (2 if table.has_low_poly_list else 1), _fact("demo_table_rows"))
	var demos: Dictionary[int, bool] = {}
	for row: DemoTableEntry in table.entries:
		for low_poly: bool in [false, true]:
			var id: int = row.demo_id(low_poly)
			if id >= 0 and _assets.read_demo(id) != null:
				demos[id] = true
	assert_eq(demos.size(), _fact("demos"), "demo resources the demo table names")


func test_music() -> void:
	assert_eq(files_under(ASSETS.path_join("audio/music"), ".ogg").size(), _fact("disc_audio_tracks"), "music tracks")
