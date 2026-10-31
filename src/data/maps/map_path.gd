class_name MapPath
extends Resource
## Source-ordered PATH record, with its external entity-list pointer retained.

@export var path_index: int = -1
@export var source_offset: int = -1
@export var entity_list_pointer: int = 0
@export var entity_indices: PackedInt32Array = PackedInt32Array()
@export var entity_list_error: String = ""
@export var segments: Array[MapPathSegment] = []
