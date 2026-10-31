class_name MapFormData
extends Resource
## One FORM_DATA record and its source grid-square flags.

@export var source_offset: int = -1
@export var end_offset: int = -1
@export var height_type: int = 0
@export var height: int = 0
@export var flags_pointer: int = 0
@export var heights_pointer: int = 0
## Unsigned 16-bit flags in Z-major order.
@export var grid_flags: PackedInt32Array = PackedInt32Array()
@export var diagnostics: PackedStringArray = PackedStringArray()
