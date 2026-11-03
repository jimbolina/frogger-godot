class_name LetteringTile
extends RefCounted
## Builds the opaque lettering tiles at runtime from their committed masks and
## the player's retail images, the way [code]tools/make_lettering.py --composite[/code]
## draws them, so no retail pixel is committed.
##
## A tile's mask ([method TextureSet.lettering_mask_path]) is the 8-bit
## coverage of its lettering at [constant SCALE] times the retail padded size;
## the sub-folder it sits in names its background. The background is the most
## common colour of texture [constant PAD_SOURCE] ([code]green_pad[/code]) or
## [constant LOG_SOURCE] ([code]log[/code]), or for [code]turtle[/code] the
## shell of the [constant TURTLES]: per pixel the most common colour whose red
## channel is at most [constant SHELL_RED] among the ten digit tiles, earlier
## tiles winning ties, and where every tile shows a digit the mirrored pixel
## of the same row. The lettering's colour is the most common colour of the
## tile's retail ink, the pixels differing from the background by more than
## [constant TILE_THRESHOLD] in some channel; the first colour seen in scan
## order wins a tie. The background is enlarged by repeating pixels and the
## colour laid over it by the mask with Pillow's rounding ([method blend]),
## every channel is raised to at least [constant MIN_CHANNEL] and the tile is
## opaque. Each background is measured once per builder, from the retail
## images [method sources_of] names.

## The lettering's scale over the retail padded size.
const SCALE: int = 8
## The tile backgrounds, each the name of a mask sub-folder.
const BACKGROUNDS: PackedStringArray = ["green_pad", "log", "turtle"]
## The retail texture whose most common colour is the green pad background.
const PAD_SOURCE: int = 263
## The retail texture whose most common colour is the log background.
const LOG_SOURCE: int = 566
## The turtle digit tiles the shell is rebuilt from, in vote order.
const TURTLES: PackedInt32Array = [638, 639, 640, 641, 642, 643, 644, 645, 646, 647]
## The largest channel difference from the background that is not ink.
const TILE_THRESHOLD: int = 0x10
## The largest red channel of a turtle shell pixel.
const SHELL_RED: int = 0x10
## The smallest channel value of a tile.
const MIN_CHANNEL: int = 8

var _backgrounds: Dictionary[String, Image] = {}


## The retail texture ids the background called [param background] is
## measured from, in vote order; empty for an unknown name.
static func sources_of(background: String) -> PackedInt32Array:
	match background:
		"green_pad":
			return PackedInt32Array([PAD_SOURCE])
		"log":
			return PackedInt32Array([LOG_SOURCE])
		"turtle":
			return TURTLES
	return PackedInt32Array()


## True when the background called [param background] was measured already,
## so [method build] needs no source images for it.
func has_background(background: String) -> bool:
	return _backgrounds.has(background)


## The mipmapped tile of retail texture [param texture_id], whose retail
## image is [param tile_image], drawn from [param mask] on [param background]. The
## background is measured from [param sources] (the images of
## [method sources_of] by texture id) unless [method has_background]. Null,
## with a line in [param problems], when a retail image is missing or a size
## does not fit.
func build(mask: Image, background: String, texture_id: int, tile_image: Image,
		sources: Dictionary[int, Image], problems: PackedStringArray) -> ImageTexture:
	var tile: Image = _rgb(tile_image)
	if tile == null:
		problems.append("no retail texture %d to draw its lettering tile on" % texture_id)
		return null
	if mask == null or mask.get_size() != tile.get_size() * SCALE:
		problems.append("the lettering mask of texture %d is not %d times its %s retail size"
			% [texture_id, SCALE, tile.get_size()])
		return null
	var behind: Image = _background(background, tile.get_size(), sources, problems)
	if behind == null:
		return null
	var fill: Color = fill_colour(tile, behind)
	if fill.a8 == 0:
		problems.append("retail texture %d shows no ink over its %s background" % [texture_id, background])
		return null
	var image: Image = composite(mask, behind, fill)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The opaque RGBA8 tile at [param mask]'s size: [param fill] laid over
## [param behind], an RGB8 image [constant SCALE] times smaller enlarged by
## repeating pixels, by the grey [param mask] ([method blend]), with every
## channel at least [constant MIN_CHANNEL].
static func composite(mask: Image, behind: Image, fill: Color) -> Image:
	var grey: Image = _grey(mask)
	var enlarged: Image = _rgb(behind)
	var width: int = grey.get_width()
	var height: int = grey.get_height()
	var behind_width: int = enlarged.get_width()
	var coverage: PackedByteArray = grey.get_data()
	var under: PackedByteArray = enlarged.get_data()
	var red: int = fill.r8
	var green: int = fill.g8
	var blue: int = fill.b8
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	var at: int = 0
	for y: int in height:
		@warning_ignore("integer_division")
		var row: int = (y / SCALE) * behind_width
		for x: int in width:
			var weight: int = coverage[y * width + x]
			var rest: int = 255 - weight
			@warning_ignore("integer_division")
			var from: int = (row + x / SCALE) * 3
			var total: int = red * weight + under[from] * rest + 128
			pixels[at] = maxi(((total >> 8) + total) >> 8, MIN_CHANNEL)
			total = green * weight + under[from + 1] * rest + 128
			pixels[at + 1] = maxi(((total >> 8) + total) >> 8, MIN_CHANNEL)
			total = blue * weight + under[from + 2] * rest + 128
			pixels[at + 2] = maxi(((total >> 8) + total) >> 8, MIN_CHANNEL)
			pixels[at + 3] = 255
			at += 4
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


