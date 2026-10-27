class_name TickEvent
extends RefCounted
## Ordered gameplay notification with typed parameters and a stable trace projection.

enum Kind {
	CAMERA_DEATH,
	CAMERA_CLOCKWISE,
	CAMERA_ANTICLOCKWISE,
	OUCH,
	SUPER_HOP,
	QUICK_HOP,
	AUTO_HOP,
	ROLL,
	HOP,
	HOP_SOUND,
	SCORE_10_REQUEST,
	SCORE_50_REQUEST,
	SCORE_5_REQUEST,
	PANT,
	DEATH_COMPLETE,
	SINGLE_FROG_DIED_REQUEST,
	FALLING,
	STUN_SOUND,
	CRASH,
	CAMERA_STUN_SHAKE,
	UNKNOWN_TERRAIN_FLAGS_IGNORED,
	DEATH_FIRE_PARTICLE_REQUEST,
	CAMERA_FIXED,
	ENTITY_SQUISH,
	ENTITY_POP_EXPLOSION_REQUEST,
	PLATFORM_ATTACHMENT,
	PLATFORM_DEPARTURE,
	SLIPPING_LOOP_START,
	SLIPPING_LOOP_STOP,
	SLIDE_PARTICLES_REQUEST,
	SLIDE_PARTICLES_STOP,
	DEATH_PGEN,
	SOUND,
	MOVING,
	SPRITE,
	CREATE,
	DESTROY,
	DEATH_ANIMATION,
	PITCH_BEND,
	REWARD,
	LEVEL_TRANSITION,
}

const TRACE_NAMES: PackedStringArray = ["camera_death", "camera_clockwise", "camera_anticlockwise", "ouch", "super_hop", "quick_hop", "auto_hop", "roll", "hop", "hop_sound", "score_10_request", "score_50_request", "score_5_request", "pant", "death_complete", "single_frog_died_request", "falling", "stun_sound", "crash", "camera_stun_shake", "unknown_terrain_flags_ignored", "death_fire_particle_request", "camera_fixed", "entity_squish", "entity_pop_explosion_request", "platform_attachment", "platform_departure", "slipping_loop_start", "slipping_loop_stop", "slide_particles_request", "slide_particles_stop", "death_pgen", "sound", "moving", "sprite", "create", "destroy", "death_animation", "pitch_bend", "reward", "level_transition"]

var reward_id: int = -1
var flow_phase: int = -1
var checkpoint_index: int = -1
var kind: Kind = Kind.HOP
var entity_index: int = -1
var sound_id: int = 0
var position: Vector3i = Vector3i.ZERO
var minimum_distance: int = 0
var maximum_distance: int = 0
var velocity: Vector2i = Vector2i.ZERO
var generation: int = 0
var pitch: int = 64
var animation_id: int = 0

## Records a source reward request at the entity-update boundary.
static func reward(id: int) -> TickEvent:
	var result: TickEvent = make(Kind.REWARD)
	result.reward_id = id
	return result

## Records a committed level-flow transition and its optional checkpoint.
static func transition(phase: int, checkpoint: int = -1) -> TickEvent:
	var result: TickEvent = make(Kind.LEVEL_TRANSITION)
	result.flow_phase = phase
	result.checkpoint_index = checkpoint
	return result

## Creates a notification without parameters.
static func make(event_kind: Kind) -> TickEvent:
	var result := TickEvent.new()
	result.kind = event_kind
	return result

## Requests a sound at the supplied source-relative position.
static func sound(id: int, origin: Vector3i = Vector3i.ZERO) -> TickEvent:
	var result: TickEvent = make(Kind.SOUND)
	result.sound_id = id
	result.position = origin
	return result

## Requests the entity-owned moving sound with its audible distance bounds.
static func moving_sound(id: int, near_distance: int, far_distance: int) -> TickEvent:
	var result: TickEvent = make(Kind.MOVING)
	result.sound_id = id
	result.minimum_distance = near_distance
	result.maximum_distance = far_distance
	return result

## Requests a pitch update for the entity's logical moving sound.
static func pitch_bend(value: int) -> TickEvent:
	var result: TickEvent = make(Kind.PITCH_BEND)
	result.pitch = value
	return result

## Requests a sprite with source-relative position and movement parameters.
static func sprite(origin: Vector3i, movement: Vector2i) -> TickEvent:
	var result: TickEvent = make(Kind.SPRITE)
	result.position = origin
	result.velocity = movement
	return result

## Records creation or retirement of an authored entity generation.
static func lifecycle(event_kind: Kind, index: int, instance: int) -> TickEvent:
	var result: TickEvent = make(event_kind)
	result.entity_index = index
	result.generation = instance
	return result

## Requests the selected frog death animation.
static func death_animation(id: int) -> TickEvent:
	var result: TickEvent = make(Kind.DEATH_ANIMATION)
	result.animation_id = id
	return result

## Detaches a request and associates it with an authored entity.
func for_entity(index: int) -> TickEvent:
	var result: TickEvent = copy()
	result.entity_index = index
	return result

## Copies every parameter without retaining mutable containers.
func copy() -> TickEvent:
	var result := TickEvent.new()
	result.reward_id = reward_id
	result.flow_phase = flow_phase
	result.checkpoint_index = checkpoint_index
	result.kind = kind
	result.entity_index = entity_index
	result.sound_id = sound_id
	result.position = position
	result.minimum_distance = minimum_distance
	result.maximum_distance = maximum_distance
	result.velocity = velocity
	result.generation = generation
	result.pitch = pitch
	result.animation_id = animation_id
	return result

## Preserves the existing external trace spelling and parameter order.
func to_trace_line() -> String:
	var line: String = TRACE_NAMES[kind]
	match kind:
		Kind.REWARD:
			line += ":%d" % reward_id
		Kind.LEVEL_TRANSITION:
			line += ":%d:%d" % [flow_phase, checkpoint_index]
		Kind.PITCH_BEND:
			line += ":%d" % pitch
		Kind.SOUND:
			line += ":%d:%d:%d:%d" % [sound_id, position.x, position.y, position.z]
		Kind.MOVING:
			line += ":%d:%d:%d" % [sound_id, minimum_distance, maximum_distance]
		Kind.SPRITE:
			line += ":%d:%d:%d:%d:%d" % [position.x, position.y, position.z, velocity.x, velocity.y]
		Kind.CREATE, Kind.DESTROY:
			return line + ":%d:%d" % [entity_index, generation]
		Kind.DEATH_ANIMATION:
			line += "_%d" % animation_id
	return "entity:%d:%s" % [entity_index, line] if entity_index >= 0 else line

## Projects an ordered outbox for traces and inspection readouts.
static func trace_lines(events: Array[TickEvent]) -> Array[String]:
	var result: Array[String] = []
	for event: TickEvent in events:
		result.append(event.to_trace_line())
	return result

## Detaches an ordered outbox at an ownership boundary.
static func copy_all(events: Array[TickEvent]) -> Array[TickEvent]:
	var result: Array[TickEvent] = []
	for event: TickEvent in events:
		result.append(event.copy())
	return result
