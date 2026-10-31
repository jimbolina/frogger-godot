extends ImportStep
## Bakes the texture pages every map samples and the sky-land atlases.
##
## A set is the pair of banks a map loads: the GENERAL theme's bank, then its
## own theme's bank, each the multiplayer bank on a multiplayer level when the
## theme has one, in the map's detail. The raw phase composes the fourteen
## pages of each set with [VramPages] and writes them as
## [code]page_NN.png[/code] under [method ImportContext.page_set_dir]; a set
## used by a sky level also gets [code]sky.png[/code], the atlas of the pages
## the sky-land tiles use. The resources phase saves a [TexturePageSet]
## beside them as [code]page_set.tres[/code].



func step_name() -> String:
	return "pages"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RAW, PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	var sets: Dictionary[Vector2i, Array] = _sets(context)
	var pairs: Array[Vector2i] = []
	for pair: Vector2i in sets:
		pairs.append(pair)
	pairs.sort()
	for pair: Vector2i in pairs:
		var general: VloFile = _bank(context, pair.x)
		var theme: VloFile = _bank(context, pair.y)
		if general == null or theme == null:
			continue
		var names := PackedStringArray([context.entry_name(pair.x), context.entry_name(pair.y)])
		var set_name: String = TexturePageSet.name_for(names)
		var details: Array = sets[pair]
		if phase == PHASE_RAW:
			_write_set(context, set_name, names, general, theme, details)
		else:
			_save_set(context, set_name, names, general, theme, details)


## Every set the map book uses, by (GENERAL bank id, theme bank id), with the
## details (true for low poly) of the sky levels that use it.
func _sets(context: ImportContext) -> Dictionary[Vector2i, Array]:
	var sets: Dictionary[Vector2i, Array] = {}
	var general: ThemeBookEntry = context.data.theme_book_entry(FroggerIds.THEME_GENERAL)
	for row: MapBookEntry in context.data.tables.map_book().entries:
		if row.is_dummy():
			continue
		for low_poly: bool in [false, true]:
			var map_id: int = row.map_id(low_poly)
			if map_id <= 0:
				continue
			var problems := PackedStringArray()
			var map: MapFile = context.data.read_map(map_id, problems)
			if map == null:
				context.report("pages: level %s: %s" % [row.code(), "; ".join(problems)])
				continue
			var theme: ThemeBookEntry = context.data.theme_book_entry(map.general.theme)
			if theme == null or general == null:
				context.report("pages: level %s has no theme %d" % [row.code(), map.general.theme])
				continue
			var multiplayer: bool = AssetCatalog.is_multiplayer_level(row.level)
			var pair := Vector2i(_bank_id(general, multiplayer, low_poly), _bank_id(theme, multiplayer, low_poly))
			if not sets.has(pair):
				sets[pair] = []
			if map.general.theme == GameData.SKY_THEME and not sets[pair].has(low_poly):
				sets[pair].append(low_poly)
	return sets


func _bank_id(theme: ThemeBookEntry, multiplayer: bool, low_poly: bool) -> int:
	var id: int = theme.vlo_id(multiplayer, low_poly)
	return id if id != 0 else theme.vlo_id(false, low_poly)


func _bank(context: ImportContext, resource_id: int) -> VloFile:
	var bank_name: String = context.entry_name(resource_id)
	if context.banks.has(bank_name):
		return context.banks[bank_name]
	var problems := PackedStringArray()
	var bank: VloFile = context.data.read_texture_bank(resource_id, problems)
	if bank == null:
		context.report("pages: texture bank %s: %s" % [bank_name, "; ".join(problems)])
		return null
	context.banks[bank_name] = bank
	return bank


func _write_set(context: ImportContext, set_name: String, names: PackedStringArray, general: VloFile,
		theme: VloFile, details: Array) -> void:
	var diagnostics := PackedStringArray()
	var banks: Array[VloFile] = [general, theme]
	var pages: Array[Image] = VramPages.compose_pages(banks, diagnostics)
	for page: int in TexturePageSet.PAGE_COUNT:
		if pages[page] == null:
			context.report("pages: %s page %d could not be composed" % [set_name, page])
			continue
		context.write_if_changed(_page_path(context, set_name, page), pages[page].save_png_to_buffer())
	for diagnostic: String in diagnostics:
		context.report("pages: %s: %s" % [set_name, diagnostic])
	if details.is_empty():
		return
	var order: PackedInt32Array = _sky_order(context, set_name, general, theme, details)
	context.write_if_changed(_sky_path(context, set_name), VramPages.sky_atlas(pages, order).save_png_to_buffer())


## The atlas page order of [VramPages.sky_order]; both details must agree.
func _sky_order(context: ImportContext, set_name: String, general: VloFile, theme: VloFile,
		details: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	var remap: TextureRemap = context.data.tables.remaps().find_by_name(GameData.SKY_REMAP)
	for low_poly: bool in details:
		var problems := PackedStringArray()
		var sky: SkyLandFile = context.data.read_sky_land(low_poly, problems)
		if sky == null or remap == null:
			context.report("pages: %s: no sky land or %s remap: %s" % [set_name, GameData.SKY_REMAP, "; ".join(problems)])
			continue
		var order: PackedInt32Array = VramPages.sky_order(general, theme, sky, remap)
		if not result.is_empty() and result != order:
			context.report("pages: %s: the sky-land files give different atlases" % set_name)
		result = order
	return result


func _save_set(context: ImportContext, set_name: String, names: PackedStringArray, general: VloFile,
		theme: VloFile, details: Array) -> void:
	var page_set := TexturePageSet.new()
	page_set.resource_name = set_name
	page_set.set_name = set_name
	page_set.bank_names = names
	var banks: Array[VloFile] = [general, theme]
	for page: int in TexturePageSet.PAGE_COUNT:
		var path: String = _page_path(context, set_name, page)
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			context.report("pages: %s did not import" % path)
		page_set.pages.append(texture)
		page_set.colour_keyed.append(VramPages.colour_keyed(banks, page))
	if not details.is_empty():
		page_set.sky_pages = _sky_order(context, set_name, general, theme, details)
		page_set.sky_atlas = load(_sky_path(context, set_name)) as Texture2D
		if page_set.sky_atlas == null:
			context.report("pages: %s did not import" % _sky_path(context, set_name))
	context.save_resource(page_set, context.page_set_dir(set_name).path_join("page_set.tres"))


func _page_path(context: ImportContext, set_name: String, page: int) -> String:
	return context.page_set_dir(set_name).path_join("page_%02d.png" % page)


func _sky_path(context: ImportContext, set_name: String) -> String:
	return context.page_set_dir(set_name).path_join("sky.png")
