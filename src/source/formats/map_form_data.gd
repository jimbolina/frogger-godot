class_name MapFormData
extends RefCounted
## One FORM_DATA record and its source grid-square flags.

var source_offset: int = -1
var end_offset: int = -1
var height_type: int = 0
var height: int = 0
var flags_pointer: int = 0
var heights_pointer: int = 0
## Unsigned 16-bit flags in Z-major order.
var grid_flags: PackedInt32Array = PackedInt32Array()
var diagnostics: PackedStringArray = PackedStringArray()
