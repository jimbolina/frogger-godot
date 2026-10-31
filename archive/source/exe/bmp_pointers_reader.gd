class_name BmpPointersReader
extends RefCounted
## Reads the texture pointer list ([BmpPointers]) from the executable.


## Reads the list of [param exe]: addresses up to the first value that does
## not look like a program address.
static func read(exe: ExeImage) -> BmpPointers:
	var list := BmpPointers.new()
	var start: int = exe.version.bmp_pointer_address
	if start <= 0:
		list.error = "this build has no texture pointer list address"
		return list
	var reader: ByteReader = exe.reader_at(start)
	while reader.remaining() >= 4:
		var value: int = reader.read_u32()
		if not ExeImage.looks_like_pointer(value):
			break
		list.pointers.append(value)
	if reader.has_error():
		list.error = "texture pointer list: %s" % reader.error
	list.end_offset = start + list.pointers.size() * 4
	return list
