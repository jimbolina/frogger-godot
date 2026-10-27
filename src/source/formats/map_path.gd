class_name MapPath
extends RefCounted
## Source-ordered PATH record, with its external entity-list pointer retained.

var path_index: int = -1
var source_offset: int = -1
var entity_list_pointer: int = 0
var entity_indices: PackedInt32Array = PackedInt32Array()
var entity_list_error: String = ""
var segments: Array[MapPathSegment] = []
