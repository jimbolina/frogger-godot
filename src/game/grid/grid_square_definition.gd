class_name GridSquareDefinition
extends RefCounted
## A terrain layer's flags and four calculation corners in game units.

var flags: int = 0
## Scalar source identity for diagnostics; never a legacy object reference.
var source_offset: int = 0
var polygon_index: int = -1
var polygon_source_offset: int = 0
var vertices: Array[Vector3i] = []
