class_name WadFile
extends Resource
## A WAD: a bundle of game files loaded together (for example one level's models).
##
## A WAD is itself an MWI entry (type -1), usually compressed as a whole; its
## contents are a list of [WadChild] files, decoded by [WadFileReader]. A file
## inside a WAD may be PowerPacker-compressed on its own; its MWI entry's flags
## say so.

## Former name of [WadChild], kept for existing references.
const Child := preload("res://src/data/archive/wad_child.gd")

## The files, in stored order.
@export var children: Array[WadChild] = []
## Why parsing failed, or "".
@export var error: String = ""


## Parses the (already decompressed) WAD bytes [param bytes]; see
## [method WadFileReader.parse].
static func parse(bytes: PackedByteArray) -> WadFile:
	return WadFileReader.parse(bytes)


## True when the WAD parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## The contents of [param child], decompressed if it is PP20 data. Returns an
## empty array and sets [member error] if decompression fails.
func child_contents(child: WadChild) -> PackedByteArray:
	return WadFileReader.child_contents(self, child)


## The MWI entry of [param child] in [param index], or null if the id is out of range.
static func entry_for(child: WadChild, index: MwiIndex) -> MwiEntry:
	return index.get_entry(child.resource_id)
