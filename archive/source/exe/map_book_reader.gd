class_name MapBookReader
extends RefCounted
## Reads the level list ([MapBook]) from the executable, up to the theme book.


## Reads the map book of [param exe].
static func read(exe: ExeImage) -> MapBook:
	var book := MapBook.new()
	var start: int = exe.version.map_book
	var end: int = exe.version.theme_book
	if start <= 0:
		book.error = "this build has no map book address"
		return book
	if end <= start:
		book.error = "the theme book (at %d) does not follow the map book (at %d)" % [end, start]
		return book
	var reader: ByteReader = exe.reader_at(start)
	while reader.get_position() < end and not reader.has_error():
		book.entries.append(read_entry(reader, book.entries.size()))
	if reader.has_error():
		book.error = "map book: %s" % reader.error
	return book


## Reads one row ([MapBookEntry], 36 bytes) at [param reader]'s cursor.
static func read_entry(reader: ByteReader, level_number: int) -> MapBookEntry:
	var e := MapBookEntry.new()
	e.level = level_number
	e.high_map_id = reader.read_s32()
	e.low_map_id = reader.read_s32()
	e.high_remap_pointer = reader.read_u32()
	e.low_remap_pointer = reader.read_u32()
	e.use_cave_lights = reader.read_s32() == 1
	e.environment_texture_pointer = reader.read_u32()
	e.high_wad_id = reader.read_s32()
	e.low_wad_id = reader.read_s32()
	e.palette_id = reader.read_s32()
	return e
