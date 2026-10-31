extends RetailTest
## Needs the retail files: every texture bank (VLO) decodes to the golden
## facts in tests/golden/pc-retail-v3.0e/vlo_*.tsv (made by an independent
## Python reader, see tests/golden/README.md), header fields and pixel digests.

var _data: GameData


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))


func after_all() -> void:
	if _data != null:
		_data.close()


func _stored_in(resource_id: int) -> String:
	var entry: MwiEntry = _data.mwi.get_entry(resource_id)
	return "wad %d" % _data.wad_holding(resource_id) if entry.is_group_access() else "mwd"


func test_every_texture_bank_matches() -> void:
	var file_rows: Array[PackedStringArray] = []
	var image_rows: Array[PackedStringArray] = []
	var read_usec: int = 0
	var decode_usec: int = 0
	var texels: int = 0
	var transparent: int = 0
	var renamed: int = 0
	var in_wads: int = 0
	var problems := PackedStringArray()
	for entry: MwiEntry in _data.texture_bank_entries():
		var t0: int = Time.get_ticks_usec()
		var bytes: PackedByteArray = _data.read_resource(entry.index, problems)
		var t1: int = Time.get_ticks_usec()
		var vlo: VloFile = VloFile.parse(bytes)
		decode_usec += Time.get_ticks_usec() - t1
		read_usec += t1 - t0
		assert_eq(vlo.error, "", entry.display_name())
		var named: int = 0
		for image: VloImage in vlo.images:
			if not image.custom_name.is_empty():
				named += 1
			texels += image.padded_width * image.padded_height
			if image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT):
				for word: int in image.pixels.to_int32_array():
					if word & 0xFF000000 == 0:
						transparent += 1
			image_rows.append(PackedStringArray([str(entry.index), str(image.index), str(image.texture_id),
				str(image.vram_x), str(image.vram_y), str(image.padded_width), str(image.padded_height),
				str(image.width), str(image.height), str(image.u), str(image.v), str(image.flags),
				str(image.blend_mode()), str(image.page()), GoldenFiles.sha256_hex(image.pixels),
				GoldenFiles.sha256_hex(image.unpadded_pixels())]))
		renamed += named
		if entry.is_group_access():
			in_wads += 1
		file_rows.append(PackedStringArray([str(entry.index), entry.display_name(), _stored_in(entry.index),
			str(vlo.size()), str(named)]))
	print("TIMING: read %d texture banks %.0f ms; decoded %d images (%.1f M texels) in %.0f ms" % [
		file_rows.size(), read_usec / 1000.0, image_rows.size(), texels / 1000000.0, decode_usec / 1000.0])
	assert_eq(problems.size(), 0, ", ".join(problems))
	var facts: Dictionary[String, String] = GoldenFiles.facts("vlo_summary.txt")
	assert_eq(str(transparent), facts["transparent_texels"], "fully transparent texels")
	assert_eq(str(renamed), facts["custom_names"], "textures renamed by FrogLord")
	assert_eq(str(in_wads), facts["in_wads"], "banks stored inside WADs")
	for label: String in ["files", "images"]:
		var got: Array[PackedStringArray] = file_rows if label == "files" else image_rows
		var differences: PackedStringArray = GoldenFiles.differences(label, got, GoldenFiles.rows("vlo_%s.tsv" % label))
		for difference: String in differences:
			fail_test(difference)
		assert_eq(differences.size(), 0, "vlo_%s.tsv matches" % label)


func test_summary_facts() -> void:
	var facts: Dictionary[String, String] = GoldenFiles.facts("vlo_summary.txt")
	assert_eq(str(_data.texture_bank_entries().size()), facts["vlo_files"])
	var images: int = 0
	var black_is_transparent: int = 0
	for row: PackedStringArray in GoldenFiles.rows("vlo_images.tsv"):
		images += 1
		if row[11].to_int() & VloImage.FLAG_BLACK_IS_TRANSPARENT != 0:
			black_is_transparent += 1
	assert_eq(str(images), facts["images"])
	assert_eq(str(black_is_transparent), facts["black_is_transparent_images"])


func test_texture_library_resolves_a_level_through_its_remap() -> void:
	var sub1: MapBookEntry = _data.map_book_entry(FroggerIds.level_from_code("SUB1"))
	var remap: TextureRemap = _data.remap_for_resource(sub1.high_map_id)
	var theme: ThemeBookEntry = _data.theme_book_entry(FroggerIds.theme_of_level(sub1.level))
	var library := TextureLibrary.new()
	var problems := PackedStringArray()
	var general: VloFile = _data.read_texture_bank(_data.theme_book_entry(FroggerIds.THEME_GENERAL).vlo_id(), problems)
	var bank: VloFile = _data.read_texture_bank(theme.vlo_id(), problems)
	assert_eq(problems.size(), 0, ", ".join(problems))
	library.add_bank(general, "general")
	library.add_bank(bank, "theme")
	var missing: int = 0
	for local: int in remap.size():
		var image: VloImage = library.image_for_local(remap, local, bank)
		if image == null:
			missing += 1
		else:
			assert_eq(image.texture_id, remap.global_id(local))
	assert_eq(missing, 0, "every texture SUB1 names is in the GENERAL or Suburbia bank")
	var texture: ImageTexture = library.texture_for_id(remap.global_id(0), bank)
	assert_not_null(texture)
	assert_eq(texture.get_width(), library.image_for_id(remap.global_id(0), bank).padded_width)
