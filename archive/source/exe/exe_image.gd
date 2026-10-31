class_name ExeImage
extends RefCounted
## The game executable as a block of bytes that tables are read from.
##
## Besides the program itself, [code]FROGGER.EXE[/code] holds most of the
## game's fixed data: the level list, the theme list, texture tables, entity
## scripts and more. Tables sit at file offsets named by the build's FrogLord
## version file ([GameVersionConfig]). Pointers stored [i]inside[/i] those
## tables are addresses in the running program; [method pointer_to_offset]
## turns one into a file offset using the build's [code]ramOffset[/code].
##
## A FrogLord-saved executable has build information appended after the
## program ([FrogLordExeTrailer]). Table reads are confined to the original
## program bytes, [code][0, program_length)[/code], so the appended text can
## never be mistaken for table data.

## The whole executable as read from disk.
var bytes: PackedByteArray
## The build this executable belongs to.
var version: GameVersionConfig
## Number of bytes that belong to the program (the file size, or the length
## FrogLord recorded before appending its build information).
var program_length: int = 0
## FrogLord's build information, or null for an unmodified executable.
var trailer: FrogLordExeTrailer
## Why the image is unusable, or "".
var error: String = ""


## Wraps [param exe_bytes] as an executable of build [param build].
static func create(exe_bytes: PackedByteArray, build: GameVersionConfig) -> ExeImage:
	var image := ExeImage.new()
	image.bytes = exe_bytes
	image.version = build
	image.program_length = exe_bytes.size()
	image.trailer = FrogLordExeTrailer.read(exe_bytes)
	if image.trailer != null:
		if not image.trailer.error.is_empty():
			image.error = "FrogLord build information: %s" % image.trailer.error
		else:
			image.program_length = image.trailer.original_exe_length
	return image


## True when tables can be read.
func is_valid() -> bool:
	return error.is_empty()


## The file offset of in-program address [param pointer].
func pointer_to_offset(pointer: int) -> int:
	return version.pointer_to_file_offset(pointer)


## The in-program address of file offset [param offset].
func offset_to_pointer(offset: int) -> int:
	return version.file_offset_to_pointer(offset)


## True if [param offset] .. [param offset] + [param size] lies inside the program bytes.
func contains(offset: int, size: int) -> bool:
	return offset >= 0 and size >= 0 and offset + size <= program_length


## True if [param value] looks like an address inside a Windows program
## (0x004xxxxx), the test FrogLord uses to find where pointer lists end.
static func looks_like_pointer(value: int) -> bool:
	return ExePointer.looks_like(value)


## A reader over the program bytes with its cursor at file offset [param offset].
## Reads past the end of the program record an error in the reader.
func reader_at(offset: int) -> ByteReader:
	var reader := ByteReader.new(bytes, 0, program_length)
	reader.seek(offset)
	return reader


## A reader positioned at the file offset in-program address [param pointer] points to.
func reader_at_pointer(pointer: int) -> ByteReader:
	return reader_at(pointer_to_offset(pointer))


## The first file offset where [param pattern] occurs inside the program bytes, or -1.
func find(pattern: PackedByteArray) -> int:
	if pattern.is_empty():
		return -1
	var start: int = bytes.find(pattern[0])
	while start >= 0 and start + pattern.size() <= program_length:
		if bytes.slice(start, start + pattern.size()) == pattern:
			return start
		start = bytes.find(pattern[0], start + 1)
	return -1


## A value from the build information FrogLord appended, as text; "" when
## the key is absent or the executable is unmodified. Keys live at the top
## level of that text, beside its [code][BuildInfo][/code] section.
func trailer_value(key: String) -> String:
	if trailer == null or trailer.config == null:
		return ""
	return trailer.config.get_string(key)
