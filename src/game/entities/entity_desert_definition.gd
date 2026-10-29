class_name EntityDesertDefinition
extends RefCounted
## Detached Desert falling-rock, croc-head and crack operands from FrogLord payloads.

## Source DESERT_FALLING_ROCK_TARGETS_RESOLVED value that skips target projection.
const TARGETS_RESOLVED: int = 1
## Source fr_targets capacity.
const MAX_ROCK_TARGETS: int = 12

var rock_delay: int = 0
## Authored targets after setup; landscape-projected targets once rock_targets_resolved is true.
var rock_targets: Array[Vector3i] = []
var rock_times: PackedInt32Array = PackedInt32Array()
var rock_bounces: int = 0
## Signed fr_flags; the source projects targets unless it equals TARGETS_RESOLVED.
var rock_flags: int = 0
var rock_targets_resolved: bool = false
var rise_height: int = 0
var rise_speed: int = 0
var snap_delay: int = 0
var pause_delay: int = 0
var snap_flag: int = 0
var submerged_delay: int = 0
var fall_delay: int = 0
var hops_before: int = 0
## Action lengths of the map WAD slot-1 explosion flipbook the falling and rolling rocks play.
var explosion_action_lengths: PackedInt32Array = PackedInt32Array()

## Copies authored operands without sharing target, time or action arrays.
func copy() -> EntityDesertDefinition:
	var result := EntityDesertDefinition.new()
	result.rock_delay = rock_delay
	result.rock_targets = rock_targets.duplicate()
	result.rock_times = rock_times.duplicate()
	result.rock_bounces = rock_bounces
	result.rock_flags = rock_flags
	result.rock_targets_resolved = rock_targets_resolved
	result.rise_height = rise_height
	result.rise_speed = rise_speed
	result.snap_delay = snap_delay
	result.pause_delay = pause_delay
	result.snap_flag = snap_flag
	result.submerged_delay = submerged_delay
	result.fall_delay = fall_delay
	result.hops_before = hops_before
	result.explosion_action_lengths = explosion_action_lengths.duplicate()
	return result
