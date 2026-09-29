class_name WadFile
extends RefCounted
## A WAD: a bundle of game files loaded together (for example one level's models).
##
## A WAD is itself an MWI entry (type -1), usually compressed as a whole. Its
## contents are a list of files, each with a 16-byte header:
## [codeblock]
## s32 resource id (its MWI entry)  s32 type id  s32 size  s32 file count (unused, 0)
## [size bytes of data] [zero padding to a multiple of 4]
## [/codeblock]
## The list ends with a header whose resource id is -1 and whose other three
## fields are zero. A file inside a WAD may be PowerPacker-compressed on its
## own; its MWI entry's flags say so.


## One file inside a WAD.
class Child:
	extends RefCounted
	## The file's resource id (its position in the MWI).
	var resource_id: int = 0
	## Type id recorded in the WAD.
	var type_id: int = 0
	## "File count" field; zero in all known data.
	var file_count: int = 0
	## The stored bytes (possibly PP20-compressed).
	var data: PackedByteArray
	## True if [member data] starts with the PP20 marker.
	var is_packed: bool = false


## The files, in stored order.
var children: Array[Child] = []
## Why parsing failed, or "".
var error: String = ""


## Parses the (already decompressed) WAD bytes [param bytes].
static func parse(bytes: PackedByteArray) -> WadFile:
	var wad := WadFile.new()
	var reader := ByteReader.new(bytes)
	while true:
		if reader.remaining() < 16:
			wad.error = "no end marker (%d bytes left at %d)" % [reader.remaining(), reader.get_position()]
			return wad
		var resource_id: int = reader.read_s32()
		if resource_id == -1:
			if reader.read_s32() != 0 or reader.read_s32() != 0 or reader.read_s32() != 0:
				wad.error = "end marker is not zero-filled"
			return wad
		var child := Child.new()
		child.resource_id = resource_id
		child.type_id = reader.read_s32()
		var size: int = reader.read_s32()
		child.file_count = reader.read_s32()
		if size < 0 or size > reader.remaining():
			wad.error = "file %d (resource %d) claims %d bytes, only %d remain" % [
				wad.children.size(), resource_id, size, reader.remaining()]
			return wad
		child.data = reader.read_bytes(size)
		child.is_packed = Pp20.is_packed(child.data)
		reader.align(4)
		if reader.has_error():
			wad.error = reader.error
			return wad
		wad.children.append(child)
	return wad


## True when the WAD parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## The contents of [param child], decompressed if it is PP20 data. Returns an
## empty array and sets [member error] if decompression fails.
func child_contents(child: Child) -> PackedByteArray:
	if not child.is_packed:
		return child.data
	var unpacker := Pp20.new()
	var out: PackedByteArray = unpacker.unpack(child.data)
	if not unpacker.error.is_empty():
		error = "resource %d: %s" % [child.resource_id, unpacker.error]
	return out


## The MWI entry of [param child] in [param index], or null if the id is out of range.
static func entry_for(child: Child, index: MwiIndex) -> MwiEntry:
	return index.get_entry(child.resource_id)
