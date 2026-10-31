class_name MapAnimation
extends Resource
## A UV or texture animation track with resolved polygon targets.

## Stored source offset.
@export var source_offset: int = 0
## Stored type.
@export var type: int = 0
## Stored delta u.
@export var delta_u: int = 0
## Stored delta v.
@export var delta_v: int = 0
## Stored uv frame count.
@export var uv_frame_count: int = 0
## Stored frames per texture.
@export var frames_per_texture: int = 0
## Stored texture ids.
@export var texture_ids: PackedInt32Array = PackedInt32Array()
## Stored target polygon indices.
@export var target_polygon_indices: PackedInt32Array = PackedInt32Array()
## Stored target pointers.
@export var target_pointers: PackedInt32Array = PackedInt32Array()
## Stored raw header.
@export var raw_header: PackedByteArray = PackedByteArray()
## Stored raw targets.
@export var raw_targets: PackedByteArray = PackedByteArray()
## Stored initial u.
@export var initial_u: int = 0
## Stored initial v.
@export var initial_v: int = 0
## Stored initial uv count.
@export var initial_uv_count: int = 0
## Stored initial cel.
@export var initial_cel: int = 0
## Stored initial cel count.
@export var initial_cel_count: int = 0
