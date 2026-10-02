class_name PathStart
extends RefCounted
## Initial path-runner fields for a detached component inspection.

const ACTIVE: int = 1
const BACKWARDS: int = 2
const ONE_SHOT: int = 4
const REPEAT: int = 8
const AT_END: int = 16
const JUST_BOUNCED_START: int = 1 << 16
const JUST_BOUNCED_END: int = 1 << 17
const JUST_REPEATED_START: int = 1 << 18
const JUST_REPEATED_END: int = 1 << 19
const JUST_HIT_START: int = 1 << 20
const JUST_HIT_END: int = 1 << 21
const JUST_CLEAR_MASK: int = 0x3f0000
const ALL_FLAGS: int = ACTIVE | BACKWARDS | ONE_SHOT | REPEAT | AT_END | JUST_CLEAR_MASK

var segment_index: int = 0
var distance: int = 0
var speed: int = 16
var flags: int = ACTIVE | REPEAT

## Returns an independent copy of the component start.
func copy() -> PathStart:
	var result := PathStart.new()
	result.segment_index = segment_index
	result.distance = distance
	result.speed = speed
	result.flags = flags
	return result
