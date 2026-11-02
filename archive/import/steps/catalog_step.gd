extends ImportStep
## Saves the [AssetIndex] at [method ImportContext.catalog_path], last.
##
## The index records the build, the kind of source with its file names (and
## for a FrogLord save the build and FrogLord version its trailer names), the
## SHA-256 of its executable and archive, the archive index, the asset file of
## every resource id that has one (found at the path conventions of
## [ImportContext] by checking which files exist, under
## [member ImportContext.assets_root] first and then under
## [member ImportContext.fallback_root]), every WAD's children without their
## bytes, the counterpart of every incomplete model and the levels the game
## plays.
##
## A complete run without a fallback root notes, as [code]stale <path>[/code],
## every file in the folders the steps own that the run neither wrote nor found
## unchanged. Nothing is deleted.

## Model record file names tried inside [method ImportContext.model_dir], after
## [code]<name>.res[/code] and [code]<name>.tres[/code].
const MODEL_FILES: PackedStringArray = ["model.res", "model.tres", "mof.res", "mof.tres"]
## The folders below the assets root whose every file a complete run writes.
const OWNED_FOLDERS: PackedStringArray = ["textures/banks", "textures/images", "maps", "demos", "tables",
	"models", "audio/sfx"]
## Files Godot writes beside imported ones, which the steps never touch.
const SIDE_FILE_SUFFIXES: PackedStringArray = [".import", ".uid"]


func step_name() -> String:
	return "catalog"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	var index := AssetIndex.new()
	index.resource_name = "%s assets" % context.data.version_name
	index.version_name = context.data.version_name
	index.hidden_parts = context.data.hidden_parts
	index.exe_sha256 = FileAccess.get_sha256(context.data.source.get_exe_path())
	index.mwd_sha256 = FileAccess.get_sha256(context.data.source.get_mwd_path())
	if index.exe_sha256.is_empty() or index.mwd_sha256.is_empty():
		context.report("catalog: cannot hash the executable or archive")
	_describe_source(context, index)
	index.mwi = context.data.mwi
	index.tables_path = _existing(context, context.table_path("game_tables"))
	index.names_path = _existing(context, context.table_path("names"))
	for path: String in [index.tables_path, index.names_path]:
		if not FileAccess.file_exists(path):
			context.report("catalog: %s is missing" % path)
	for entry: MwiEntry in context.data.mwi.entries:
		var found: String = _asset_path(context, entry)
		if not found.is_empty():
			index.paths[entry.index] = found
		if entry.is_wad():
			_add_wad(context, index, entry)
		elif AssetCatalog.is_model_entry(entry) and MofReader.needs_counterpart(context.data.read_resource(entry.index)):
			index.counterparts[entry.index] = context.data.counterpart_of(entry.index)
	for row: MapBookEntry in context.data.tables.map_book().entries:
		if not row.is_dummy() and context.data.is_playable_level(row.level):
			index.playable_levels.append(row.code())
	ImportContext.number_sub_resources(index)
	_note_stale(context)
	context.save_resource(index, context.catalog_path())


func _describe_source(context: ImportContext, index: AssetIndex) -> void:
	var source: GameDataSource = context.data.source
	index.source_exe_name = source.exe_file_name()
	index.source_mwd_name = source.mwd_file_name()
	index.fallback_root = context.fallback_root
	if source is FrogLordModSource:
		index.source_kind = AssetIndex.SOURCE_FROGLORD_MOD
		var trailer: FrogLordExeTrailer = (source as FrogLordModSource).get_trailer()
		if trailer != null and trailer.error.is_empty():
			index.trailer_build = trailer.game_version
			index.froglord_version = trailer.froglord_version
	elif source is RetailDirSource:
		index.source_kind = AssetIndex.SOURCE_RETAIL
	else:
		index.source_kind = source.kind_name()


func _existing(context: ImportContext, path: String) -> String:
	var found: String = _first_existing(context, PackedStringArray([context.relative_to_assets(path)]))
	return found if not found.is_empty() else path


func _first_existing(context: ImportContext, relative_paths: PackedStringArray) -> String:
	var roots := PackedStringArray([context.assets_root])
	if not context.fallback_root.is_empty():
		roots.append(context.fallback_root)
	for root: String in roots:
		for relative: String in relative_paths:
			var candidate: String = root.path_join(relative)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


func _note_stale(context: ImportContext) -> void:
	if not context.fallback_root.is_empty():
		return
	if not context.complete_phases.has(PHASE_RAW) or not context.complete_phases.has(PHASE_RESOURCES):
		return
	var touched: Dictionary[String, bool] = {}
	for path: String in context.touched:
		touched[path.simplify_path()] = true
	for folder: String in OWNED_FOLDERS:
		for path: String in _files_below(context.assets_root.path_join(folder)):
			if not touched.has(path.simplify_path()):
				context.note("stale %s" % path)


func _files_below(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for child: String in DirAccess.get_directories_at(folder):
		found.append_array(_files_below(folder.path_join(child)))
	for file_name: String in DirAccess.get_files_at(folder):
		if not _is_side_file(file_name):
			found.append(folder.path_join(file_name))
	return found


func _is_side_file(file_name: String) -> bool:
	for suffix: String in SIDE_FILE_SUFFIXES:
		if file_name.ends_with(suffix):
			return true
	return false


func _asset_path(context: ImportContext, entry: MwiEntry) -> String:
	return _first_existing(context, _relative_candidates(context, entry))


func _relative_candidates(context: ImportContext, entry: MwiEntry) -> PackedStringArray:
	var entry_name: String = context.entry_name(entry.index)
	var file_name: String = entry.display_name().to_upper()
	var candidates := PackedStringArray()
	if file_name.ends_with(".VLO") or entry.type_id == 1:
		candidates.append(context.bank_resource_path(entry_name))
	if file_name.ends_with(".MAP"):
		candidates.append(context.map_path(entry_name))
	if file_name.ends_with(".DAT"):
		candidates.append(context.demo_path(entry_name))
	if AssetCatalog.is_model_entry(entry):
		var folder: String = context.model_dir(entry_name)
		candidates.append(folder.path_join(entry_name + ".res"))
		candidates.append(folder.path_join(entry_name + ".tres"))
		for model_file: String in MODEL_FILES:
			candidates.append(folder.path_join(model_file))
	candidates.append(context.sound_bank_path(entry_name))
	var relative := PackedStringArray()
	for candidate: String in candidates:
		relative.append(context.relative_to_assets(candidate))
	return relative


func _add_wad(context: ImportContext, index: AssetIndex, entry: MwiEntry) -> void:
	var wad: WadFile = context.data.read_wad(entry.index)
	if wad == null:
		context.report("catalog: WAD %s cannot be read" % entry.display_name())
		return
	var listed := WadFile.new()
	listed.resource_name = entry.display_name()
	for child: WadChild in wad.children:
		var copy := WadChild.new()
		copy.resource_id = child.resource_id
		copy.type_id = child.type_id
		copy.file_count = child.file_count
		copy.is_packed = child.is_packed
		listed.children.append(copy)
	index.wads[entry.index] = listed

