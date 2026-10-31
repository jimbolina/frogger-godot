class_name WadChild
extends Resource
## One file inside a [WadFile].

## The file's resource id (its position in the MWI).
@export var resource_id: int = 0
## Type id recorded in the WAD.
@export var type_id: int = 0
## "File count" field; zero in all known data.
@export var file_count: int = 0
## The stored bytes (possibly PP20-compressed).
@export var data: PackedByteArray
## True if [member data] starts with the PP20 marker.
@export var is_packed: bool = false
