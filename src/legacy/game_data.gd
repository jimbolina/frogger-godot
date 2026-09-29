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


## Closes the archive.
func close() -> void:
	if archive != null:
		archive.close()


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
