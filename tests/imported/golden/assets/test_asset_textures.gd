extends AssetTest
## The imported textures match the retail facts: every bank image's header
## (vlo_images.tsv) and its PNG's padded and unpadded RGBA8 digests. PNGs are
## decoded from the files themselves, and through the imported texture.

const IMAGES: String = "res://assets/textures/images"

var _assets: ImportedAssets
var _image_rows: Array[PackedStringArray]


func before_all() -> void:
	_assets = catalog()
	_image_rows = fact_rows("vlo_images.tsv")


func _png(path: String) -> Image:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func test_bank_images_match_the_headers() -> void:
	var mismatches := PackedStringArray()
	for row: PackedStringArray in _image_rows:
		var bank: VloFile = _assets.read_texture_bank(int(row[0]))
		var at: int = int(row[1])
		if bank == null or at >= bank.size():
			mismatches.append("bank %s has no image %d" % [row[0], at])
			continue
		var image: VloImage = bank.images[at]
		var got := PackedStringArray([row[0], row[1], str(image.texture_id), str(image.vram_x), str(image.vram_y),
			str(image.padded_width), str(image.padded_height), str(image.width), str(image.height), str(image.u),
			str(image.v), str(image.flags), str(image.blend_mode()), str(image.page())])
		if got != row.slice(0, 14):
			mismatches.append("bank %s image %d: got %s, golden %s" % [row[0], at, got, row.slice(0, 14)])
		var png: String = IMAGES.path_join("t%04d.png" % image.texture_id)
		if image.texture == null or image.texture.resource_path != png:
			mismatches.append("bank %s image %d does not use %s" % [row[0], at, png])
		if not image.pixels.is_empty():
			mismatches.append("bank %s image %d keeps its pixels" % [row[0], at])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d bank images match" % _image_rows.size())


func test_pngs_match_the_pixels() -> void:
	var mismatches := PackedStringArray()
	var seen: Dictionary[int, bool] = {}
	for row: PackedStringArray in _image_rows:
		var texture_id: int = int(row[2])
		if seen.has(texture_id):
			continue
		seen[texture_id] = true
		var path: String = IMAGES.path_join("t%04d.png" % texture_id)
		var image: Image = _png(path)
		if image == null:
			mismatches.append("%s does not load" % path)
			continue
		var size := Vector2i(int(row[5]), int(row[6]))
		if image.get_size() != size:
			mismatches.append("%s is %s, golden %s" % [path, image.get_size(), size])
			continue
		if sha256_hex(image.get_data()) != row[14]:
			mismatches.append("%s: padded RGBA digest differs" % path)
		var inner := Rect2i((size.x - int(row[7])) / 2, (size.y - int(row[8])) / 2, int(row[7]), int(row[8]))
		if sha256_hex(image.get_region(inner).get_data()) != row[15]:
			mismatches.append("%s: unpadded RGBA digest differs" % path)
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d texture PNGs match" % seen.size())
	assert_eq(seen.size(), int(fact_values("asset_census.txt")["distinct_texture_ids"]))


func test_imported_textures_hold_the_pixels() -> void:
	var mismatches := PackedStringArray()
	var seen: Dictionary[int, bool] = {}
	for row: PackedStringArray in _image_rows:
		var texture_id: int = int(row[2])
		if seen.has(texture_id):
			continue
		seen[texture_id] = true
		var path: String = IMAGES.path_join("t%04d.png" % texture_id)
		var texture: Texture2D = load(path) as Texture2D
		var image: Image = texture.get_image() if texture != null else null
		if image == null:
			mismatches.append("%s has no imported image" % path)
			continue
		image.convert(Image.FORMAT_RGBA8)
		if image.has_mipmaps():
			mismatches.append("%s has mipmaps" % path)
		if sha256_hex(image.get_data()) != row[14]:
			mismatches.append("%s: imported RGBA digest differs" % path)
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d imported textures match" % seen.size())


func test_front_end_and_hud_images_load_from_the_assets() -> void:
	var front: FrontEndAssets = FrontEndAssets.from_data(_assets)
	assert_eq(front.error, "")
	assert_true(front.texture("jun_col") is AtlasTexture, "2D tiles draw a region of the imported texture")
	var water: Texture2D = front.texture("opt_env_sky")
	assert_true(water is ImageTexture, "3D water gets its own unpadded image")
	var texture_id: int = _assets.names.images.index_of("opt_env_sky")
	for row: PackedStringArray in _image_rows:
		if int(row[2]) == texture_id and water != null:
			var pixels: Image = water.get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			assert_eq(pixels.get_size(), Vector2i(int(row[7]), int(row[8])))
			assert_eq(sha256_hex(pixels.get_data()), row[15], "unpadded water image")
			break
	var hud: GameplayHudAssets = GameplayHudAssets.from_data(_assets)
	assert_eq(hud.error, "")
	assert_true(hud.textures["newfont"] is CompressedTexture2D, "HUD images are the imported textures")

