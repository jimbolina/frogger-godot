extends RefCounted
## Renders the placeholder app icon from its SVG source into the files the
## exports use: a PNG for the project and Linux, a Windows [code].ico[/code]
## and a macOS [code].icns[/code], each holding PNG images.

## The SVG source.
const SOURCE: String = "res://icon/frogger_icon.svg"
## The project, window and Linux icon.
const PNG: String = "res://icon/frogger_icon.png"
## The Windows icon.
const ICO: String = "res://icon/frogger.ico"
## The macOS icon.
const ICNS: String = "res://icon/frogger.icns"
## The side of [constant PNG] in pixels.
const PNG_SIZE: int = 256
## The sides of the images inside [constant ICO].
const ICO_SIZES: Array[int] = [16, 32, 48, 64, 128, 256]
## The element types inside [constant ICNS] with their sides in pixels.
const ICNS_TYPES: Array[Array] = [
	["icp4", 16], ["icp5", 32], ["ic07", 128], ["ic08", 256], ["ic09", 512],
	["ic10", 1024], ["ic11", 32], ["ic12", 64], ["ic13", 512], ["ic14", 1024],
]


## The SVG source rendered as a square RGBA8 image [param side] pixels wide,
## or null when the source does not load.
static func render(side: int) -> Image:
	var text: String = FileAccess.get_file_as_string(SOURCE)
	if text.is_empty():
		return null
	var image := Image.new()
	if image.load_svg_from_string(text, float(side) / 1024.0) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## PNG bytes of the icon at [param side] pixels.
static func png_bytes(side: int) -> PackedByteArray:
	var image: Image = render(side)
	return image.save_png_to_buffer() if image != null else PackedByteArray()


## The Windows icon file: one PNG image per side in [constant ICO_SIZES].
static func ico_bytes() -> PackedByteArray:
	var images: Array[PackedByteArray] = []
	for side: int in ICO_SIZES:
		images.append(png_bytes(side))
	var header := StreamPeerBuffer.new()
	header.put_u16(0)
	header.put_u16(1)
	header.put_u16(images.size())
	var offset: int = 6 + 16 * images.size()
	for index: int in images.size():
		var side: int = ICO_SIZES[index]
		header.put_u8(side % 256)
		header.put_u8(side % 256)
		header.put_u8(0)
		header.put_u8(0)
		header.put_u16(1)
		header.put_u16(32)
		header.put_u32(images[index].size())
		header.put_u32(offset)
		offset += images[index].size()
	var data: PackedByteArray = header.data_array
	for image: PackedByteArray in images:
		data.append_array(image)
	return data


## The macOS icon file: one PNG element per entry of [constant ICNS_TYPES].
static func icns_bytes() -> PackedByteArray:
	var body := StreamPeerBuffer.new()
	body.big_endian = true
	for entry: Array in ICNS_TYPES:
		var kind: String = entry[0]
		var side: int = entry[1]
		var image: PackedByteArray = png_bytes(side)
		body.put_data(kind.to_ascii_buffer())
		body.put_u32(image.size() + 8)
		body.put_data(image)
	var file := StreamPeerBuffer.new()
	file.big_endian = true
	file.put_data("icns".to_ascii_buffer())
	file.put_u32(body.data_array.size() + 8)
	file.put_data(body.data_array)
	return file.data_array


## Every generated file by path.
static func outputs() -> Dictionary[String, PackedByteArray]:
	return {PNG: png_bytes(PNG_SIZE), ICO: ico_bytes(), ICNS: icns_bytes()}
