class_name GameData
extends RefCounted
## Everything read from the player's game files, behind one object.
##
## Built from a [GameDataSource] (a retail install or FrogLord's modded
## files) and its build ([GameVersionConfig]), it owns the executable
## ([ExeImage]) and its decoded tables ([ExeTables]), the archive index
## ([MwiIndex]), the archive ([MwdArchive]) and FrogLord's name lists. Later
## parts of the game ask it for things like "the level list row of SUB1",
## "the texture remap of this map" or "the bytes of resource 123", without
## caring where each lives.

## The files the data comes from.
var source: GameDataSource
## The build.
var version: GameVersionConfig
## The executable.
var exe: ExeImage
## The executable's decoded tables.
var tables: ExeTables
## The archive index.
var mwi: MwiIndex
## The archive, open for reading.
var archive: MwdArchive
## FrogLord's name lists for this build.
var names: GameNameLists
## Why the data cannot be used, or "".
var error: String = ""

var _wads: Dictionary[int, WadFile] = {}
var _wad_of_resource: Dictionary[int, int] = {}
var _models: Dictionary[int, MofFile] = {}


## Opens [param data_source] as build [param build]; name lists come from
## [param library] (the shipped FrogLord files by default). Check [member error].
static func open(data_source: GameDataSource, build: GameVersionConfig, library: FrogLordConfigLibrary = null) -> GameData:
	var data := GameData.new()
	data.source = data_source
	data.version = build
	data.exe = ExeImage.create(data_source.get_exe_bytes(), build)
	if not data.exe.is_valid():
		data.error = data.exe.error
		return data
	data.mwi = MwiIndex.from_exe(data.exe.bytes, build)
	if not data.mwi.is_valid():
		data.error = "archive index: %s" % data.mwi.error
		return data
	var problems := PackedStringArray()
	data.archive = MwdArchive.open(data_source.get_mwd_path(), problems)
	if data.archive == null:
		data.error = "archive: %s" % ", ".join(problems)
		return data
	data.names = GameNameLists.load_for(build, library if library != null else FrogLordConfigLibrary.new())
	data.tables = ExeTables.new(data.exe, data.mwi, data.names)
	return data


## True when the data opened cleanly.
func is_valid() -> bool:
	return error.is_empty()


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


## The contents of resource [param resource_id], decompressed. Files that live
## only inside WADs are taken from the first WAD holding them (every copy is
## identical in retail data). Returns an empty array, and adds the reason to
## [param problems], when the resource cannot be read.
func read_resource(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	var entry: MwiEntry = mwi.get_entry(resource_id)
	if entry == null:
		problems.append("no resource %d" % resource_id)
		return PackedByteArray()
	if not entry.is_group_access():
		var bytes: PackedByteArray = archive.read(entry)
		if not archive.error.is_empty():
			problems.append(archive.error)
		return bytes
	var wad: WadFile = _find_wad_holding(resource_id)
	if wad == null:
		problems.append("%s is in no WAD" % entry.display_name())
		return PackedByteArray()
	for child: WadFile.Child in wad.children:
		if child.resource_id == resource_id:
			return wad.child_contents(child)
	return PackedByteArray()


## The contents of the resource called [param file_name], or an empty array.
func read_resource_by_name(file_name: String, problems: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	var entry: MwiEntry = mwi.find_by_name(file_name)
	if entry == null:
		problems.append("no resource called %s" % file_name)
		return PackedByteArray()
	return read_resource(entry.index, problems)


## The resource id of a WAD holding resource [param resource_id], or -1.
func wad_holding(resource_id: int) -> int:
	return _wad_of_resource[resource_id] if _find_wad_holding(resource_id) != null else -1


## The archive entries of every texture bank (type 1, or a name ending in .VLO),
## in index order.
func texture_bank_entries() -> Array[MwiEntry]:
	var banks: Array[MwiEntry] = []
	for e: MwiEntry in mwi.entries:
		if e.type_id == 1 or e.display_name().to_upper().ends_with(".VLO"):
			banks.append(e)
	return banks


## The texture bank with resource id [param resource_id], decoded; null (with
## the reason in [param problems]) when it cannot be read.
func read_texture_bank(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> VloFile:
	var bytes: PackedByteArray = read_resource(resource_id, problems)
	if bytes.is_empty():
		return null
	var vlo: VloFile = VloFile.parse(bytes)
	if not vlo.error.is_empty():
		problems.append("resource %d: %s" % [resource_id, vlo.error])
		return null
	return vlo


## The WAD with resource id [param wad_resource_id], parsed (and kept for
## later calls), or null when it is not a readable WAD.
func read_wad(wad_resource_id: int) -> WadFile:
	if _wads.has(wad_resource_id):
		return _wads[wad_resource_id]
	var entry: MwiEntry = mwi.get_entry(wad_resource_id)
	if entry == null or not entry.is_wad():
		return null
	var wad: WadFile = WadFile.parse(archive.read(entry))
	if not wad.is_valid():
		return null
	_wads[wad_resource_id] = wad
	for child: WadFile.Child in wad.children:
		if not _wad_of_resource.has(child.resource_id):
			_wad_of_resource[child.resource_id] = wad_resource_id
	return wad


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


## The model with resource id [param resource_id], parsed (and kept for later
## calls); null, with the reason in [param problems], when it cannot be read.
## An incomplete model is joined to the model it takes its shape from.
func read_model(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> MofFile:
	if _models.has(resource_id):
		return _models[resource_id]
	var bytes: PackedByteArray = read_resource(resource_id, problems)
	if bytes.is_empty():
		return null
	var counterpart: MofFile = null
	if MofFile.needs_counterpart(bytes):
		counterpart = _complete_model_before(resource_id, problems)
	var model: MofFile = MofFile.parse(bytes, counterpart)
	if not model.is_valid():
		problems.append("resource %d: %s" % [resource_id, model.error])
		return null
	_models[resource_id] = model
	return model


## The resource id of the complete model an incomplete model [param
## resource_id] takes its shape from, or -1. As in FrogLord, it is the nearest
## earlier model in the index that is not itself incomplete.
func counterpart_of(resource_id: int) -> int:
	for id: int in range(resource_id - 1, -1, -1):
		var entry: MwiEntry = mwi.get_entry(id)
		if entry == null or not is_model_entry(entry):
			continue
		if not MofFile.needs_counterpart(read_resource(id)):
			return id
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


## Closes the archive.
func close() -> void:
	if archive != null:
		archive.close()


func _complete_model_before(resource_id: int, problems: PackedStringArray) -> MofFile:
	var id: int = counterpart_of(resource_id)
	if id < 0:
		problems.append("resource %d is incomplete and no complete model comes before it" % resource_id)
		return null
	return read_model(id, problems)


# A theme's bank for the given kind, falling back to its single-player bank.
func _theme_bank(theme: ThemeBookEntry, multiplayer: bool, low_poly: bool) -> int:
	var bank: int = theme.vlo_id(multiplayer, low_poly)
	return bank if bank != 0 else theme.vlo_id(false, low_poly)


func _find_wad_holding(resource_id: int) -> WadFile:
	if _wad_of_resource.has(resource_id):
		return read_wad(_wad_of_resource[resource_id])
	for wad_entry: MwiEntry in mwi.wad_entries():
		if _wads.has(wad_entry.index):
			continue
		read_wad(wad_entry.index)
		if _wad_of_resource.has(resource_id):
			return read_wad(_wad_of_resource[resource_id])
	return null
