class_name RunSnapshot
extends RefCounted
## Detached authoritative terrain state. Positions and velocities use integer 16.16.

var tick_index: int = 0
var entities: EntityRunSnapshot = null
var entity_hit_indices: PackedInt32Array = PackedInt32Array()
var death_entity_index: int = -1
## Authored attachment identities; local coordinates remain in the source entity frame.
var current_entity_index: int = -1
var forbidden_entity_index: int = -1
var entity_cell: Vector2i = Vector2i.ZERO
var entity_offset_16: Vector3i = Vector3i.ZERO
var entity_angle: int = 0
var entity_transform12: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var entity_carry_indices: PackedInt32Array = PackedInt32Array()
var position_16: Vector3i = Vector3i.ZERO
var velocity_16: Vector3i = Vector3i.ZERO
var cell: Vector2i = Vector2i.ZERO
var remaining_ticks: int = 0
var flags: int = 2049
var mode: int = 0
var current_input: int = 0
var direction: int = 0
var buffered_keys: int = 0
var buffered_input_count: int = 0
var animation_requests: int = 0
var sound_requests: int = 0
var score_requests: int = 0
## Internal continuation values are copied too; callers cannot alter the run.
var buffered_direction: int = 0
var target_16: Vector3i = Vector3i.ZERO
var square_index: int = -1
var powerup_flags: int = 0
var old_y: int = 0
var target_y: int = 0
## Cached C transform translation can temporarily differ from position after death-height clamp.
var world_position: Vector3i = Vector3i.ZERO
var fixture_lives: int = 3
## Life/mainloop outcomes are requests; P10 owns their application.
var life_decrement_requested: bool = false
var death_count: int = 0
var death_equate: int = 0
var game_mode_request: int = -1
var completed: bool = false
var camera: GameplayCameraSnapshot = null
var animation: FrogAnimationState = null
var rng_state: int = 1
var animation_condition_counter: int = 0
var no_input_timer: int = 0
var start_timer: int = 0
var old_position_16: Vector3i = Vector3i.ZERO
## Source row-major 12-bit rotation followed by whole-unit translation.
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var user_target_cell: Vector2i = Vector2i.ZERO
var quick_jump_timer: int = 0
var auto_hop_timer: int = 0
var super_tongue_timer: int = 0
var shadow_hidden: bool = false
var source_id: String = ""
var resource_id: int = -1
var map_index: int = -1
var last_animation_request: int = -1
var death_fire_requested: bool = false
var death_scale_colour: Vector3i = Vector3i(-1, -1, -1)
var square_flags: int = 0
var square_source_offset: int = -1
var polygon_index: int = -1
var polygon_source_offset: int = -1
var destination_cell: Vector2i = Vector2i.ZERO
var initial_cell: Vector2i = Vector2i.ZERO
var start_mode: int = 0
var start_target_16: int = 0
var rng_draw_count: int = 0

## Makes an independently mutable value snapshot.
func copy() -> RunSnapshot:
	var result := RunSnapshot.new()
	result.tick_index = tick_index
	result.entities = entities.copy() if entities != null else null
	result.entity_hit_indices = entity_hit_indices.duplicate()
	result.death_entity_index = death_entity_index
	result.current_entity_index = current_entity_index
	result.forbidden_entity_index = forbidden_entity_index
	result.entity_cell = entity_cell
	result.entity_offset_16 = entity_offset_16
	result.entity_angle = entity_angle
	result.entity_transform12 = entity_transform12.duplicate()
	result.entity_carry_indices = entity_carry_indices.duplicate()
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
	result.animation_requests = animation_requests
	result.sound_requests = sound_requests
	result.score_requests = score_requests
	result.buffered_direction = buffered_direction
	result.target_16 = target_16
	result.square_index = square_index
	result.powerup_flags = powerup_flags
	result.old_y = old_y
	result.target_y = target_y
	result.world_position = world_position
	result.fixture_lives = fixture_lives
	result.life_decrement_requested = life_decrement_requested
	result.death_count = death_count
	result.death_equate = death_equate
	result.game_mode_request = game_mode_request
	result.completed = completed
	result.camera = camera.copy() if camera != null else null
	result.animation = animation.copy() if animation != null else null
	result.rng_state = rng_state
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
	result.source_id = source_id
	result.resource_id = resource_id
	result.map_index = map_index
	result.last_animation_request = last_animation_request
	result.death_fire_requested = death_fire_requested
	result.death_scale_colour = death_scale_colour
	result.square_flags = square_flags
	result.square_source_offset = square_source_offset
	result.polygon_index = polygon_index
	result.polygon_source_offset = polygon_source_offset
	result.destination_cell = destination_cell
	result.initial_cell = initial_cell
	result.start_mode = start_mode
	result.start_target_16 = start_target_16
	result.rng_draw_count = rng_draw_count
	return result
