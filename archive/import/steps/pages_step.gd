extends ImportStep
## Bakes the texture pages every map samples and the sky-land atlases.
##
## A set is the pair of banks a map loads: the GENERAL theme's bank, then its
## own theme's bank, each the multiplayer bank on a multiplayer level when the
## theme has one, in the map's detail. The raw phase composes the fourteen
## pages of each set with [MapTexturePages] (the runtime composition) and
## writes them as [code]page_NN.png[/code] under
## [method ImportContext.page_set_dir]; a set used by a sky level also gets
## [code]sky.png[/code], the atlas [MapMeshBuilder] builds from the pages the
## sky-land tiles use. The resources phase saves a [TexturePageSet] beside
## them as [code]page_set.tres[/code].

const SKY_THEME: int = 8
const SKY_LAND_FILES: Dictionary[bool, String] = {false: "SKY_LAND.MAP", true: "SKY_LAND_WIN95.MAP"}
const SKY_REMAP: String = "txl_sky_land"


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
			if map.general.theme == SKY_THEME and not sets[pair].has(low_poly):
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
	var library := TextureLibrary.new()
	library.add_bank(general, names[0])
	library.add_bank(theme, names[1])
	var composer := MapTexturePages.new()
	composer.configure(library)
	var pages: Array[Image] = []
	for page: int in TexturePageSet.PAGE_COUNT:
		var pixels: Image = composer.image_for_page(page)
		pages.append(pixels)
		if pixels == null:
			context.report("pages: %s page %d could not be composed" % [set_name, page])
			continue
		context.write_if_changed(_page_path(context, set_name, page), pixels.save_png_to_buffer())
	for diagnostic: String in composer.diagnostics:
		context.report("pages: %s: %s" % [set_name, diagnostic])
	if details.is_empty():
		return
	var order: PackedInt32Array = _sky_order(context, set_name, library, theme, details)
	var atlas: Image = Image.create(TexturePageSet.PAGE_SIZE, TexturePageSet.SKY_SLOT_HEIGHT * maxi(1, order.size()),
		false, Image.FORMAT_RGBA8)
	atlas.fill(Color.MAGENTA)
	for slot: int in order.size():
		var page: int = order[slot]
		if page < 0 or page >= pages.size() or pages[page] == null:
			continue
		var top: int = slot * TexturePageSet.SKY_SLOT_HEIGHT
		atlas.blit_rect(pages[page], Rect2i(0, 0, 256, 256), Vector2i(0, top + 1))
		atlas.blit_rect(pages[page], Rect2i(0, 0, 256, 1), Vector2i(0, top))
		atlas.blit_rect(pages[page], Rect2i(0, 255, 256, 1), Vector2i(0, top + 257))
	context.write_if_changed(_sky_path(context, set_name), atlas.save_png_to_buffer())


## The atlas page order: the page of each sky-land tile's image in first-seen
## order, -1 for a missing image. Both details must agree.
func _sky_order(context: ImportContext, set_name: String, library: TextureLibrary, theme: VloFile,
		details: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	var remap: TextureRemap = context.data.tables.remaps().find_by_name(SKY_REMAP)
	for low_poly: bool in details:
		var problems := PackedStringArray()
		var sky: SkyLandFile = context.data.read_sky_land(low_poly, problems)
		if sky == null or remap == null:
			context.report("pages: %s: no sky land or %s remap: %s" % [set_name, SKY_REMAP, "; ".join(problems)])
			continue
		var order := PackedInt32Array()
		for local_id: int in sky.texture_ids:
			var image: VloImage = library.image_for_id(remap.global_id(local_id), theme)
			var page: int = image.page() if image != null else -1
			if not order.has(page):
				order.append(page)
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
	for page: int in TexturePageSet.PAGE_COUNT:
		var path: String = _page_path(context, set_name, page)
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			context.report("pages: %s did not import" % path)
		page_set.pages.append(texture)
		page_set.colour_keyed.append(_keyed(general, page) or _keyed(theme, page))
	if not details.is_empty():
		var library := TextureLibrary.new()
		library.add_bank(general, names[0])
		library.add_bank(theme, names[1])
		page_set.sky_pages = _sky_order(context, set_name, library, theme, details)
		page_set.sky_atlas = load(_sky_path(context, set_name)) as Texture2D
		if page_set.sky_atlas == null:
			context.report("pages: %s did not import" % _sky_path(context, set_name))
	context.save_resource(page_set, context.page_set_dir(set_name).path_join("page_set.tres"))


## True when a valid upload whose own page is [param page] has the colour-key flag.
func _keyed(bank: VloFile, page: int) -> bool:
	for image: VloImage in bank.images:
		if image.page() != page or not image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT):
			continue
		if image.vram_x >= 0 and image.vram_y >= 0 and image.padded_width > 0 and image.padded_height > 0 \
				and image.vram_x + image.padded_width <= TexturePageSet.PAGE_SIZE \
				and image.vram_y + image.padded_height <= TexturePageSet.PAGE_COUNT * TexturePageSet.PAGE_SIZE:
			return true
	return false


func _page_path(context: ImportContext, set_name: String, page: int) -> String:
	return context.page_set_dir(set_name).path_join("page_%02d.png" % page)


func _sky_path(context: ImportContext, set_name: String) -> String:
	return context.page_set_dir(set_name).path_join("sky.png")
