class_name MwiIndex
extends RefCounted
## The MWI (Millennium WAD Index): the list of every file in the game's archive.
##
## On PC the index is stored inside [code]FROGGER.EXE[/code], at the offset and
## length the build's version config gives ([code]mwiOffset[/code],
## [code]mwiLength[/code]). FrogLord also writes it as a standalone
## [code].MWI[/code] file; both are parsed the same way.
##
## The index is an array of fixed-size [MwiEntry] records followed by their
## NUL-terminated names. Name offsets are relative to the start of the index,
## and the record array ends where the first name begins (as in FrogLord's
## MillenniumWadIndex).

## Every entry, in index order.
var entries: Array[MwiEntry] = []
## Why parsing failed, or "".
var error: String = ""

var _by_name: Dictionary[String, int] = {}


## Parses the index held in [param bytes] (the MWI region only, not the whole
## executable). Returns an index whose [member error] says what went wrong,
## if anything.
static func parse(bytes: PackedByteArray) -> MwiIndex:
	var index := MwiIndex.new()
	var reader := ByteReader.new(bytes)
	var first_name: int = bytes.size()
	while reader.get_position() < first_name and reader.remaining() >= MwiEntry.ENTRY_SIZE:
		var e := MwiEntry.new()
		e.index = index.entries.size()
		e.name_offset = reader.read_u32()
		e.flags = reader.read_u32()
		e.type_id = FixedPoint.to_s32(reader.read_u32())
		e.sector_offset = reader.read_u32()
		if reader.read_u32() != 0 or reader.read_u32() != 0:
			index.error = "entry %d: the run-time pointer fields are not zero" % e.index
			return index
		e.packed_size = reader.read_u32()
		var size_word: int = reader.read_u32()
		e.unpacked_size = size_word & 0xFFFFFF
		e.safety_margin_words = size_word >> 24
		index.entries.append(e)
		if e.name_offset != MwiEntry.NO_NAME:
			first_name = mini(first_name, e.name_offset)
	if index.entries.is_empty():
		index.error = "no entries (index of %d bytes)" % bytes.size()
		return index
	for e: MwiEntry in index.entries:
		if e.name_offset == MwiEntry.NO_NAME:
			continue
		e.path = reader.cstring_at(e.name_offset)
		if reader.has_error():
			index.error = "entry %d: %s" % [e.index, reader.error]
			return index
		var key: String = e.display_name().to_lower()
		if not index._by_name.has(key):
			index._by_name[key] = e.index
	return index


## Reads the index out of a whole executable using [param version]'s location.
static func from_exe(exe: PackedByteArray, version: GameVersionConfig) -> MwiIndex:
	if version.mwi_offset <= 0 or version.mwi_offset + version.mwi_length > exe.size():
		var bad := MwiIndex.new()
		bad.error = "the MWI (%d bytes at %d) is outside an executable of %d bytes" % [
			version.mwi_length, version.mwi_offset, exe.size()]
		return bad
	return parse(exe.slice(version.mwi_offset, version.mwi_offset + version.mwi_length))


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
