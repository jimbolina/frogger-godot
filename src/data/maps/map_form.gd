class_name MapForm
extends Resource
## One source-ordered FORM grid, including unused and empty records.

@export var form_index: int = -1
@export var source_offset: int = -1
@export var end_offset: int = -1
@export var data_count: int = 0
## The file's runtime scratch word. Setup derives the actual maximum Y.
@export var stored_max_y: int = 0
@export var dimensions: Vector2i = Vector2i.ZERO
@export var offsets: Vector2i = Vector2i.ZERO
@export var data: Array[MapFormData] = []
@export var diagnostics: PackedStringArray = PackedStringArray()
