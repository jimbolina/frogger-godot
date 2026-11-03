extends GutTest
## LetteringTile composites a tile the way tools/make_lettering.py --composite
## does: Pillow's composite rounding, the most common background and ink
## colours with the first seen winning a tie, the ink threshold, the turtle
## shell vote and mirror, the enlarged background and the channel floor. A
## catalog composites a tile from a committed mask and the base root's images,
## and falls back to the retail texture with a problem when they are missing.
## Synthetic images only.

const SCRATCH: String = "user://test_lettering_tile"
const BASE: String = SCRATCH + "/base"
const FIXTURE_ROOT: String = "res://tests/fixtures/lettering"
const TILE_ID: int = 235
const PAD: Color = Color8(40, 160, 60)
const INK: Color = Color8(240, 240, 200)


func before_each() -> void:
	_remove(SCRATCH)
	assert_eq(DirAccess.make_dir_recursive_absolute(BASE.path_join("textures/images")), OK)


func after_all() -> void:
	_remove(SCRATCH)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _image(size: Vector2i, colour: Color) -> Image:
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return image


func _row(colours: Array[Color]) -> Image:
	var image: Image = Image.create_empty(colours.size(), 1, false, Image.FORMAT_RGBA8)
	for x: int in colours.size():
		image.set_pixel(x, 0, colours[x])
	return image


func _grey(size: Vector2i, weights: PackedByteArray) -> Image:
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, weights)


func _rgb8(image: Image, x: int, y: int) -> Array[int]:
	var pixel: Color = image.get_pixel(x, y)
	return [pixel.r8, pixel.g8, pixel.b8, pixel.a8]


func _save_retail(texture_id: int, image: Image) -> Texture2D:
	var path: String = BASE.path_join("textures/images/t%04d.res" % texture_id)
	assert_eq(ResourceSaver.save(ImageTexture.create_from_image(image), path), OK)
	var texture: Texture2D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	texture.take_over_path(path)
	return texture


func _pad_tile() -> Image:
	var tile: Image = _image(Vector2i(4, 4), PAD)
	tile.set_pixel(2, 1, INK)
	tile.set_pixel(3, 1, INK)
	tile.set_pixel(2, 2, Color8(50, 170, 70))
	return tile


func test_blending_rounds_as_pillow_composite() -> void:
	var cases: Array[PackedInt32Array] = [
		PackedInt32Array([200, 37, 77, 86]),
		PackedInt32Array([8, 250, 200, 60]),
		PackedInt32Array([1, 0, 128, 1]),
		PackedInt32Array([3, 0, 128, 2]),
		PackedInt32Array([255, 0, 1, 1]),
		PackedInt32Array([0, 255, 254, 1]),
		PackedInt32Array([123, 45, 129, 84]),
	]
	for case: PackedInt32Array in cases:
		assert_eq(LetteringTile.blend(case[0], case[1], case[2]), case[3], str(case))
	for value: int in [0, 1, 127, 128, 254, 255]:
		assert_eq(LetteringTile.blend(value, 255 - value, 255), value, "full weight keeps the fill")
		assert_eq(LetteringTile.blend(255 - value, value, 0), value, "no weight keeps the background")


func test_the_most_common_colour_wins_and_the_first_seen_breaks_a_tie() -> void:
	var red := Color8(200, 0, 0)
	var blue := Color8(0, 0, 200)
	assert_eq(LetteringTile.flat_colour(_row([red, blue, blue, red, blue])), blue)
	assert_eq(LetteringTile.flat_colour(_row([blue, red, red, blue])), blue, "a tie goes to the first seen")
	assert_eq(LetteringTile.most_common(PackedInt32Array([5, 7, 7, 5])), 5)


