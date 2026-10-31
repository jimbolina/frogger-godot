class_name AssetCatalog
extends RefCounted
## Everything the game reads from the player's game data, behind one object.
##
## The game is typed against this catalog and asks it for things like "the
## level list row of SUB1", "the texture remap of this map" or "the model in
## slot 3 of this WAD", without caring where each lives. The answers that
## follow from the archive index ([member mwi]), the decoded executable tables
## ([member tables]) and FrogLord's name lists ([member names]) are worked out
## here; fetching and decoding archive resources is left to a concrete catalog
## such as [GameData], which reads the player's own files.

## The build the data belongs to.
var version: GameVersionConfig
## The executable's decoded tables, or null when they were not read.
var tables: GameTables
## The archive index.
var mwi: MwiIndex
## FrogLord's name lists for this build.
var names: GameNameLists
## Why the data cannot be used, or "".
var error: String = ""
## Non-fatal source inconsistencies, including a saved standalone index mismatch.
var warnings := PackedStringArray()


## True when the data opened cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Releases whatever the catalog holds open. A catalog that holds nothing
## open does nothing.
func close() -> void:
	pass


## The level list row of level [param level] (see [FroggerIds]), or null.
func map_book_entry(level: int) -> MapBookEntry:
	return tables.map_book().get_entry(level)


## The theme list row of theme [param theme], or null.
func theme_book_entry(theme: int) -> ThemeBookEntry:
	return tables.theme_book().get_entry(theme)


## The texture remap used by map resource [param map_resource_id], or null.
func remap_for_resource(map_resource_id: int) -> TextureRemap:
	return tables.remaps().for_resource(map_resource_id)


## The MWI entry called [param file_name] (folders ignored, any case), or null.
func find_resource(file_name: String) -> MwiEntry:
	return mwi.find_by_name(file_name)


