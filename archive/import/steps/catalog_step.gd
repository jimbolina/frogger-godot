extends ImportStep
## Saves the [AssetIndex] at [method ImportContext.catalog_path], last.
##
## The index records the build and the SHA-256 of its executable and archive,
## the archive index, the asset file of every resource id that has one (found
## at the path conventions of [ImportContext] by checking which files exist),
## every WAD's children without their bytes, the counterpart of every
## incomplete model, the baked page sets under [code]textures/pages[/code]
## and the levels the game plays.

## Model record file names tried inside [method ImportContext.model_dir], after
## [code]<name>.res[/code] and [code]<name>.tres[/code].
const MODEL_FILES: PackedStringArray = ["model.res", "model.tres", "mof.res", "mof.tres"]


func step_name() -> String:
	return "catalog"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	var index := AssetIndex.new()
	index.resource_name = "%s assets" % context.data.version.internal_name
	index.version_name = context.data.version.internal_name
	index.exe_sha256 = FileAccess.get_sha256(context.data.source.get_exe_path())
	index.mwd_sha256 = FileAccess.get_sha256(context.data.source.get_mwd_path())
	if index.exe_sha256.is_empty() or index.mwd_sha256.is_empty():
		context.report("catalog: cannot hash the executable or archive")
	index.mwi = context.data.mwi
	index.tables_path = context.table_path("game_tables")
	index.names_path = context.table_path("names")
	for path: String in [index.tables_path, index.names_path]:
		if not FileAccess.file_exists(path):
			context.report("catalog: %s is missing" % path)
	for entry: MwiEntry in context.data.mwi.entries:
		var found: String = _asset_path(context, entry)
		if not found.is_empty():
			index.paths[entry.index] = found
		if entry.is_wad():
			_add_wad(context, index, entry)
		elif AssetCatalog.is_model_entry(entry) and MofFile.needs_counterpart(context.data.read_resource(entry.index)):
			index.counterparts[entry.index] = context.data.counterpart_of(entry.index)
	_add_page_sets(context, index)
	for row: MapBookEntry in context.data.tables.map_book().entries:
		if not row.is_dummy() and GameplaySetup.supports_level(row.level):
			index.playable_levels.append(row.code())
	ImportContext.number_sub_resources(index)
	context.save_resource(index, context.catalog_path())


func _asset_path(context: ImportContext, entry: MwiEntry) -> String:
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
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


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


func _add_page_sets(context: ImportContext, index: AssetIndex) -> void:
	var folder: String = context.assets_root.path_join("textures/pages")
	if not DirAccess.dir_exists_absolute(folder):
		return
	var set_names: PackedStringArray = DirAccess.get_directories_at(folder)
	set_names.sort()
	for set_name: String in set_names:
		var path: String = context.page_set_dir(set_name).path_join("page_set.tres")
		if FileAccess.file_exists(path):
			index.page_sets[set_name] = path
