class_name MapGeneral
extends RefCounted
## General map settings and raw camera offsets.

## Stored raw words.
var raw_words: PackedInt32Array = PackedInt32Array()
## Stored start grid.
var start_grid: Vector2i = Vector2i.ZERO
## Stored start rotation.
var start_rotation: int = 0
## Stored theme.
var theme: int = 0
## Stored time limit.
var time_limit: int = 0
## Stored camera source offset.
var camera_source_offset: Vector3i = Vector3i.ZERO
## Stored camera target offset.
var camera_target_offset: Vector3i = Vector3i.ZERO
