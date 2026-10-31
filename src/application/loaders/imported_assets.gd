class_name ImportedAssets
extends AssetCatalog
## The [AssetCatalog] read from the committed resources under
## [code]res://assets[/code], written once by the importer.
##
## [method open] loads the [AssetIndex] ([code]catalog.tres[/code]), the
## executable tables and the name lists; every other record is loaded on
## request through Godot's resource cache, so a record asked for twice is the
## same object. Records are shared and must not be changed. The retail archive
## is not kept, so no raw resource bytes are available.

## The asset index the catalog answers from.
var index: AssetIndex
## The folder the assets were opened from.
var root: String = ""
## Records that could not be loaded, one line each.
var problems: PackedStringArray = PackedStringArray()


## Opens the assets under [param assets_root]. Check [member AssetCatalog.error].
static func open(assets_root: String = "res://assets") -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.root = assets_root
	var index_path: String = assets_root.path_join("catalog.tres")
	catalog.index = catalog._load(index_path) as AssetIndex
	if catalog.index == null:
		catalog.error = "no asset index at %s" % index_path
		return catalog
	catalog.version_name = catalog.index.version_name
	catalog.hidden_parts = catalog.index.hidden_parts
	catalog.mwi = catalog.index.mwi
	if catalog.mwi == null:
		catalog.error = "the asset index has no archive index"
		return catalog
	catalog.tables = catalog._load(catalog.index.tables_path) as GameTables
	if catalog.tables == null:
		catalog.error = "no executable tables at %s" % catalog.index.tables_path
		return catalog
	catalog.names = catalog._load(catalog.index.names_path) as GameNameLists
	if catalog.names == null:
		catalog.error = "no name lists at %s" % catalog.index.names_path
	return catalog


## The SHA-256 of the executable and archive the assets were imported from.
func source_digests() -> Dictionary[String, String]:
	return {"exe": index.exe_sha256, "mwd": index.mwd_sha256}


## The codes of the levels the importer recorded as playable, in the arcade
## level-select stack's order, then any others in level-number order.
func playable_level_codes() -> PackedStringArray:
	var codes := PackedStringArray()
	for entry: LevelSelectEntry in tables.level_select().arcade:
		var code: String = FroggerIds.level_code(entry.level)
		if code in index.playable_levels and not code in codes:
			codes.append(code)
	for code: String in index.playable_levels:
		if not code in codes:
			codes.append(code)
	return codes


## The imported map with resource id [param resource_id], or null.
func read_map(resource_id: int, problems_out: PackedStringArray = PackedStringArray()) -> MapFile:
	return _record(resource_id, "map", problems_out) as MapFile


## The imported sky-land tiles of the chosen detail, or null.
func read_sky_land(low_poly: bool = false, problems_out: PackedStringArray = PackedStringArray()) -> SkyLandFile:
	var entry: MwiEntry = find_resource("SKY_LAND_WIN95.MAP" if low_poly else "SKY_LAND.MAP")
	if entry == null:
		problems_out.append("no sky-land file for low poly %s" % low_poly)
		return null
	return _record(entry.index, "sky land", problems_out) as SkyLandFile


## The imported texture bank with resource id [param resource_id], or null.
## Its images hold their imported [member VloImage.texture]; their
## [member VloImage.pixels] are empty.
func read_texture_bank(resource_id: int, problems_out: PackedStringArray = PackedStringArray()) -> VloFile:
	return _record(resource_id, "texture bank", problems_out) as VloFile


## The WAD with resource id [param wad_resource_id], its children listed
## without their bytes, or null.
func read_wad(wad_resource_id: int) -> WadFile:
	return index.wads.get(wad_resource_id, null)


## The resource id of a WAD holding resource [param resource_id], or -1.
func wad_holding(resource_id: int) -> int:
	return index.wad_holding(resource_id)


## The imported model with resource id [param resource_id], or null. An
## incomplete model was joined to its counterpart when it was imported.
func read_model(resource_id: int, problems_out: PackedStringArray = PackedStringArray()) -> MofFile:
	return _record(resource_id, "model", problems_out) as MofFile


## The complete model the incomplete model [param resource_id] takes its
## shape from, or -1 (also for a complete model).
func counterpart_of(resource_id: int) -> int:
	return index.counterparts.get(resource_id, -1)


## The imported demo with resource id [param resource_id], or null.
func read_demo(resource_id: int, problems_out: PackedStringArray = PackedStringArray()) -> SourceDemoFile:
	return _record(resource_id, "demo", problems_out) as SourceDemoFile


## The imported sound bank whose body has resource id [param resource_id], or null.
func read_sound_bank(resource_id: int, problems_out: PackedStringArray = PackedStringArray()) -> SoundBankHeader:
	return _record(resource_id, "sound bank", problems_out) as SoundBankHeader


## The baked page set of texture banks [param general_bank_id] then
## [param theme_bank_id], or null.
func page_set_for_banks(general_bank_id: int, theme_bank_id: int,
		problems_out: PackedStringArray = PackedStringArray()) -> TexturePageSet:
	var general: MwiEntry = mwi.get_entry(general_bank_id)
	var theme: MwiEntry = mwi.get_entry(theme_bank_id)
	if general == null or theme == null:
		problems_out.append("no texture banks %d and %d" % [general_bank_id, theme_bank_id])
		return null
	return page_set(TexturePageSet.name_for(PackedStringArray([general.display_name(), theme.display_name()])), problems_out)


## The baked page set called [param set_name], or null.
func page_set(set_name: String, problems_out: PackedStringArray = PackedStringArray()) -> TexturePageSet:
	if not index.page_sets.has(set_name):
		problems_out.append("no texture page set %s" % set_name)
		return null
	var found: TexturePageSet = _load(index.page_sets[set_name]) as TexturePageSet
	if found == null:
		problems_out.append("texture page set %s does not load" % set_name)
	return found


func _record(resource_id: int, kind: String, problems_out: PackedStringArray) -> Resource:
	var path: String = index.path_of(resource_id)
	if path.is_empty():
		var message: String = "%s %d was not imported" % [kind, resource_id]
		problems_out.append(message)
		problems.append(message)
		return null
	var loaded: Resource = _load(path)
	if loaded == null:
		var message: String = "%s %d does not load from %s" % [kind, resource_id, path]
		problems_out.append(message)
		problems.append(message)
	return loaded


func _load(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
