class_name MapZone
extends Resource
## One authored ZONE record, with its camera payload and ordered regions.

@export var zone_index: int = -1
@export var source_offset: int = -1
@export var end_offset: int = -1
@export var zone_type: int = -1
@export var bounds: PackedInt32Array = PackedInt32Array()
@export var region_pointer: int = 0
@export var regions: Array[MapZoneRegion] = []
@export var camera_flags: int = 0
@export var camera_direction: int = -1
@export var camera_offsets: Array[Vector3i] = []
@export var diagnostics: PackedStringArray = PackedStringArray()
