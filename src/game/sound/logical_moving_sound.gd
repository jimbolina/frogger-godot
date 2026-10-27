class_name LogicalMovingSound
extends RefCounted
## Source moving object, retained even when radius or voice pressure prevents playback.

var generation: int = 0
var owner: int = -1
var sound_id: int = 0
var near_radius: int = 256
var far_radius: int = 768
var voice_tag: int = -1
var position: Vector3i = Vector3i.ZERO
var old_position: Vector3i = Vector3i.ZERO
var doppler: bool = true

## Copies the logical owner and source positions without presentation references.
func copy() -> LogicalMovingSound:
	var result := LogicalMovingSound.new()
	result.generation = generation
	result.owner = owner
	result.sound_id = sound_id
	result.near_radius = near_radius
	result.far_radius = far_radius
	result.voice_tag = voice_tag
	result.position = position
	result.old_position = old_position
	result.doppler = doppler
	return result
