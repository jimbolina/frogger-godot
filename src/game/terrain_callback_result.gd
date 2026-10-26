class_name TerrainCallbackResult
extends RefCounted
## Explicit source callback outputs; GameplayRun applies requests in source order.

const UPDATE_POS: int = 1
const UPDATE_OLD_POS: int = 2
const REACT_WITH_FLAGS: int = 4
const UPDATE_MATRIX: int = 8

var error: String = ""
var callback_flags: int = 0
var react_flags: int = 0
var animation_ids: Array[int] = []
var kill_animation: int = -1
var create_slide_particles: bool = false
var kill_looping_sound: bool = false
var start_slipping_sound: bool = false
var jump_requested: bool = false
var jump_direction: int = 0
var jump_flags: int = 0
var jump_distance: int = 0
var jump_duration: int = 0
var setup_mode_request: int = -1
var land_requested: bool = false
var kill_slide_particles: bool = false
var forward_steering: bool = false
