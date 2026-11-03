extends AssetTest
## Every lettering tile the catalog composites at runtime from its committed
## mask and the imported retail images (LetteringTile) is the tile
## tools/make_lettering.py --composite draws from the same import, generated
## by tools/run_tests into the folder [constant AssetTest.GENERATED_VARIABLE]
## names. The generator measures its geometry and colours from the retail
## images itself, so the layout file and the masks are checked too. Pillow may
## round a few supersamples differently on another CPU, so a tile matches when
## no channel differs by more than [constant RASTER_STEP] and at most
## [constant RASTER_PIXELS] pixels differ at all, as the generator's own check
## allows.

const FOLDER: String = "lettering"
const TABLE_PATH: String = "res://content/fonts/angular/lettering.tsv"
const IMAGES: String = "res://assets/textures/images"
const ID_COLUMN: int = 0
const BACKGROUND_COLUMN: int = 5
const TRANSPARENT: String = "transparent"
const TILE_COUNT: int = 49
const RASTER_STEP: int = 16
const RASTER_PIXELS: int = 16


func _tile_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for line: String in FileAccess.get_file_as_string(TABLE_PATH).split("\n", false):
		var row: PackedStringArray = line.split("\t")
		if not line.begins_with("#") and row.size() > BACKGROUND_COLUMN and row[BACKGROUND_COLUMN] != TRANSPARENT:
			ids.append(row[ID_COLUMN].to_int())
	return ids


func _differences(actual: Image, expected: Image) -> Vector2i:
	var left: PackedByteArray = actual.get_data()
	var right: PackedByteArray = expected.get_data()
	var pixels: int = 0
	var largest: int = 0
	for at: int in range(0, left.size(), 4):
		var differs: bool = false
		for channel: int in 4:
			var difference: int = absi(left[at + channel] - right[at + channel])
			largest = maxi(largest, difference)
			differs = differs or difference != 0
		if differs:
			pixels += 1
	return Vector2i(pixels, largest)


func test_the_runtime_tiles_are_the_generated_tiles() -> void:
	var folder: String = generated_folder(FOLDER)
	if folder.is_empty():
		return
	var ids: PackedInt32Array = _tile_ids()
	assert_eq(ids.size(), TILE_COUNT, "lettering.tsv has the tile rows")
	var assets: ImportedAssets = ImportedAssets.open(ASSETS)
	var mismatches := PackedStringArray()
	var exact: int = 0
	for texture_id: int in ids:
		var retail: Texture2D = load(IMAGES.path_join("t%04d.png" % texture_id)) as Texture2D
		var drawn: Texture2D = assets.texture_counterpart(retail) if retail != null else null
		var expected: Image = Image.load_from_file(folder.path_join("t%04d.png" % texture_id))
		if drawn == null or drawn == retail or expected == null:
			mismatches.append("t%04d: no composited tile or no generated tile" % texture_id)
			continue
		var actual: Image = drawn.get_image()
		actual.clear_mipmaps()
		actual.convert(Image.FORMAT_RGBA8)
		expected.convert(Image.FORMAT_RGBA8)
		if actual.get_size() != expected.get_size():
			mismatches.append("t%04d: %s, generated %s" % [texture_id, actual.get_size(), expected.get_size()])
			continue
		var found: Vector2i = _differences(actual, expected)
		if found.x == 0:
			exact += 1
		elif found.y > RASTER_STEP or found.x > RASTER_PIXELS:
			mismatches.append("t%04d: %d pixels differ, by up to %d" % [texture_id, found.x, found.y])
	assert_eq(assets.problems, PackedStringArray(), "\n".join(assets.problems))
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d tiles match the generator, %d exactly" % [ids.size(), exact])
	gut.p("%d of %d lettering tiles match the generator exactly" % [exact, ids.size()])