func test_the_fill_is_the_most_common_ink_beyond_the_threshold() -> void:
	var behind: Image = _image(Vector2i(6, 1), Color8(100, 100, 100))
	var near := Color8(116, 100, 84)
	var faint := Color8(117, 100, 100)
	var strong := Color8(0, 0, 0)
	var tile: Image = _row([near, near, near, faint, strong, strong])
	assert_eq(LetteringTile.fill_colour(tile, behind), strong, "a difference of 0x10 is not ink")
	tile = _row([near, faint, faint, near, strong, near])
	assert_eq(LetteringTile.fill_colour(tile, behind), faint, "a difference of 0x11 is ink")
	assert_eq(LetteringTile.fill_colour(_row([near, near]), _image(Vector2i(2, 1), Color8(100, 100, 100))).a8, 0,
		"no ink gives transparent black")


func test_the_turtle_shell_votes_dark_pixels_and_mirrors_the_rest() -> void:
	var shell_a := Color8(16, 80, 20)
	var shell_b := Color8(8, 60, 10)
	var digit := Color8(240, 240, 240)
	var tiles: Array[Image] = []
	for index: int in LetteringTile.TURTLES.size():
		var left: Color = shell_a if index < 4 else shell_b
		var second: Color = shell_b if index % 2 == 0 else shell_a
		tiles.append(_row([left, second, digit, Color8(4, 4, 4)]))
	var shell: Image = LetteringTile.turtle_shell(tiles)
	assert_not_null(shell)
	assert_eq(shell.get_format(), Image.FORMAT_RGB8)
	assert_eq(shell.get_pixel(0, 0), shell_b, "six tiles out of ten")
	assert_eq(shell.get_pixel(1, 0), shell_b, "a five-five tie goes to the earlier tile")
	assert_eq(shell.get_pixel(3, 0), Color8(4, 4, 4))
	assert_eq(shell.get_pixel(2, 0), shell.get_pixel(1, 0), "a pixel every tile covers takes its mirror")
	var covered: Array[Image] = []
	for index: int in LetteringTile.TURTLES.size():
		covered.append(_row([digit, digit]))
	assert_null(LetteringTile.turtle_shell(covered), "a pixel and its mirror both covered rebuild nothing")
	tiles[3] = _row([shell_a])
	assert_null(LetteringTile.turtle_shell(tiles), "tiles of different sizes rebuild nothing")


func test_the_composite_enlarges_the_background_and_lifts_dark_channels() -> void:
	var behind: Image = _row([Color8(3, 100, 9), Color8(200, 7, 50)])
	var weights := PackedByteArray()
	weights.resize(16 * 8)
	for y: int in 8:
		for x: int in 16:
			weights[y * 16 + x] = 255 if x == 15 else (128 if x == 8 else 0)
	var tile: Image = LetteringTile.composite(_grey(Vector2i(16, 8), weights), behind, Color8(1, 255, 100))
	assert_eq(tile.get_size(), Vector2i(16, 8))
	assert_eq(tile.get_format(), Image.FORMAT_RGBA8)
	assert_eq(_rgb8(tile, 0, 0), [8, 100, 9, 255], "the background, every channel at least 8")
	assert_eq(_rgb8(tile, 7, 7), [8, 100, 9, 255], "the first background pixel covers eight columns")
	assert_eq(_rgb8(tile, 9, 3), [200, 8, 50, 255], "the second background pixel starts at column 8")
	assert_eq(_rgb8(tile, 15, 0), [8, 255, 100, 255], "full coverage is the fill, lifted")
	assert_eq(_rgb8(tile, 8, 0), [
		LetteringTile.blend(1, 200, 128), LetteringTile.blend(255, 7, 128), LetteringTile.blend(100, 50, 128), 255])


