class_name MapAnimation
extends RefCounted
## A UV or texture animation track with resolved polygon targets.

## Stored source offset.
var source_offset: int = 0
## Stored type.
var type: int = 0
## Stored delta u.
var delta_u: int = 0
## Stored delta v.
var delta_v: int = 0
## Stored uv frame count.
var uv_frame_count: int = 0
## Stored frames per texture.
var frames_per_texture: int = 0
## Stored texture ids.
var texture_ids: PackedInt32Array = PackedInt32Array()
## Stored target polygon indices.
var target_polygon_indices: PackedInt32Array = PackedInt32Array()
## Stored target pointers.
var target_pointers: PackedInt32Array = PackedInt32Array()
## Stored raw header.
var raw_header: PackedByteArray = PackedByteArray()
## Stored raw targets.
var raw_targets: PackedByteArray = PackedByteArray()
## Stored initial u.
var initial_u: int = 0
## Stored initial v.
var initial_v: int = 0
## Stored initial uv count.
var initial_uv_count: int = 0
## Stored initial cel.
var initial_cel: int = 0
## Stored initial cel count.
var initial_cel_count: int = 0
