extends GutTest
## The committed app icon files are the renders of icon/frogger_icon.svg that
## tools/make_icons.gd writes, and the project and export presets point at
## them. Pixels are compared with a small tolerance, so a rasteriser
## difference between hosts does not fail the check.

const AppIcons = preload("res://tools/support/app_icons.gd")
const TOLERANCE: int = 3


func _decoded(data: PackedByteArray) -> Image:
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _close(actual: Image, side: int) -> bool:
	var expected: Image = AppIcons.render(side)
	if actual == null or expected == null or actual.get_size() != expected.get_size():
		return false
	var left: PackedByteArray = actual.get_data()
	var right: PackedByteArray = expected.get_data()
	for index: int in left.size():
		if absi(left[index] - right[index]) > TOLERANCE:
			return false
	return true


func test_the_png_is_the_rendered_source() -> void:
	var image: Image = _decoded(FileAccess.get_file_as_bytes(AppIcons.PNG))
	assert_not_null(image)
	assert_true(_close(image, AppIcons.PNG_SIZE), "icon/frogger_icon.png matches its SVG; run tools/make_icons.gd")


func test_the_ico_holds_each_size_as_a_png() -> void:
	var data := StreamPeerBuffer.new()
	data.data_array = FileAccess.get_file_as_bytes(AppIcons.ICO)
	assert_eq(data.get_u16(), 0)
	assert_eq(data.get_u16(), 1, "an icon file")
	assert_eq(data.get_u16(), AppIcons.ICO_SIZES.size())
	for side: int in AppIcons.ICO_SIZES:
		var width: int = data.get_u8()
		assert_eq(width, side % 256)
		data.get_data(7)
		var size: int = data.get_u32()
		var offset: int = data.get_u32()
		var image: Image = _decoded(data.data_array.slice(offset, offset + size))
		assert_true(_close(image, side), "the %d-pixel icon matches its SVG" % side)


func test_the_icns_holds_each_element_as_a_png() -> void:
	var data := StreamPeerBuffer.new()
	data.big_endian = true
	data.data_array = FileAccess.get_file_as_bytes(AppIcons.ICNS)
	assert_eq(data.get_utf8_string(4), "icns")
	assert_eq(data.get_u32(), data.data_array.size())
	for entry: Array in AppIcons.ICNS_TYPES:
		var kind: String = entry[0]
		var side: int = entry[1]
		assert_eq(data.get_utf8_string(4), kind)
		var length: int = data.get_u32()
		var start: int = data.get_position()
		assert_true(_close(_decoded(data.data_array.slice(start, start + length - 8)), side), "%s matches its SVG" % kind)
		data.seek(start + length - 8)
	assert_eq(data.get_available_bytes(), 0)


func test_the_project_and_presets_use_the_icons() -> void:
	var icon: String = ProjectSettings.get_setting("application/config/icon")
	var macos_icon: String = ProjectSettings.get_setting("application/config/macos_native_icon")
	var windows_icon: String = ProjectSettings.get_setting("application/config/windows_native_icon")
	assert_eq(icon, AppIcons.PNG)
	assert_eq(macos_icon, AppIcons.ICNS)
	assert_eq(windows_icon, AppIcons.ICO)
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var macos_export: String = presets.get_value("preset.0.options", "application/icon")
	var windows_export: String = presets.get_value("preset.1.options", "application/icon")
	assert_eq(macos_export, AppIcons.ICNS)
	assert_eq(windows_export, AppIcons.ICO)
