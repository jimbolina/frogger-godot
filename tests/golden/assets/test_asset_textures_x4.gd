extends AssetTest
## The upscaled textures keep the layout of the images they come from: one PNG
## per texture id, exactly four times the padded size, binary alpha whose
## transparent set is the nearest x4 of the source's, and zero RGB under
## alpha 0.

const IMAGES: String = "res://assets/textures/images"
const IMAGES_X4: String = "res://assets/textures/images_x4"
const FACTOR: int = 4


func _png(path: String) -> Image:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _names(folder: String) -> PackedStringArray:
	var names := PackedStringArray()
	for path: String in files_under(folder, ".png"):
		names.append(path.get_file())
	return names


func _masked(source: Image, mask: Image) -> Image:
	var out := Image.create_empty(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(source, mask, Rect2i(Vector2i.ZERO, mask.get_size()), Vector2i.ZERO)
	return out


func test_every_image_has_one_upscaled_counterpart() -> void:
	var sources: PackedStringArray = _names(IMAGES)
	assert_gt(sources.size(), 0)
	assert_eq(_names(IMAGES_X4), sources, "images_x4 holds the same file names as images")


func test_upscaled_images_keep_size_and_alpha() -> void:
	var mismatches := PackedStringArray()
	var names: PackedStringArray = _names(IMAGES)
	for file_name: String in names:
		var source: Image = _png(IMAGES.path_join(file_name))
		var path: String = IMAGES_X4.path_join(file_name)
		var upscaled: Image = _png(path)
		if source == null or upscaled == null:
			mismatches.append("%s does not load" % path)
			continue
		var size: Vector2i = source.get_size() * FACTOR
		if upscaled.get_size() != size:
			mismatches.append("%s is %s, expected %s" % [path, upscaled.get_size(), size])
			continue
		if upscaled.detect_alpha() == Image.ALPHA_BLEND:
			mismatches.append("%s has partial alpha" % path)
		if _masked(upscaled, upscaled).get_data() != upscaled.get_data():
			mismatches.append("%s has RGB under alpha 0" % path)
		source.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		var opaque := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		opaque.fill(Color.WHITE)
		if _masked(opaque, upscaled).get_data() != _masked(opaque, source).get_data():
			mismatches.append("%s: alpha is not the nearest x4 of the source" % path)
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d upscaled textures keep the layout" % names.size())
