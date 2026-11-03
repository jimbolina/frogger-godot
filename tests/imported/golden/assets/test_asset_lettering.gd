extends AssetTest
## Without a texture pack, the catalog opened from the local import draws each
## row of content/fonts/angular/lettering.tsv in place of its retail texture
## with no problems: a transparent row's image content/lettering/tNNNN.png, a
## tile row a mipmapped tile composited from its mask, each eight times the
## retail size. The table is read with Godot's own file access; the tiles'
## pixels are test_asset_lettering_tiles.gd's.

const TABLE_PATH: String = "res://content/fonts/angular/lettering.tsv"
const LETTERING: String = "res://content/lettering"
const IMAGES: String = "res://assets/textures/images"
const TRANSPARENT: String = "transparent"
const SCALE: int = 8
const ID_COLUMN: int = 0
const BACKGROUND_COLUMN: int = 5


func _rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(TABLE_PATH).split("\n", false):
		if not line.begins_with("#"):
			rows.append(line.split("\t"))
	return rows


func _file(texture_id: int) -> String:
	return "t%04d.png" % texture_id


func test_the_catalog_draws_the_lettering() -> void:
	var assets: ImportedAssets = ImportedAssets.open(ASSETS)
	var mismatches := PackedStringArray()
	var rows: Array[PackedStringArray] = _rows()
	assert_gt(rows.size(), 0, "%s has rows" % TABLE_PATH)
	for row: PackedStringArray in rows:
		var texture_id: int = row[ID_COLUMN].to_int()
		var retail: Texture2D = load(IMAGES.path_join(_file(texture_id))) as Texture2D
		if retail == null:
			mismatches.append("t%04d has no retail texture" % texture_id)
			continue
		var wanted: String = LETTERING.path_join(_file(texture_id)) if row[BACKGROUND_COLUMN] == TRANSPARENT else ""
		var drawn: Texture2D = assets.texture_counterpart(retail)
		var got: String = drawn.resource_path if drawn != null else "null"
		if got != wanted:
			mismatches.append("t%04d: the catalog draws %s, not %s" % [texture_id, got, wanted])
		elif drawn.get_size() != retail.get_size() * SCALE or not drawn.get_image().has_mipmaps():
			mismatches.append("t%04d: the catalog draws %s without mipmaps or at another size than %d times %s"
				% [texture_id, drawn.get_size(), SCALE, retail.get_size()])
	assert_eq(assets.problems, PackedStringArray(), "catalog problems")
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d lettering images replace their retail textures" % rows.size())