func test_a_tile_is_built_from_the_mask_and_the_retail_images() -> void:
	var sources: Dictionary[int, Image] = {LetteringTile.PAD_SOURCE: _image(Vector2i(2, 2), PAD)}
	var builder := LetteringTile.new()
	var weights := PackedByteArray()
	weights.resize(32 * 32)
	weights.fill(255)
	weights[0] = 0
	var problems := PackedStringArray()
	var texture: ImageTexture = builder.build(_grey(Vector2i(32, 32), weights), "green_pad", TILE_ID, _pad_tile(),
		sources, problems)
	assert_eq(problems, PackedStringArray())
	assert_true(builder.has_background("green_pad"), "the background is measured once")
	assert_not_null(texture)
	if texture == null:
		return
	var image: Image = texture.get_image()
	assert_eq(image.get_size(), Vector2i(32, 32))
	assert_true(image.has_mipmaps(), "a tile carries mipmaps like the imported lettering")
	assert_eq(image.get_pixel(0, 0), PAD, "the pad colour where the mask is empty")
	assert_eq(image.get_pixel(1, 0), INK, "the most common ink where the mask is full")


func test_missing_or_mismatched_inputs_build_nothing_with_a_problem() -> void:
	var none: Dictionary[int, Image] = {}
	var builder := LetteringTile.new()
	var full: Image = Image.create_empty(32, 32, false, Image.FORMAT_L8)
	var problems := PackedStringArray()
	assert_null(builder.build(full, "green_pad", TILE_ID, _pad_tile(), none, problems))
	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "no retail texture %d" % LetteringTile.PAD_SOURCE)
	assert_false(builder.has_background("green_pad"))
	problems.clear()
	assert_null(builder.build(full, "green_pad", 999, null, none, problems))
	assert_string_contains(problems[0], "no retail texture 999")
	problems.clear()
	assert_null(builder.build(Image.create_empty(16, 16, false, Image.FORMAT_L8), "green_pad", TILE_ID, _pad_tile(),
		none, problems))
	assert_string_contains(problems[0], "is not 8 times")
	problems.clear()
	assert_null(builder.build(full, "turtle", TILE_ID, _pad_tile(), none, problems))
	assert_string_contains(problems[0], "no retail texture %d" % LetteringTile.TURTLES[0])
	assert_eq(LetteringTile.sources_of("log"), PackedInt32Array([LetteringTile.LOG_SOURCE]))
	assert_eq(LetteringTile.sources_of("turtle"), LetteringTile.TURTLES)
	assert_eq(LetteringTile.sources_of("sky"), PackedInt32Array())


func test_a_catalog_composites_a_committed_mask_over_the_base_root() -> void:
	_save_retail(LetteringTile.PAD_SOURCE, _image(Vector2i(2, 2), PAD))
	var retail: Texture2D = _save_retail(TILE_ID, _pad_tile())
	var catalog := ImportedAssets.new()
	catalog.root = BASE
	catalog.shippable_root = FIXTURE_ROOT
	var drawn: Texture2D = catalog.texture_counterpart(retail)
	assert_eq(catalog.problems, PackedStringArray())
	assert_true(drawn is ImageTexture)
	assert_eq(Vector2i(drawn.get_size()), Vector2i(32, 32))
	assert_same(catalog.texture_counterpart(retail), drawn, "cached per retail path")
	var image: Image = drawn.get_image()
	assert_eq(image.get_pixel(0, 0), PAD)
	assert_eq(image.get_pixel(31, 31), INK)
	assert_eq(_rgb8(image, 15, 4), [
		LetteringTile.blend(INK.r8, PAD.r8, 128), LetteringTile.blend(INK.g8, PAD.g8, 128),
		LetteringTile.blend(INK.b8, PAD.b8, 128), 255])


func test_a_catalog_without_the_retail_inputs_draws_the_retail_texture_with_a_problem() -> void:
	var retail: Texture2D = _save_retail(TILE_ID, _pad_tile())
	var catalog := ImportedAssets.new()
	catalog.root = BASE
	catalog.shippable_root = FIXTURE_ROOT
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_eq(catalog.problems.size(), 1, "\n".join(catalog.problems))
	assert_string_contains(catalog.problems[0], "lettering tile %d: no retail texture %d" % [TILE_ID, LetteringTile.PAD_SOURCE])
	assert_string_contains(catalog.problems[0], "drawing the retail texture")
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_eq(catalog.problems.size(), 1, "noted once")
