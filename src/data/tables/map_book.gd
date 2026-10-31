class_name MapBook
extends Resource
## The level list ("map book"): one [MapBookEntry] per level number.
##
## The table stores no length. As in FrogLord, rows are read from the map
## book's offset up to the theme book, which the game's linker placed right
## after it (60 rows in the PC releases).

## Rows in level-number order.
@export var entries: Array[MapBookEntry] = []
## Why reading failed, or "".
@export var error: String = ""


## Reads the map book of [param exe] (see [MapBookReader]).
static func read(exe: ExeImage) -> MapBook:
	return MapBookReader.read(exe)


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


## The first row whose high- or low-poly WAD of models is resource
## [param wad_resource_id], or null.
func find_by_wad(wad_resource_id: int) -> MapBookEntry:
	if wad_resource_id <= 0:
		return null
	for e: MapBookEntry in entries:
		if e.high_wad_id == wad_resource_id or e.low_wad_id == wad_resource_id:
			return e
	return null