## [param over] laid on [param under] by the 8-bit [param weight] of
## [param over], rounded as Pillow's [code]Image.composite[/code] rounds:
## [code]t = over * weight + under * (255 - weight) + 128[/code], then
## [code]((t >> 8) + t) >> 8[/code].
static func blend(over: int, under: int, weight: int) -> int:
	var total: int = over * weight + under * (255 - weight) + 128
	return ((total >> 8) + total) >> 8


## The most common colour of [param tile]'s ink over [param behind] (images
## of one size), or transparent black when no pixel differs from the
## background by more than [constant TILE_THRESHOLD].
static func fill_colour(tile: Image, behind: Image) -> Color:
	var ink: PackedByteArray = _rgb(tile).get_data()
	var under: PackedByteArray = _rgb(behind).get_data()
	var colours := PackedInt32Array()
	for at: int in range(0, ink.size(), 3):
		var difference: int = maxi(maxi(absi(ink[at] - under[at]), absi(ink[at + 1] - under[at + 1])),
			absi(ink[at + 2] - under[at + 2]))
		if difference > TILE_THRESHOLD:
			colours.append(_key(ink, at))
	if colours.is_empty():
		return Color(0, 0, 0, 0)
	return _colour(most_common(colours))


## The most common colour of [param image]'s pixels.
static func flat_colour(image: Image) -> Color:
	var pixels: PackedByteArray = _rgb(image).get_data()
	var colours := PackedInt32Array()
	for at: int in range(0, pixels.size(), 3):
		colours.append(_key(pixels, at))
	return _colour(most_common(colours))


## The turtle shell behind the rank digits, an RGB8 image of the size of
## [param tiles] (the [constant TURTLES] in order), or null when they differ
## in size or every tile shows a digit on both a pixel and its mirror.
static func turtle_shell(tiles: Array[Image]) -> Image:
	if tiles.is_empty():
		return null
	var size: Vector2i = tiles[0].get_size()
	var data: Array[PackedByteArray] = []
	for tile: Image in tiles:
		if tile == null or tile.get_size() != size:
			return null
		data.append(_rgb(tile).get_data())
	var shell := PackedByteArray()
	shell.resize(size.x * size.y * 3)
	var holes := PackedByteArray()
	holes.resize(size.x * size.y)
	for at: int in size.x * size.y:
		var candidates := PackedInt32Array()
		for pixels: PackedByteArray in data:
			if pixels[at * 3] <= SHELL_RED:
				candidates.append(_key(pixels, at * 3))
		if candidates.is_empty():
			holes[at] = 1
			continue
		_put(shell, at * 3, most_common(candidates))
	for y: int in size.y:
		for x: int in size.x:
			var at: int = y * size.x + x
			if holes[at] == 0:
				continue
			var mirror: int = y * size.x + size.x - 1 - x
			if holes[mirror] != 0:
				return null
			for channel: int in 3:
				shell[at * 3 + channel] = shell[mirror * 3 + channel]
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, shell)


## The most common of [param colours] (packed [code]0xRRGGBB[/code]); the
## first seen wins a tie.
static func most_common(colours: PackedInt32Array) -> int:
	var counts: Dictionary[int, int] = {}
	for colour: int in colours:
		counts[colour] = counts.get(colour, 0) + 1
	var best: int = -1
	var best_count: int = 0
	for colour: int in counts:
		if counts[colour] > best_count:
			best = colour
			best_count = counts[colour]
	return best


func _background(background: String, size: Vector2i, sources: Dictionary[int, Image],
		problems: PackedStringArray) -> Image:
	if not _backgrounds.has(background):
		var made: Image = _measure(background, sources, problems)
		if made == null:
			return null
		_backgrounds[background] = made
	var found: Image = _backgrounds[background]
	if background == "turtle":
		if found.get_size() != size:
			problems.append("a turtle tile is %s, the shell %s" % [size, found.get_size()])
			return null
		return found
	var flat: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
	flat.fill(found.get_pixel(0, 0))
	return flat


func _measure(background: String, sources: Dictionary[int, Image], problems: PackedStringArray) -> Image:
	if not background in BACKGROUNDS:
		problems.append("no lettering tile background called %s" % background)
		return null
	if background == "turtle":
		var tiles: Array[Image] = []
		for texture_id: int in TURTLES:
			var tile: Image = sources.get(texture_id, null)
			if tile == null:
				problems.append("no retail texture %d to rebuild the turtle shell from" % texture_id)
				return null
			tiles.append(tile)
		var shell: Image = turtle_shell(tiles)
		if shell == null:
			problems.append("the turtle tiles %s do not rebuild a shell" % str(TURTLES))
		return shell
	var source_id: int = PAD_SOURCE if background == "green_pad" else LOG_SOURCE
	var source: Image = sources.get(source_id, null)
	if source == null:
		problems.append("no retail texture %d to take the %s colour from" % [source_id, background])
		return null
	var colour: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	colour.fill(flat_colour(source))
	return colour


static func _rgb(image: Image) -> Image:
	if image == null:
		return null
	if image.get_format() == Image.FORMAT_RGB8 and not image.has_mipmaps():
		return image
	var copy: Image = image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGB8)
	return copy


static func _grey(image: Image) -> Image:
	if image.get_format() == Image.FORMAT_L8 and not image.has_mipmaps():
		return image
	var copy: Image = image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_L8)
	return copy


static func _key(pixels: PackedByteArray, at: int) -> int:
	return (pixels[at] << 16) | (pixels[at + 1] << 8) | pixels[at + 2]


static func _put(pixels: PackedByteArray, at: int, colour: int) -> void:
	pixels[at] = (colour >> 16) & 0xFF
	pixels[at + 1] = (colour >> 8) & 0xFF
	pixels[at + 2] = colour & 0xFF


static func _colour(colour: int) -> Color:
	return Color8((colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF)
