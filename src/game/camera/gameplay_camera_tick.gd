class_name GameplayCameraTick
extends RefCounted
## Explicit frog/camera inputs for one source-ordered camera update after movement.

var frog_world: Vector3i = Vector3i.ZERO
var frog_mode: int = 0
var remaining_ticks: int = 0
var old_y: int = 0
var target_y: int = 0
var freefall: bool = false
var superjump: bool = false
var start_timer: int = 0
var ignore_frog_y: bool = false
## Unsupported branches are explicit instead of silently approximated.
var has_camera_zone: bool = false
var on_entity: bool = false
var shaking: bool = false
