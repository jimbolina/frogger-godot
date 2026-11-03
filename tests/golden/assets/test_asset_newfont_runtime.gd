extends AssetTest
## NewfontFont, built from the committed retail texture 310, is the committed
## newfont.fnt as Godot imports it: every stored property, glyph and metric
## is equal and the page matches pixel for pixel. A packaged build, which
## ships no font page, therefore draws the same text as a source run.

const COMMITTED: String = "res://assets/fonts/retail/newfont.fnt"
const PAGE_PROPERTY: String = "/textures/0/image"


func _built() -> FontFile:
	var catalog: ImportedAssets = catalog()
	var image: Image = catalog.base_image(NewfontPage.TEXTURE_ID)
	assert_not_null(image, "the committed assets hold texture 310")
	return NewfontFont.build(NewfontPage.build(image))


func _stored(font: FontFile) -> Dictionary[String, Variant]:
	var values: Dictionary[String, Variant] = {}
	for property: Dictionary in font.get_property_list():
		var usage: int = property["usage"]
		var name: String = property["name"]
		if usage & PROPERTY_USAGE_STORAGE == 0 or name.ends_with(PAGE_PROPERTY) or name.begins_with("resource_"):
			continue
		values[name] = font.get(name)
	return values


func test_the_built_font_stores_what_the_imported_font_stores() -> void:
	var committed: FontFile = load(COMMITTED) as FontFile
	var built: FontFile = _built()
	assert_not_null(built)
	if built == null:
		return
	var expected: Dictionary[String, Variant] = _stored(committed)
	var actual: Dictionary[String, Variant] = _stored(built)
	assert_eq(actual.keys().size(), expected.keys().size(), "the same stored properties")
	var differing := PackedStringArray()
	for name: String in expected:
		if not actual.has(name) or str(actual[name]) != str(expected[name]):
			differing.append("%s: %s, imported %s" % [name, str(actual.get(name, "<missing>")), str(expected[name])])
	assert_eq(differing, PackedStringArray(), "\n".join(differing))


func test_the_built_page_is_the_committed_page() -> void:
	var committed: FontFile = load(COMMITTED) as FontFile
	var built: FontFile = _built()
	assert_not_null(built)
	if built == null:
		return
	var expected: Image = committed.get_texture_image(0, NewfontPage.CACHE_SIZE, 0)
	var actual: Image = built.get_texture_image(0, NewfontPage.CACHE_SIZE, 0)
	expected.convert(Image.FORMAT_RGBA8)
	actual.convert(Image.FORMAT_RGBA8)
	assert_eq(actual.get_size(), expected.get_size())
	assert_true(actual.get_data() == expected.get_data(), "the page matches pixel for pixel")


func test_text_measures_the_same() -> void:
	var committed: FontFile = load(COMMITTED) as FontFile
	var built: FontFile = _built()
	for text: String in ["SCORE 012345", "Hi-Score!", "~{|}"]:
		assert_eq(built.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NewfontText.DRAW_SIZE),
			committed.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NewfontText.DRAW_SIZE), text)