## The contents of resource [param resource_id], decompressed. Returns an
## empty array, and adds the reason to [param problems], when the resource
## cannot be read. A concrete catalog provides this.
func read_resource(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	_unavailable("resource %d" % resource_id, problems)
	return PackedByteArray()


## The contents of the resource called [param file_name], or an empty array.
func read_resource_by_name(file_name: String, problems: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	var entry: MwiEntry = mwi.find_by_name(file_name)
	if entry == null:
		problems.append("no resource called %s" % file_name)
		return PackedByteArray()
	return read_resource(entry.index, problems)


## Every regular map resource, excluding the separate sky-land tile files.
func map_entries() -> Array[MwiEntry]:
	var entries: Array[MwiEntry] = []
	for entry: MwiEntry in mwi.entries:
		var file_name: String = entry.display_name().to_upper()
		if file_name.ends_with(".MAP") and not file_name.begins_with("SKY_LAND"):
			entries.append(entry)
	return entries


## The regular map with resource id [param resource_id], decoded; null, with
## the reason in [param problems], when it cannot be read. Sky-land tiles use
## [method read_sky_land]. A concrete catalog provides this.
func read_map(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> MapFile:
	_unavailable("map resource %d" % resource_id, problems)
	return null


## The separately formatted sky-land tiles of the chosen detail; null, with
## the reason in [param problems], when they cannot be read. A concrete
## catalog provides this.
func read_sky_land(low_poly: bool = false, problems: PackedStringArray = PackedStringArray()) -> SkyLandFile:
	_unavailable("sky land (low poly %s)" % low_poly, problems)
	return null


## The archive entries of every texture bank (type 1, or a name ending in .VLO),
## in index order.
func texture_bank_entries() -> Array[MwiEntry]:
	var banks: Array[MwiEntry] = []
	for e: MwiEntry in mwi.entries:
		if e.type_id == 1 or e.display_name().to_upper().ends_with(".VLO"):
			banks.append(e)
	return banks


## The texture bank with resource id [param resource_id], decoded; null (with
## the reason in [param problems]) when it cannot be read. A concrete catalog
## provides this.
func read_texture_bank(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> VloFile:
	_unavailable("texture bank %d" % resource_id, problems)
	return null


## The WAD with resource id [param wad_resource_id], or null when it is not a
## readable WAD. A concrete catalog provides this.
func read_wad(wad_resource_id: int) -> WadFile:
	_unavailable("WAD %d" % wad_resource_id, PackedStringArray())
	return null


## The resource id of a WAD holding resource [param resource_id], or -1. A
## concrete catalog provides this.
func wad_holding(resource_id: int) -> int:
	_unavailable("the WAD holding resource %d" % resource_id, PackedStringArray())
	return -1


## True if [param entry] is a model: type 3 or 4 (FrogLord's model types), or
## a name ending in .XMR, .XAR or .XMU.
static func is_model_entry(entry: MwiEntry) -> bool:
	if entry.type_id == 3 or entry.type_id == 4:
		return true
	var file_name: String = entry.display_name().to_upper()
	return file_name.ends_with(".XMR") or file_name.ends_with(".XAR") or file_name.ends_with(".XMU")


## The archive entries of every model, in index order.
func model_entries() -> Array[MwiEntry]:
	var found: Array[MwiEntry] = []
	for e: MwiEntry in mwi.entries:
		if is_model_entry(e):
			found.append(e)
	return found


## The model with resource id [param resource_id]; null, with the reason in
## [param problems], when it cannot be read. An incomplete model is joined to
## the model it takes its shape from. A concrete catalog provides this.
func read_model(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> MofFile:
	_unavailable("model %d" % resource_id, problems)
	return null


## The resource id of the complete model an incomplete model [param
## resource_id] takes its shape from, or -1. As in FrogLord, it is the nearest
## earlier model in the index that is not itself incomplete. A concrete
## catalog provides this.
func counterpart_of(resource_id: int) -> int:
	_unavailable("the counterpart of model %d" % resource_id, PackedStringArray())
	return -1


## The model at [param position] in WAD [param wad_resource_id], or null. A
## placeholder is returned as a model of kind DUMMY.
func read_wad_model(wad_resource_id: int, position: int, problems: PackedStringArray = PackedStringArray()) -> MofFile:
	var resource_id: int = model_resource_at(wad_resource_id, position)
	if resource_id < 0:
		problems.append("WAD %d has no file %d" % [wad_resource_id, position])
		return null
	return read_model(resource_id, problems)


## The resource id of the file at [param position] in WAD [param
## wad_resource_id], or -1.
func model_resource_at(wad_resource_id: int, position: int) -> int:
	var wad: WadFile = read_wad(wad_resource_id)
	if wad == null or position < 0 or position >= wad.children.size():
		return -1
	return wad.children[position].resource_id


## True if level number [param level] is a multiplayer level (the sixth of its theme).
static func is_multiplayer_level(level: int) -> bool:
	return level >= 0 and level < 60 and level % 6 == 5


## The WAD that holds the model of [param form] when it appears in level
## [param level]: the GENERAL theme's WAD for a GENERAL form or a model id of
## 128 or more, else the level's own WAD. Multiplayer levels use the
## multiplayer GENERAL WAD. Returns 0 when there is none.
func model_wad_for(form: FormBookEntry, level: int, low_poly: bool = false) -> int:
	if form.uses_general_wad():
		var general: ThemeBookEntry = theme_book_entry(FroggerIds.THEME_GENERAL)
		return general.wad_id(is_multiplayer_level(level), low_poly) if general != null else 0
	var row: MapBookEntry = map_book_entry(level)
	return row.wad_id(low_poly) if row != null else 0


## The resource id of the model of [param form] in level [param level], or -1
## when the form has no model or the WAD has no such file. The file may be a
## placeholder: a level's WAD only holds the models the level uses.
func model_resource_for(form: FormBookEntry, level: int, low_poly: bool = false) -> int:
	if form.has_flag(FormBookEntry.FLAG_NO_MODEL):
		return -1
	return model_resource_at(model_wad_for(form, level, low_poly), form.wad_index())


## The resource id of the texture bank the models of WAD [param
## wad_resource_id] use, or 0. A GENERAL WAD uses the GENERAL bank of the same
## kind; a level's WAD uses its theme's bank; any other WAD uses the bank
## named after it, and the options WADs use OPT_VRAM.VLO (FrogLord's
## [code]resolveMainVlo[/code]).
func texture_bank_for_wad(wad_resource_id: int) -> int:
	for theme: ThemeBookEntry in tables.theme_book().entries:
		for multiplayer: bool in [false, true]:
			for low_poly: bool in [false, true]:
				if theme.wad_id(multiplayer, low_poly) == wad_resource_id and wad_resource_id != 0:
					return _theme_bank(theme, multiplayer, low_poly)
	var row: MapBookEntry = tables.map_book().find_by_wad(wad_resource_id)
	if row != null:
		var level_theme: ThemeBookEntry = theme_book_entry(FroggerIds.theme_of_level(row.level))
		if level_theme != null:
			var bank: int = _theme_bank(level_theme, is_multiplayer_level(row.level), row.high_wad_id != wad_resource_id)
			if bank != 0:
				return bank
	var entry: MwiEntry = mwi.get_entry(wad_resource_id)
	if entry == null:
		return 0
	var wad_name: String = entry.display_name().to_upper()
	var bank_name: String = wad_name.get_basename().trim_prefix("THEME_") + ".VLO"
	if wad_name in ["OPTIONSL.WAD", "OPTIONSH.WAD", "OPTIONS.WAD"]:
		bank_name = "OPT_VRAM.VLO"
	var found: MwiEntry = mwi.find_by_name(bank_name)
	return found.index if found != null else 0


func _theme_bank(theme: ThemeBookEntry, multiplayer: bool, low_poly: bool) -> int:
	var bank: int = theme.vlo_id(multiplayer, low_poly)
	return bank if bank != 0 else theme.vlo_id(false, low_poly)


func _unavailable(what: String, problems: PackedStringArray) -> void:
	var reason: String = "this catalog cannot read %s" % what
	push_error(reason)
	problems.append(reason)
