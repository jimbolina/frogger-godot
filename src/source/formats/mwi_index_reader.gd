class_name MwiIndexReader
extends RefCounted
## Decodes the MWI (Millennium WAD Index) into an [MwiIndex].
##
## The index is an array of fixed-size [MwiEntry] records followed by their
## NUL-terminated names. Name offsets are relative to the start of the index,
## and the record array ends where the first name begins (as in FrogLord's
## MillenniumWadIndex).


## Parses the index held in [param bytes] (the MWI region only, not the whole
## executable). Returns an index whose [member MwiIndex.error] says what went
## wrong, if anything.
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
	return index


## Reads the index out of a whole executable using [param version]'s location.
static func from_exe(exe: PackedByteArray, version: GameVersionConfig) -> MwiIndex:
	if version.mwi_offset <= 0 or version.mwi_offset + version.mwi_length > exe.size():
		var bad := MwiIndex.new()
		bad.error = "the MWI (%d bytes at %d) is outside an executable of %d bytes" % [
			version.mwi_length, version.mwi_offset, exe.size()]
		return bad
	return parse(exe.slice(version.mwi_offset, version.mwi_offset + version.mwi_length))
