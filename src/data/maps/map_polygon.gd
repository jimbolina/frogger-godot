class_name MapPolygon
extends Resource
## One final-format map polygon, preserving file identity and corner order.

## Stored type index.
@export var type_index: int = 0
## Stored index.
@export var index: int = 0
## Stored source offset.
@export var source_offset: int = 0
## Stored vertex indices.
@export var vertex_indices: PackedInt32Array = PackedInt32Array()
## Four stored terrain vertex words, including triangle padding used by GRID.C.
@export var grid_vertex_indices: PackedInt32Array = PackedInt32Array()
## Stored colors.
@export var colors: PackedColorArray = PackedColorArray()
## Stored uvs.
@export var uvs: PackedVector2Array = PackedVector2Array()
## Stored raw words.
@export var raw_words: PackedInt32Array = PackedInt32Array()
## Stored texture id.
@export var texture_id: int = -1
## Stored flags.
@export var flags: int = 0
## Stored visible.
@export var visible: bool = false
