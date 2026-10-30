class_name EntityCustomState
extends RefCounted
## Owned custom continuation for the supported custom entity behaviors.

var initialized: bool = false
var no_frog_contact: bool = false
var texture_animation_paused: bool = false
var texture_animation_cel: int = -1
var swarm: EntitySwarmState = null
var mode: int = 0
var timer: int = 60
var home: bool = false
var checkpoint_index: int = -1
var search_count: int = 0
var model_hidden: bool = false
var parent_entity_index: int = -1
var direction: int = 0
var delay: int = 0
var count: int = 0
var cell: Vector2i = Vector2i.ZERO
var offset_16: Vector3i = Vector3i.ZERO
var velocity_16: Vector3i = Vector3i.ZERO
var target: Vector3i = Vector3i.ZERO
## Source moving-sound voice allocation, independent of presentation playback.
var moving_voice_active: bool = false
var moving_sound: PackedInt32Array = PackedInt32Array()
var carrier_index: int = -1
var carried_jump_ticks: int = 0
var dead: bool = false
var shadow_visible: bool = false
## Secondary flipbook, such as a rock explosion, drawn at overlay_position instead of the entity model.
var overlay_animation: EntityAnimationState = null
var overlay_position: Vector3i = Vector3i.ZERO
## Action awaiting the current action's last cel; -1 when none is requested.
var requested_action: int = -1
var deadly: bool = false
## Swamp rat ra_pos in <<4 fixed point, signed 32-bit per axis.
var position_4: Vector3i = Vector3i.ZERO
## Swamp rat ra_prev_y, the <<4 jump height before the sine lift.
var previous_y: int = 0
## Swamp rat ra_jump1_sin_pos and ra_jump2_sin_pos.
var sine_positions: Vector2i = Vector2i.ZERO
## Swamp rat ra_has_sprite: the second jump has reached the splash height since the last restart.
var splashed: bool = false

## Copies every custom continuation value.
func copy() -> EntityCustomState:
	var result := EntityCustomState.new()
	result.initialized = initialized
	result.no_frog_contact = no_frog_contact
	result.texture_animation_paused = texture_animation_paused
	result.texture_animation_cel = texture_animation_cel
	result.swarm = swarm.copy() if swarm != null else null
	result.mode = mode
	result.timer = timer
	result.home = home
	result.checkpoint_index = checkpoint_index
	result.search_count = search_count
	result.model_hidden = model_hidden
	result.parent_entity_index = parent_entity_index
	result.direction = direction
	result.delay = delay
	result.count = count
	result.cell = cell
	result.offset_16 = offset_16
	result.velocity_16 = velocity_16
	result.target = target
	result.moving_voice_active = moving_voice_active
	result.moving_sound = moving_sound.duplicate()
	result.carrier_index = carrier_index
	result.carried_jump_ticks = carried_jump_ticks
	result.dead = dead
	result.shadow_visible = shadow_visible
	result.overlay_animation = overlay_animation.copy() if overlay_animation != null else null
	result.overlay_position = overlay_position
	result.requested_action = requested_action
	result.deadly = deadly
	result.position_4 = position_4
	result.previous_y = previous_y
	result.sine_positions = sine_positions
	result.splashed = splashed
	return result
