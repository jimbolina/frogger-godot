class_name GameData
extends AssetCatalog
## The [AssetCatalog] read from the player's own game files.
##
## Built from a [GameDataSource] (a retail install or FrogLord's modded
## files) and its build ([GameVersionConfig]), it owns the executable
## ([ExeImage]) and its decoded tables ([ExeTables]), the archive index
## ([MwiIndex]), the archive ([MwdArchive]) and FrogLord's name lists, and
## fetches and decodes archive resources on request, keeping WADs and models
## for later calls.

## The rate of the samples [method read_sound_bank] gives, as the import writes them.
const SAMPLE_RATE: int = 11025
## The sky theme, whose banks also hold the sky-land tiles.
const SKY_THEME: int = 8
## The remap of the sky-land tiles' texture ids.
const SKY_REMAP: String = "txl_sky_land"
## The codes of the levels the game plays, in level-select order.
const PLAYABLE_LEVEL_CODES: PackedStringArray = ["ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "SUB1", "FOR1", "FOR2", "VOL1", "VOL3", "VOL2", "CAV1", "CAV3", "CAV4", "SKY1", "SKY3", "SKY4", "SKY2", "SWP1", "SWP4", "SWP3", "SWP2", "SWP5", "DES1", "DES2", "DES3", "DES4", "DES5", "JUN1"]

## The build the data belongs to.
var version: GameVersionConfig
## The files the data comes from.
var source: GameDataSource
## The executable.
var exe: ExeImage
## The executable's tables with the inputs they were read from; [member
## AssetCatalog.tables] holds the same decoded tables.
var exe_tables: ExeTables
## The archive, open for reading.
var archive: MwdArchive
## True when a FrogLord standalone index was read and compared with the EXE.
var standalone_index_checked: bool = false

var _wads: Dictionary[int, WadFile] = {}
var _source_digests: Dictionary[String, String] = {}
var _wad_of_resource: Dictionary[int, int] = {}
var _models: Dictionary[int, MofFile] = {}


## Opens [param data_source] as build [param build]; name lists come from
## [param library] (the shipped FrogLord files by default). Check [member error].
static func open(data_source: GameDataSource, build: GameVersionConfig, library: FrogLordConfigLibrary = null) -> GameData:
	var data := GameData.new()
	data.source = data_source
	data.version = build
	data.hidden_parts = build.hidden_parts
	data.version_name = build.internal_name
	data.exe = ExeImage.create(data_source.get_exe_bytes(), build)
	if not data.exe.is_valid():
		data.error = data.exe.error
		return data
	data.mwi = MwiIndexReader.from_exe(data.exe.bytes, build)
	if not data.mwi.is_valid():
		data.error = "archive index: %s" % data.mwi.error
		return data
	var problems := PackedStringArray()
	data.archive = MwdArchive.open(data_source.get_mwd_path(), problems)
	if data.archive == null:
		data.error = "archive: %s" % ", ".join(problems)
		return data
	data.names = GameNameListsReader.load_for(build, library if library != null else FrogLordConfigLibrary.new())
	data.exe_tables = ExeTables.new(data.exe, data.mwi, data.names)
	data.tables = data.exe_tables.decoded
	data._check_standalone_index()
	return data


## The SHA-256 of the executable and archive this catalog reads, computed once.
func source_digests() -> Dictionary[String, String]:
	if _source_digests.is_empty() and source != null:
		_source_digests = {"exe": FileAccess.get_sha256(source.get_exe_path()), "mwd": FileAccess.get_sha256(source.get_mwd_path())}
	return _source_digests


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
			return WadFileReader.child_contents(wad, child)
	return PackedByteArray()


## The contents of the resource called [param file_name], or an empty array.
func read_resource_by_name(file_name: String, problems: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	var entry: MwiEntry = mwi.find_by_name(file_name)
	if entry == null:
		problems.append("no resource called %s" % file_name)
		return PackedByteArray()
	return read_resource(entry.index, problems)


## Decodes a regular map without retaining it after the caller releases it.
## Sky-land tiles have a separate format and use [method read_sky_land].
func read_map(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> MapFile:
	var bytes: PackedByteArray = read_resource(resource_id, problems)
	if bytes.is_empty():
		return null
	var map: MapFile = MapFileReader.read(bytes)
	if not map.error.is_empty():
		problems.append("map resource %d: %s" % [resource_id, map.error])
		return null
	return map


## Decodes the separately formatted sky-land tiles of the chosen detail.
func read_sky_land(low_poly: bool = false, problems: PackedStringArray = PackedStringArray()) -> SkyLandFile:
	var file_name: String = "SKY_LAND_WIN95.MAP" if low_poly else "SKY_LAND.MAP"
	var bytes: PackedByteArray = read_resource_by_name(file_name, problems)
	if bytes.is_empty():
		return null
	var sky: SkyLandFile = SkyLandReader.read(bytes)
	if not sky.error.is_empty():
		problems.append("%s: %s" % [file_name, sky.error])
		return null
	return sky


## Decodes the demo with resource id [param resource_id]; null, with the
## reason in [param problems], when it cannot be read.
func read_demo(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> SourceDemoFile:
	var entry: MwiEntry = mwi.get_entry(resource_id)
	var bytes: PackedByteArray = read_resource(resource_id, problems)
	if entry == null or bytes.is_empty():
		return null
	var demo: SourceDemoFile = SourceDemoFileReader.parse(bytes, entry.display_name())
	if not demo.is_valid():
		problems.append(demo.error)
		return null
	return demo


## Decodes the sound bank whose sample body has resource id [param
## resource_id], its header named by the executable's sound tables. Each
## present entry carries its samples as a mono 16-bit [AudioStreamWAV] at
## [constant SAMPLE_RATE], as the imported samples are. Returns null, with the
## reason in [param problems], when it cannot be read.
func read_sound_bank(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> SoundBankHeader:
	var header_id: int = -1
	var sounds: SoundTables = tables.sound_tables() if tables != null else null
	if sounds != null:
		for bank: Vector2i in sounds.banks:
			if bank.y == resource_id and bank.x >= 0:
				header_id = bank.x
	if header_id < 0:
		problems.append("no sound bank has body resource %d" % resource_id)
		return null
	var header_bytes: PackedByteArray = read_resource(header_id, problems)
	var body: PackedByteArray = read_resource(resource_id, problems)
	if header_bytes.is_empty() or body.is_empty():
		return null
	var header: SoundBankHeader = SoundBankReader.read(header_bytes, body.size(), mwi.get_entry(header_id).display_name())
	if not header.error.is_empty():
		return header
	for entry: SoundBankEntry in header.entries:
		if not entry.audio_present:
			continue
		var pcm: SoundBankPcm = SoundBankPcm.slice(entry, body)
		if not pcm.error.is_empty():
			header.error = pcm.error
			return header
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = SAMPLE_RATE
		stream.stereo = false
		stream.data = pcm.to_signed_16()
		entry.stream = stream
	return header


## Compares decoded archive entries, ignoring storage padding after their names.
static func index_difference(embedded: MwiIndex, standalone: MwiIndex) -> String:
	if not standalone.is_valid():
		return "standalone MWI is unreadable: %s" % standalone.error
	if embedded.entries.size() != standalone.entries.size():
		return "standalone MWI entry count differs from embedded index"
	for i: int in embedded.entries.size():
		var a: MwiEntry = embedded.entries[i]
		var b: MwiEntry = standalone.entries[i]
		if a.path != b.path or a.flags != b.flags or a.type_id != b.type_id \
				or a.sector_offset != b.sector_offset or a.packed_size != b.packed_size \
				or a.unpacked_size != b.unpacked_size or a.safety_margin_words != b.safety_margin_words:
			return "standalone MWI differs from embedded index at entry %d" % i
	return ""


func _check_standalone_index() -> void:
	if not source is FrogLordModSource:
		return
	var mod_source: FrogLordModSource = source as FrogLordModSource
	var path: String = mod_source.get_standalone_mwi_path()
	if path.is_empty():
		return
	standalone_index_checked = true
	var standalone: MwiIndex = MwiIndexReader.parse(FileAccess.get_file_as_bytes(path))
	var difference: String = index_difference(mwi, standalone)
	if not difference.is_empty():
		warnings.append(difference + "; using the EXE index")


## The resource id of a WAD holding resource [param resource_id], or -1.
func wad_holding(resource_id: int) -> int:
	return _wad_of_resource[resource_id] if _find_wad_holding(resource_id) != null else -1


## The texture bank with resource id [param resource_id], decoded; null (with
## the reason in [param problems]) when it cannot be read.
func read_texture_bank(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> VloFile:
	var bytes: PackedByteArray = read_resource(resource_id, problems)
	if bytes.is_empty():
		return null
	var vlo: VloFile = VloFileReader.parse(bytes)
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
	var wad: WadFile = WadFileReader.parse(archive.read(entry))
	if not wad.is_valid():
		return null
	_wads[wad_resource_id] = wad
	for child: WadFile.Child in wad.children:
		if not _wad_of_resource.has(child.resource_id):
			_wad_of_resource[child.resource_id] = wad_resource_id
	return wad


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
	if MofReader.needs_counterpart(bytes):
		counterpart = _complete_model_before(resource_id, problems)
	var model: MofFile = MofReader.parse(bytes, counterpart)
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
		if not MofReader.needs_counterpart(read_resource(id)):
			return id
	return -1


## The codes of the levels the game plays, in level-select order.
func playable_level_codes() -> PackedStringArray:
	return PLAYABLE_LEVEL_CODES.duplicate()


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
