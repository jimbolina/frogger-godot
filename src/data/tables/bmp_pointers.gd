class_name BmpPointers
extends Resource
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
@export var pointers: PackedInt64Array = PackedInt64Array()
## File offset just past the last entry.
@export var end_offset: int = 0
## Why reading failed, or "".
@export var error: String = ""

var _id_by_pointer: Dictionary[int, int] = {}


## Number of texture ids.
func size() -> int:
	return pointers.size()


## The texture id whose record is at [param pointer], or -1 (0 = no texture).
func texture_id_for_pointer(pointer: int) -> int:
	if _id_by_pointer.is_empty() and not pointers.is_empty():
		for index: int in pointers.size():
			if not _id_by_pointer.has(pointers[index]):
				_id_by_pointer[pointers[index]] = index
	var id: int = _id_by_pointer.get(pointer, -1)
	return id
