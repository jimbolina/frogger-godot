class_name MwiIndex
extends Resource
## The MWI (Millennium WAD Index): the list of every file in the game's archive.
##
## On PC the index is stored inside [code]FROGGER.EXE[/code], at the offset and
## length the build's version config gives ([code]mwiOffset[/code],
## [code]mwiLength[/code]). FrogLord also writes it as a standalone
## [code].MWI[/code] file; both are parsed the same way by [MwiIndexReader].

## Every entry, in index order.
@export var entries: Array[MwiEntry] = []
## Why parsing failed, or "".
@export var error: String = ""

var _by_name: Dictionary[String, int] = {}


## Parses the index held in [param bytes] (the MWI region only, not the whole
## executable); see [method MwiIndexReader.parse].
static func parse(bytes: PackedByteArray) -> MwiIndex:
	return MwiIndexReader.parse(bytes)


## Reads the index out of a whole executable using [param version]'s location;
## see [method MwiIndexReader.from_exe].
static func from_exe(exe: PackedByteArray, version: GameVersionConfig) -> MwiIndex:
	return MwiIndexReader.from_exe(exe, version)


## True when the index parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Number of entries.
func size() -> int:
	return entries.size()


## The entry with resource id [param resource_id], or null.
func get_entry(resource_id: int) -> MwiEntry:
	if resource_id < 0 or resource_id >= entries.size():
		return null
	return entries[resource_id]


## The first entry whose file name (without folders) is [param file_name],
## ignoring case, or null.
func find_by_name(file_name: String) -> MwiEntry:
	if _by_name.is_empty():
		_index_names()
	var key: String = file_name.to_lower()
	if not _by_name.has(key):
		return null
	return entries[_by_name[key]]


## All WAD entries, in index order.
func wad_entries() -> Array[MwiEntry]:
	var wads: Array[MwiEntry] = []
	for e: MwiEntry in entries:
		if e.is_wad():
			wads.append(e)
	return wads


## Number of entries per type id.
func count_by_type() -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for e: MwiEntry in entries:
		counts[e.type_id] = counts.get(e.type_id, 0) + 1
	return counts


## Number of compressed entries.
func compressed_count() -> int:
	var n: int = 0
	for e: MwiEntry in entries:
		if e.is_compressed():
			n += 1
	return n


func _index_names() -> void:
	for e: MwiEntry in entries:
		if e.name_offset == MwiEntry.NO_NAME:
			continue
		var key: String = e.display_name().to_lower()
		if not _by_name.has(key):
			_by_name[key] = e.index
