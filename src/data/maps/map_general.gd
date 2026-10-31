class_name MapGeneral
extends Resource
## General map settings and raw camera offsets.

## Stored raw words.
@export var raw_words: PackedInt32Array = PackedInt32Array()
## Stored start grid.
@export var start_grid: Vector2i = Vector2i.ZERO
## Stored start rotation.
@export var start_rotation: int = 0
## Stored theme.
@export var theme: int = 0
## Stored time limit.
@export var time_limit: int = 0
## Stored camera source offset.
@export var camera_source_offset: Vector3i = Vector3i.ZERO
## Stored camera target offset.
@export var camera_target_offset: Vector3i = Vector3i.ZERO
