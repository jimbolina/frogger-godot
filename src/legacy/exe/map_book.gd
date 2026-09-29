class_name MapBook
extends RefCounted
## The level list ("map book"): one [MapBookEntry] per level number.
##
## The table stores no length. As in FrogLord, rows are read from the map
## book's offset up to the theme book, which the game's linker placed right
## after it (60 rows in the PC releases).

## Rows in level-number order.
var entries: Array[MapBookEntry] = []
## Why reading failed, or "".
var error: String = ""


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
		book.entries.append(MapBookEntry.read(reader, book.entries.size()))
	if reader.has_error():
		book.error = "map book: %s" % reader.error
	return book


## Number of rows.
func size() -> int:
	return entries.size()


## The row of level number [param level], or null.
func get_entry(level: int) -> MapBookEntry:
	return entries[level] if level >= 0 and level < entries.size() else null


## The row whose high- or low-poly map is resource [param map_resource_id], or null.
func find_by_map(map_resource_id: int) -> MapBookEntry:
	if map_resource_id <= 0:
		return null
	for e: MapBookEntry in entries:
		if e.high_map_id == map_resource_id or e.low_map_id == map_resource_id:
			return e
	return null
