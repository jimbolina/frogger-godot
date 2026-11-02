class_name ImportedAssets
extends AssetCatalog
## The [AssetCatalog] read from the committed resources under
## [code]res://assets[/code], written once by the importer.
##
## [method open] loads the [AssetIndex] ([code]catalog.tres[/code]), from the
## assets root or from a separate index root holding an overlay index whose
## paths point into either folder, then the executable tables and the name
## lists; every other record is loaded on
## request through Godot's resource cache, so a record asked for twice is the
## same object. Records are shared and must not be changed. The retail archive
## is not kept, so no raw resource bytes are available.
##
## The catalog draws from one [TextureSet]: the records keep their retail
## textures, and [method texture_of], [method texture_counterpart] and
## [method font] answer with the chosen set's files,
## falling back to the retail file (noted in [member problems]) when the set
## lacks one. A lettering image ([method TextureSet.lettering_path]) replaces
## its retail texture in every set.

## The hand-authored glowing-image table under the assets root.
const EMISSIVE_IMAGES_PATH: String = "rendering/emissive_images.tres"

## The asset index the catalog answers from.
var index: AssetIndex
## The folder the assets were opened from: fonts, lettering, the emissive
## table and texture sets are read from here.
var root: String = ""
## The folder the asset index was read from; [member root] unless
## [method open] was given another.
var index_root: String = ""
## The texture set the catalog draws from.
var textures: TextureSet = TextureSet.retail()
## Records that could not be loaded, one line each.
var problems: PackedStringArray = PackedStringArray()
var _counterparts: Dictionary[String, Texture2D] = {}
var _fonts: Dictionary[String, Font] = {}
var _emissive: EmissiveImageTable


## Opens the assets under [param assets_root], drawing from the texture set
## called [param texture_set_name] ("" for retail). The index is read from
## [param index_folder] when it is not empty, otherwise from
## [param assets_root]. Check [member AssetCatalog.error]; a set that is not
## installed falls back to retail with a line in [member AssetCatalog.warnings].
static func open(assets_root: String = "res://assets", texture_set_name: String = "",
		index_folder: String = "") -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.root = assets_root
	catalog.index_root = index_folder if not index_folder.is_empty() else assets_root
	catalog.textures = resolve_texture_set(assets_root, texture_set_name, catalog.warnings)
	var index_path: String = catalog.index_root.path_join("catalog.tres")
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


## The texture set called [param texture_set_name] when its images folder
## exists under [param assets_root]; otherwise the retail set, with the reason
## appended to [param warnings_out].
static func resolve_texture_set(assets_root: String, texture_set_name: String,
		warnings_out: PackedStringArray) -> TextureSet:
	var wanted: TextureSet = TextureSet.named(texture_set_name)
	if wanted == null:
		warnings_out.append("unknown texture set %s; drawing the retail set" % texture_set_name)
		return TextureSet.retail()
	if wanted.is_retail():
		return wanted
	var images: String = assets_root.path_join("textures").path_join(wanted.images_dir)
	if not DirAccess.dir_exists_absolute(images):
		warnings_out.append("texture set %s is not installed at %s; drawing the retail set" % [wanted.set_name, images])
		return TextureSet.retail()
	return wanted


## The texture set the catalog draws from.
func texture_set() -> TextureSet:
	return textures


## The texture of [param image] in the catalog's texture set, or null.
func texture_of(image: VloImage) -> Texture2D:
	return texture_counterpart(image.texture) if image != null else null


## The file the catalog draws for the retail [param texture]: its lettering
## image under the assets root when one exists, in every set; otherwise the
## texture set's file, which is the same texture for the retail set, a texture
## outside the retail folders, or a set file that is missing (noted once in
## [member problems]). The answer is cached per retail path.
func texture_counterpart(texture: Texture2D) -> Texture2D:
	if texture == null or texture.resource_path.is_empty():
		return texture
	var retail_path: String = texture.resource_path
	if _counterparts.has(retail_path):
		return _counterparts[retail_path]
	var lettering: String = TextureSet.lettering_path(retail_path)
	var found: Texture2D = _load(root.path_join(lettering)) as Texture2D if not lettering.is_empty() else null
	if found == null:
		found = _set_counterpart(texture)
	_counterparts[retail_path] = found
	return found


## The bitmap font called [param name] under [code]fonts/<set>/[/code], the
## retail set's font when the chosen set lacks it (noted once in
## [member problems]), or null with a line in [member problems] when neither
## exists. The answer is cached per name.
func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var path: String = root.path_join(textures.font_path(name))
	var found: Font = _load(path) as Font
	if found == null and not textures.is_retail():
		var retail_path: String = root.path_join(TextureSet.retail().font_path(name))
		problems.append("texture set %s has no %s; drawing %s" % [textures.set_name, path, retail_path])
		path = retail_path
		found = _load(path) as Font
	if found == null:
		problems.append("no font %s at %s" % [name, path])
	_fonts[name] = found
	return found


func _set_counterpart(texture: Texture2D) -> Texture2D:
	var retail_path: String = texture.resource_path
	var path: String = textures.counterpart_path(retail_path)
	if path == retail_path:
		return texture
	var found: Texture2D = _load(path) as Texture2D
	if found == null:
		problems.append("texture set %s has no %s; drawing %s" % [textures.set_name, path, retail_path])
		return texture
	return found


## The glowing-image table at [constant EMISSIVE_IMAGES_PATH], loaded once;
## an empty table, with a line in [member problems], when it is missing.
func emissive_images() -> EmissiveImageTable:
	if _emissive != null:
		return _emissive
	var path: String = root.path_join(EMISSIVE_IMAGES_PATH)
	_emissive = _load(path) as EmissiveImageTable
	if _emissive == null:
		problems.append("no emissive image table at %s" % path)
		_emissive = EmissiveImageTable.new()
	return _emissive


## One line naming the source the assets were imported from, for example
## [code]retail FROGGER.EXE + FROGPSX.MWD[/code] or
## [code]FrogLord mod modded_FROGGER.EXE + modded_FROGPSX.MWD (FrogLord 12, base pc-retail-v3.0e)[/code],
## followed by the root an overlay index falls back to; "" without an index.
func source_summary() -> String:
	if index == null:
		return ""
	var line: String = index.source_kind
	if not index.source_exe_name.is_empty() or not index.source_mwd_name.is_empty():
		line += " %s + %s" % [index.source_exe_name, index.source_mwd_name]
	var origin := PackedStringArray()
	if index.froglord_version >= 0:
		origin.append("FrogLord %d" % index.froglord_version)
	if not index.trailer_build.is_empty():
		origin.append("base %s" % index.trailer_build)
	if not origin.is_empty():
		line += " (%s)" % ", ".join(origin)
	if not index.fallback_root.is_empty():
		line += " over %s" % index.fallback_root
	return line


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
