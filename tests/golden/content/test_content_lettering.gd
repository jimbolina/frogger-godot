extends GutTest
## The lettering (written by tools/make_lettering.py from
## content/fonts/angular/lettering.tsv) replaces its retail textures: every
## transparent row has one image content/lettering/tNNNN.png, imported with
## mipmaps, and every tile row one grey mask
## content/lettering/masks/<background>/tNNNN.png, imported as an exact
## [Image], each at exactly eight times the retail padded size recorded in
## vlo_images.tsv. No file lacks a row, and the angular font holds every
## character the table writes. The tables are read with Godot's own file
## access, independent of the generator; the pixels themselves are the
## generator's --check, and what the catalog draws the imported suite's
## test_asset_lettering.gd and test_asset_lettering_tiles.gd.

const TABLE_PATH: String = "res://content/fonts/angular/lettering.tsv"
const FONT_PATH: String = "res://content/fonts/angular/frogger_angular.ttf"
const LETTERING: String = "res://content/lettering"
const TRANSPARENT: String = "transparent"
const SCALE: int = 8
const COLUMNS: int = 7
const ID_COLUMN: int = 0
const TEXT_COLUMN: int = 3
const BACKGROUND_COLUMN: int = 5
const VLO_TEXTURE_ID: int = 2
const VLO_PADDED_WIDTH: int = 5
const VLO_PADDED_HEIGHT: int = 6
const LINE_BREAK: String = "|"


func _rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(TABLE_PATH).split("\n", false):
		if not line.begins_with("#"):
			rows.append(line.split("\t"))
	return rows


func _file(texture_id: int) -> String:
	return "t%04d.png" % texture_id


func _path(row: PackedStringArray) -> String:
	var file: String = _file(row[ID_COLUMN].to_int())
	if row[BACKGROUND_COLUMN] == TRANSPARENT:
		return LETTERING.path_join(file)
	return LETTERING.path_join(TextureSet.MASKS_DIR).path_join(row[BACKGROUND_COLUMN]).path_join(file)


func _padded_sizes() -> Dictionary[int, Vector2i]:
	var sizes: Dictionary[int, Vector2i] = {}
	for row: PackedStringArray in GoldenFiles.rows("vlo_images.tsv"):
		sizes[row[VLO_TEXTURE_ID].to_int()] = Vector2i(row[VLO_PADDED_WIDTH].to_int(), row[VLO_PADDED_HEIGHT].to_int())
	return sizes


func _report(mismatches: PackedStringArray, what: String) -> void:
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, what)


func test_the_table_is_well_formed() -> void:
	var rows: Array[PackedStringArray] = _rows()
	assert_gt(rows.size(), 0, "%s has rows" % TABLE_PATH)
	var seen: Dictionary[int, bool] = {}
	var mismatches := PackedStringArray()
	for row: PackedStringArray in rows:
		if row.size() != COLUMNS or not row[ID_COLUMN].is_valid_int():
			mismatches.append("malformed row %s" % "\t".join(row))
			continue
		var texture_id: int = row[ID_COLUMN].to_int()
		if seen.has(texture_id):
			mismatches.append("t%04d appears twice" % texture_id)
		seen[texture_id] = true
	_report(mismatches, "%d lettering rows are well formed" % rows.size())


func test_every_row_has_an_image_or_mask_eight_times_its_padded_size() -> void:
	var sizes: Dictionary[int, Vector2i] = _padded_sizes()
	var mismatches := PackedStringArray()
	var rows: Array[PackedStringArray] = _rows()
	for row: PackedStringArray in rows:
		var texture_id: int = row[ID_COLUMN].to_int()
		var path: String = _path(row)
		if not sizes.has(texture_id):
			mismatches.append("t%04d is not a retail texture in vlo_images.tsv" % texture_id)
			continue
		if not FileAccess.file_exists(path):
			mismatches.append("t%04d has no lettering image at %s" % [texture_id, path])
			continue
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) != OK:
			mismatches.append("t%04d: %s does not load" % [texture_id, path])
			continue
		var wanted: Vector2i = sizes[texture_id] * SCALE
		if image.get_size() != wanted:
			mismatches.append("t%04d: %s is %s, expected %s" % [texture_id, path, image.get_size(), wanted])
	_report(mismatches, "%d lettering images are %d times their padded size" % [rows.size(), SCALE])


func test_images_import_with_mipmaps_and_masks_as_exact_images() -> void:
	var mismatches := PackedStringArray()
	var rows: Array[PackedStringArray] = _rows()
	for row: PackedStringArray in rows:
		var texture_id: int = row[ID_COLUMN].to_int()
		var path: String = _path(row)
		var loaded: Resource = load(path) if ResourceLoader.exists(path) else null
		if row[BACKGROUND_COLUMN] != TRANSPARENT:
			var mask: Image = loaded as Image
			var raw: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
			if mask == null:
				mismatches.append("t%04d: %s does not import as an image" % [texture_id, path])
			elif mask.get_format() != Image.FORMAT_L8 or raw == null or mask.get_data() != raw.get_data():
				mismatches.append("t%04d: %s does not import as its exact grey PNG" % [texture_id, path])
			continue
		var texture: Texture2D = loaded as Texture2D
		if texture == null:
			mismatches.append("t%04d: %s does not import as a texture" % [texture_id, path])
		elif not texture.get_image().has_mipmaps():
			mismatches.append("t%04d: %s is imported without mipmaps" % [texture_id, path])
	_report(mismatches, "%d lettering images and masks import as wanted" % rows.size())


func test_the_font_holds_every_character_of_the_table() -> void:
	var font: FontFile = load(FONT_PATH) as FontFile
	assert_not_null(font, "%s loads as a FontFile" % FONT_PATH)
	if font == null:
		return
	var missing: Dictionary[String, PackedStringArray] = {}
	for row: PackedStringArray in _rows():
		var text: String = row[TEXT_COLUMN]
		for index: int in text.length():
			var character: String = text[index]
			if character == LINE_BREAK or font.has_char(character.unicode_at(0)):
				continue
			if not missing.has(character):
				missing[character] = PackedStringArray()
			missing[character].append("t%04d" % row[ID_COLUMN].to_int())
	var mismatches := PackedStringArray()
	for character: String in missing:
		mismatches.append("%s (U+%04X), used by %s, is missing from the angular font"
			% [character, character.unicode_at(0), ", ".join(missing[character])])
	_report(mismatches, "the angular font holds every character of the lettering table")


func test_no_lettering_file_lacks_a_row() -> void:
	var listed: Dictionary[String, bool] = {}
	for row: PackedStringArray in _rows():
		listed[_path(row)] = true
	var mismatches := PackedStringArray()
	var found: PackedStringArray = GoldenFiles.files_under(LETTERING, ".png")
	for path: String in found:
		if not listed.has(path):
			mismatches.append("%s has no row in %s" % [path, TABLE_PATH])
	assert_eq(found.size(), listed.size(), "one file per row")
	_report(mismatches, "%d lettering files all have rows" % found.size())
