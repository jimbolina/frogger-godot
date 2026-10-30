class_name HopTrailState
extends RefCounted
## The frog's movement trail: CreateTrail, ResetTrail and the EFFECT_TYPE_TRAIL update.
##
## A hop sets the trail colour to the midpoint of TRAIL_RGB_START and
## TRAIL_RGB_MAX, the timer to 16 (26 for a super jump) and a reset
## (FROG.C:1410-1446). Each [method step] follows UpdateEffects
## (EFFECTS.C:585-644): a pending reset fills every section with the current
## head pair, then a running timer counts down, ramps the colour, writes the
## head pair and moves the ring position. The trail is drawn while the timer
## is non-zero (RenderEffects, EFFECTS.C:956-1060), newest pair first, each
## older section 0x101010 darker.

const SECTIONS: int = 6
const RGB_START: int = 0x202020
const RGB_MAX: int = 0x606060
const RGB_STEP: int = 0x080808
const SECTION_FALL: int = 0x101010
const DECREASE_TIMER: int = 12
const HOP_TIMER: int = 16
const SUPERJUMP_TIMER: int = 26
## Source Frog_trail_offsets in the frog frame.
const OFFSETS: Array[Vector3i] = [Vector3i(-0x40, -0x10, -0x20), Vector3i(0x40, -0x10, -0x20)]

var timer: int = 0
## Packed colour, red in the low byte.
var rgb: int = 0
var current_section: int = SECTIONS - 2
var display_sections: int = 0
var pending_reset: bool = false
## Two s16 points per section.
var vertices: Array[Vector3i] = []


func _init() -> void:
	vertices.resize(SECTIONS * 2)
	vertices.fill(Vector3i.ZERO)


## Starts the trail as a hop does; [param superjump] selects the longer timer.
func start(superjump: bool) -> void:
	pending_reset = true
	rgb = (RGB_START + RGB_MAX) >> 1
	timer = SUPERJUMP_TIMER if superjump else HOP_TIMER


## Runs one update with the frog's committed [param matrix12].
func step(matrix12: PackedInt32Array) -> void:
	if pending_reset:
		current_section = SECTIONS - 2
		display_sections = 0
		var head: Array[Vector3i] = head_pair(matrix12)
		for section: int in SECTIONS:
			vertices[section * 2] = head[0]
			vertices[section * 2 + 1] = head[1]
		pending_reset = false
	if timer == 0:
		return
	timer -= 1
	if timer <= DECREASE_TIMER:
		if rgb != 0:
			rgb = maxi(0, rgb - RGB_STEP)
	elif rgb < RGB_MAX:
		rgb += RGB_STEP
	var pair: Array[Vector3i] = head_pair(matrix12)
	vertices[current_section * 2] = pair[0]
	vertices[current_section * 2 + 1] = pair[1]
	current_section = SECTIONS - 1 if current_section == 0 else current_section - 1
	display_sections = mini(SECTIONS - 1, display_sections + 1)


## Clears the trail without drawing, as a new frog does.
func collapse() -> void:
	timer = 0
	rgb = 0
	pending_reset = false
	current_section = SECTIONS - 2
	display_sections = 0
	vertices.fill(Vector3i.ZERO)


## True while RenderEffects draws the trail.
func drawn() -> bool:
	return timer != 0


## Drawn vertex pairs, newest first: [method display_sections] + 1 pairs.
func pairs() -> Array[Array]:
	var result: Array[Array] = []
	if not drawn():
		return result
	for offset: int in display_sections + 1:
		var section: int = (current_section + 1 + offset) % SECTIONS
		result.append([vertices[section * 2], vertices[section * 2 + 1]])
	return result


## Packed colour of each drawn pair, newest first.
func section_colours() -> PackedInt32Array:
	var result := PackedInt32Array()
	if not drawn():
		return result
	var value: int = rgb
	result.append(value)
	for _section: int in display_sections:
		value = maxi(0, value - SECTION_FALL)
		result.append(value)
	return result


## The two s16 head points in the frame of [param matrix12].
static func head_pair(matrix12: PackedInt32Array) -> Array[Vector3i]:
	var translation := Vector3i(matrix12[9], matrix12[10], matrix12[11])
	var result: Array[Vector3i] = []
	for offset: Vector3i in OFFSETS:
		var point: Vector3i = PlatformMath.apply(matrix12, offset) + translation
		result.append(Vector3i(PlatformMath.s16(point.x), PlatformMath.s16(point.y), PlatformMath.s16(point.z)))
	return result


## Stored colour bytes of packed [param value], red in the low byte.
static func bytes(value: int) -> Vector3i:
	return Vector3i(value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff)
