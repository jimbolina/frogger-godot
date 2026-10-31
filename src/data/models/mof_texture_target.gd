class_name MofTextureTarget
extends Resource
## One polygon whose image changes according to a texture animation list.

## The kind of polygon the target names (see [MofPolygonType]).
@export var polygon_type: int = 0
## Index of the polygon in its part.
@export var polygon_index: int = 0
## Index of the texture animation in the part's lists, or -1.
@export var list_index: int = -1
## Invalid semantic references disable this target, leaving geometry usable.
@export var error: String = ""
