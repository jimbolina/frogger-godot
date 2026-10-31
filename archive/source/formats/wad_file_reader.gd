class_name WadFileReader
extends RefCounted
## Decodes WAD bundles into [WadFile]s and unpacks their files.
##
## Each file in a WAD has a 16-byte header:
## [codeblock]
## s32 resource id (its MWI entry)  s32 type id  s32 size  s32 file count (unused, 0)
## [size bytes of data] [zero padding to a multiple of 4]
## [/codeblock]
## The list ends with a header whose resource id is -1 and whose other three
## fields are zero.


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
		var child := WadChild.new()
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


## The contents of [param child], decompressed if it is PP20 data. Returns an
## empty array and sets [param wad]'s error if decompression fails.
static func child_contents(wad: WadFile, child: WadChild) -> PackedByteArray:
	if not child.is_packed:
		return child.data
	var unpacker := Pp20.new()
	var out: PackedByteArray = unpacker.unpack(child.data)
	if not unpacker.error.is_empty():
		wad.error = "resource %d: %s" % [child.resource_id, unpacker.error]
	return out
