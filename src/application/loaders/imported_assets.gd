class_name ImportedAssets
extends AssetCatalog
## The [AssetCatalog] read from imported resources: the developer's local
## import [constant COMMITTED_ROOT], or a folder the player's own copy was
## imported into ([AssetLocation]).
##
## [method open] loads the [AssetIndex] ([code]catalog.tres[/code]), from the
## assets root or from a separate index root holding an overlay index whose
## paths point into either folder, then the executable tables and the name
## lists; every other record is loaded on
## request through Godot's resource cache, so a record asked for twice is the
## same object. Records are shared and must not be changed. The retail archive
## is not kept, so no raw resource bytes are available.
##
## Records, models, maps, sounds and music come from the base
## [member root]. The angular font, the lettering and the emissive table are
## the port's own work and come from [member shippable_root],
## [constant SHIPPABLE_ROOT] whatever the base root. Nothing there holds a
## retail pixel: [code]newfont[/code] is always built from texture 310
## ([NewfontFont]), and the lettering tiles from their masks and the base
## root's retail images ([LetteringTile]).
##
## The catalog draws from one [TextureSet]: the records keep their retail
## textures, and [method texture_of], [method texture_counterpart] and
## [method font] answer with the image drawn in their place. A texture pack
## ([TexturePackReader]) wins where it supplies the texture and its image is
## accepted; otherwise the lettering replaces its retail texture (a
## transparent image, [method TextureSet.lettering_path], or a tile
## composited from its mask, [method TextureSet.lettering_mask_path]);
## otherwise the retail texture is drawn. A pack image that is rejected, or a
## tile that cannot be composited, is noted in [member problems] and the
## texture falls back as if the pack or the lettering lacked it. A pack that
## redraws texture 310 is drawn by the [code]newfont[/code] font too.

## The hand-authored glowing-image table under the shippable root.
const EMISSIVE_IMAGES_PATH: String = "rendering/emissive_images.tres"
## The port's own content: the angular font, the lettering and the emissive
## table, shipped in every build.
const SHIPPABLE_ROOT: String = "res://content"
## The developer's local import of the retail copy, the default base root.
const COMMITTED_ROOT: String = "res://assets"
## The asset index file inside an assets or index root.
const INDEX_FILE: String = "catalog.tres"

## The asset index the catalog answers from.
var index: AssetIndex
## The base folder the assets were opened from: records and models are
## read from here, and an index of its own points into it.
var root: String = ""
## The folder the angular font, the lettering and the emissive table are read from.
var shippable_root: String = SHIPPABLE_ROOT
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
var _tiles: LetteringTile


## Opens the assets under [param assets_root], drawing the texture pack
## called [param texture_pack_name] ("" for none) found in [param pack_folders].
## The index is read from [param index_folder] when it is not empty, otherwise
## from [param assets_root]; the angular font, lettering and the emissive
## table from [param shippable_folder]. Check [member AssetCatalog.error]; a
## pack that is not installed draws the original textures with a line in
## [member AssetCatalog.warnings].
static func open(assets_root: String = COMMITTED_ROOT, texture_pack_name: String = "",
		index_folder: String = "", shippable_folder: String = SHIPPABLE_ROOT,
		pack_folders: PackedStringArray = TexturePackReader.search_folders()) -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.root = assets_root
	catalog.shippable_root = shippable_folder
	catalog.index_root = index_folder if not index_folder.is_empty() else assets_root
	var index_path: String = catalog.index_root.path_join(INDEX_FILE)
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
	catalog.textures = catalog.resolve_texture_pack(texture_pack_name, pack_folders)
	return catalog


## True when [param folder] holds an asset index ([constant INDEX_FILE]).
static func has_index(folder: String) -> bool:
	return not folder.is_empty() and ResourceLoader.exists(folder.path_join(INDEX_FILE))


## The texture set drawing the pack called [param texture_pack_name] from
## [param pack_folders], its files resolved against the catalog's image
## names; the original textures for "". A pack that is not installed or is
## not a valid pack gives the original textures; that, a pack drawn for
## another build than [member AssetCatalog.version_name] and each pack file
## naming no texture add a line to [member AssetCatalog.warnings].
func resolve_texture_pack(texture_pack_name: String,
		pack_folders: PackedStringArray = TexturePackReader.search_folders()) -> TextureSet:
	if texture_pack_name.is_empty():
		return TextureSet.retail()
	var notes := PackedStringArray()
	var pack: TexturePack = TexturePackReader.find(texture_pack_name, pack_folders, notes)
	warnings.append_array(notes)
	if pack == null:
		var reason: String = "is not installed in %s" % ", ".join(pack_folders) if notes.is_empty() else "cannot be used"
		warnings.append("texture pack %s %s; drawing the original textures" % [texture_pack_name, reason])
		return TextureSet.retail()
	if pack.base_build != version_name:
		warnings.append("texture pack %s was drawn for %s, not %s; its images may not match"
			% [pack.pack_name, pack.base_build, version_name])
	notes.clear()
	var image_names: NameBank = names.images if names != null else null
	var pack_sources: Dictionary[int, String] = TexturePackReader.sources(pack, image_names, notes)
	warnings.append_array(notes)
	return TextureSet.of_pack(pack, pack_sources)


## The texture set the catalog draws from.
func texture_set() -> TextureSet:
	return textures


## The texture of [param image] in the catalog's texture set, or null.
func texture_of(image: VloImage) -> Texture2D:
	return texture_counterpart(image.texture) if image != null else null


