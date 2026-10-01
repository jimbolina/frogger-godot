class_name MapPolygon
extends RefCounted
## One final-format map polygon, preserving file identity and corner order.

## Stored type index.
var type_index: int = 0
## Stored index.
var index: int = 0
## Stored source offset.
var source_offset: int = 0
## Stored vertex indices.
var vertex_indices: PackedInt32Array = PackedInt32Array()
## Stored colors.
var colors: PackedColorArray = PackedColorArray()
## Stored uvs.
var uvs: PackedVector2Array = PackedVector2Array()
## Stored raw words.
var raw_words: PackedInt32Array = PackedInt32Array()
## Stored texture id.
var texture_id: int = -1
## Stored flags.
var flags: int = 0
## Stored visible.
var visible: bool = false
