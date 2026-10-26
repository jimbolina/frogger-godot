class_name BmpPointers
extends RefCounted
## The texture pointer list ([code]bmp_pointers[/code]): one entry per global texture id.
##
## Every texture the game can refer to by number has a texture record in the
## program's memory; this list holds the address of the record for each
## texture id, in id order. Loading a texture bank (VLO) fills in the record
## of each image's texture id, so a texture id always means "whichever loaded
## image has this id". Other tables (level select, pickups, the level list's
## environment texture) point at texture records directly; the position of
## such an address in this list is its texture id.
##
## The list has no stored length. As in FrogLord it runs until the first
## value that does not look like a program address (the texture remaps follow).

## Record addresses in texture-id order.
var pointers: PackedInt64Array = PackedInt64Array()
## File offset just past the last entry.
var end_offset: int = 0
## Why reading failed, or "".
var error: String = ""

var _id_by_pointer: Dictionary[int, int] = {}


## Reads the list of [param exe].
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
		if not list._id_by_pointer.has(value):
			list._id_by_pointer[value] = list.pointers.size()
		list.pointers.append(value)
	if reader.has_error():
		list.error = "texture pointer list: %s" % reader.error
	list.end_offset = start + list.pointers.size() * 4
	return list


## Number of texture ids.
func size() -> int:
	return pointers.size()


## The texture id whose record is at [param pointer], or -1 (0 = no texture).
func texture_id_for_pointer(pointer: int) -> int:
	var id: int = _id_by_pointer.get(pointer, -1)
	return id
