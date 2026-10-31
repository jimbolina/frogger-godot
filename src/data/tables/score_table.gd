class_name ScoreTable
extends Resource
## v3.0e SCORE_BOOK records verified from AddFrogScore's table access.

## Points awarded by each record.
@export var values: PackedInt32Array = PackedInt32Array()
## Flag words of each record.
@export var flags: PackedInt32Array = PackedInt32Array()
## Texture record address of each record.
@export var texture_pointers: PackedInt64Array = PackedInt64Array()
## Why the table could not be read, or "".
@export var error: String = ""