## The texture the catalog draws for the retail [param texture]: the
## texture pack's image when the pack supplies the texture and the image is
## accepted, else its lettering under the shippable root when there is one
## (a transparent image, or a tile composited from its mask and the base
## root's retail images), else [param texture] itself (also for a texture
## outside the retail images folder). A rejected pack image is noted once in
## [member problems] and pushed as a warning, so it shows in the log; a tile
## that cannot be composited is noted in [member problems].
## The answer is cached per retail path.
func texture_counterpart(texture: Texture2D) -> Texture2D:
	if texture == null or texture.resource_path.is_empty():
		return texture
	var retail_path: String = texture.resource_path
	if _counterparts.has(retail_path):
		return _counterparts[retail_path]
	var found: Texture2D = _pack_texture(texture)
	if found == null:
		found = _lettering(retail_path)
	if found == null:
		found = texture
	_counterparts[retail_path] = found
	return found


## The font called [param name], or null with a line in [member problems]
## when it is missing: [code]newfont[/code] is built by [NewfontFont] from the
## texture pack's texture 310 when the pack redraws it and its image is
## accepted, else from the base root's ([method base_image]); a vector font
## ([constant TextureSet.VECTOR_FONTS]) is read from the shippable root. The
## answer is cached per name.
func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var found: Font = null
	if name == NewfontPage.FONT_NAME:
		found = _built_newfont()
		if found == null:
			problems.append("no font %s: no texture %d under %s to build it from"
				% [name, NewfontPage.TEXTURE_ID, root])
	else:
		var path: String = TextureSet.font_path(name)
		found = _load(shippable_root.path_join(path)) as Font if not path.is_empty() else null
		if found == null:
			problems.append("no font %s under %s" % [name, shippable_root])
	_fonts[name] = found
	return found


## The base root's own image of texture [param texture_id]
## ([code]textures/images/tNNNN.png[/code], or [code].res[/code] in an import
## made at runtime), or null when there is none.
func base_image(texture_id: int) -> Image:
	for extension: String in ["png", "res"]:
		var path: String = root.path_join("textures/%s/t%04d.%s" % [TextureSet.IMAGES_DIR, texture_id, extension])
		var texture: Texture2D = _load(path) as Texture2D
		if texture != null:
			return texture.get_image()
	return null


func _lettering(retail_path: String) -> Texture2D:
	var image_path: String = TextureSet.lettering_path(retail_path)
	if image_path.is_empty():
		return null
	var image: Texture2D = _load(shippable_root.path_join(image_path)) as Texture2D
	if image != null:
		return image
	for background: String in LetteringTile.BACKGROUNDS:
		var mask: Image = _load(shippable_root.path_join(TextureSet.lettering_mask_path(retail_path, background))) as Image
		if mask == null:
			continue
		if _tiles == null:
			_tiles = LetteringTile.new()
		var sources: Dictionary[int, Image] = {}
		if not _tiles.has_background(background):
			for source_id: int in LetteringTile.sources_of(background):
				var source: Image = base_image(source_id)
				if source != null:
					sources[source_id] = source
		var texture_id: int = TextureSet.texture_id_of(retail_path)
		var reasons := PackedStringArray()
		var tile: ImageTexture = _tiles.build(mask, background, texture_id, base_image(texture_id), sources, reasons)
		for reason: String in reasons:
			problems.append("lettering tile %d: %s; drawing the retail texture" % [texture_id, reason])
		return tile
	return null


func _pack_texture(texture: Texture2D) -> Texture2D:
	var texture_id: int = TextureSet.texture_id_of(texture.resource_path)
	if texture_id < 0 or not textures.has_source(texture_id):
		return null
	var rejected := PackedStringArray()
	var padded_size := Vector2i(texture.get_size())
	var loaded: Texture2D = TexturePackReader.load_texture(textures.source_of(texture_id), padded_size, rejected)
	if loaded == null:
		_reject(texture_id, rejected)
		return null
	@warning_ignore("integer_division")
	var scale: int = loaded.get_width() / padded_size.x
	textures.accept(texture_id, scale)
	return loaded


func _built_newfont() -> Font:
	var image: Image = _pack_newfont_image()
	if image == null:
		image = base_image(NewfontPage.TEXTURE_ID)
	return NewfontFont.build(NewfontPage.build(image))


func _pack_newfont_image() -> Image:
	var texture_id: int = NewfontPage.TEXTURE_ID
	if not textures.has_source(texture_id):
		return null
	var rejected := PackedStringArray()
	var image: Image = TexturePackReader.load_image(textures.source_of(texture_id), NewfontPage.RETAIL_SIZE, rejected)
	if image == null:
		_reject(texture_id, rejected)
	return image


func _reject(texture_id: int, reasons: PackedStringArray) -> void:
	for reason: String in reasons:
		var line: String = "texture pack %s: %s; drawing texture %d without the pack" % [textures.pack_name(), reason, texture_id]
		problems.append(line)
		push_warning(line)
	textures.reject(texture_id)


## The glowing-image table at [constant EMISSIVE_IMAGES_PATH] under the
## shippable root, loaded once;
## an empty table, with a line in [member problems], when it is missing.
func emissive_images() -> EmissiveImageTable:
	if _emissive != null:
		return _emissive
	var path: String = shippable_root.path_join(EMISSIVE_IMAGES_PATH)
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
