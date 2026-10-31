class_name WadFile
extends Resource
## A WAD: a bundle of game files loaded together (for example one level's models).
##
## A WAD is itself an MWI entry (type -1), usually compressed as a whole; its
## contents are a list of [WadChild] files. A file
## inside a WAD may be PowerPacker-compressed on its own; its MWI entry's flags
## say so.

## Former name of [WadChild], kept for existing references.
const Child := preload("res://src/data/archive/wad_child.gd")

## The files, in stored order.
@export var children: Array[WadChild] = []
## Why parsing failed, or "".
@export var error: String = ""


## True when the WAD parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## The MWI entry of [param child] in [param index], or null if the id is out of range.
static func entry_for(child: WadChild, index: MwiIndex) -> MwiEntry:
	return index.get_entry(child.resource_id)
