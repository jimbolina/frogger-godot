class_name FrogState
extends RefCounted
## Frog kinematics, control, timers and source collision pose.

var camera_zone_index: int = -1
var camera_zone_region_index: int = -1
var position_16: Vector3i = Vector3i.ZERO
var velocity_16: Vector3i = Vector3i.ZERO
var cell: Vector2i = Vector2i.ZERO
var remaining_ticks: int = 0
var flags: int = FrogFlags.ACTIVE | FrogFlags.CONTROL_ACTIVE
var mode: int = FrogMode.STATIONARY
var current_input: int = 0
var direction: int = 0
var buffered_keys: int = 0
var buffered_input_count: int = 0
var buffered_direction: int = 0
var target_16: Vector3i = Vector3i.ZERO
var square_index: int = -1
var powerup_flags: int = 0
var old_y: int = 0
var target_y: int = 0
var world_position: Vector3i = Vector3i.ZERO
var lives: int = 3
var death_count: int = 0
var death_equate: int = 0
var frog_collision_pose: FrogCollisionPose = null
var animation_condition_counter: int = 0
var no_input_timer: int = 0
var start_timer: int = 0
var old_position_16: Vector3i = Vector3i.ZERO
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var user_target_cell: Vector2i = Vector2i.ZERO
var quick_jump_timer: int = 0
var auto_hop_timer: int = 0
var super_tongue_timer: int = 0
var shadow_hidden: bool = false
var square_flags: int = 0
var destination_cell: Vector2i = Vector2i.ZERO
var initial_cell: Vector2i = Vector2i.ZERO
var start_mode: int = 0
var start_target_16: int = 0

## Returns an independently mutable copy of every value.
func copy() -> FrogState:
	var result := FrogState.new()
	result.camera_zone_index = camera_zone_index
	result.camera_zone_region_index = camera_zone_region_index
	result.position_16 = position_16
	result.velocity_16 = velocity_16
	result.cell = cell
	result.remaining_ticks = remaining_ticks
	result.flags = flags
	result.mode = mode
	result.current_input = current_input
	result.direction = direction
	result.buffered_keys = buffered_keys
	result.buffered_input_count = buffered_input_count
	result.buffered_direction = buffered_direction
	result.target_16 = target_16
	result.square_index = square_index
	result.powerup_flags = powerup_flags
	result.old_y = old_y
	result.target_y = target_y
	result.world_position = world_position
	result.lives = lives
	result.death_count = death_count
	result.death_equate = death_equate
	result.frog_collision_pose = frog_collision_pose.copy() if frog_collision_pose != null else null
	result.animation_condition_counter = animation_condition_counter
	result.no_input_timer = no_input_timer
	result.start_timer = start_timer
	result.old_position_16 = old_position_16
	result.matrix12 = matrix12.duplicate()
	result.user_target_cell = user_target_cell
	result.quick_jump_timer = quick_jump_timer
	result.auto_hop_timer = auto_hop_timer
	result.super_tongue_timer = super_tongue_timer
	result.shadow_hidden = shadow_hidden
	result.square_flags = square_flags
	result.destination_cell = destination_cell
	result.initial_cell = initial_cell
	result.start_mode = start_mode
	result.start_target_16 = start_target_16
	return result
