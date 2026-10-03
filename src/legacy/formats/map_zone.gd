class_name MapZone
extends RefCounted
## One authored ZONE record, with its camera payload and ordered regions.

var zone_index: int = -1
var source_offset: int = -1
var end_offset: int = -1
var zone_type: int = -1
var bounds: PackedInt32Array = PackedInt32Array()
var region_pointer: int = 0
var regions: Array[MapZoneRegion] = []
var camera_flags: int = 0
var camera_direction: int = -1
var camera_offsets: Array[Vector3i] = []
var diagnostics: PackedStringArray = PackedStringArray()
