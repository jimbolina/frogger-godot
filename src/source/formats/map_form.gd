class_name MapForm
extends RefCounted
## One source-ordered FORM grid, including unused and empty records.

var form_index: int = -1
var source_offset: int = -1
var end_offset: int = -1
var data_count: int = 0
## The file's runtime scratch word. Setup derives the actual maximum Y.
var stored_max_y: int = 0
var dimensions: Vector2i = Vector2i.ZERO
var offsets: Vector2i = Vector2i.ZERO
var data: Array[MapFormData] = []
var diagnostics: PackedStringArray = PackedStringArray()
