class_name EntityJungleDefinition
extends RefCounted
## Detached Jungle plant, rope-bridge, outro-plinth and outro-target operands from FrogLord payloads.

## Source JUN_OUTRO_ENTITY target count for the retail build.
const OUTRO_TARGET_COUNT: int = 11
## Source JUN_GOLD_FROG_STATUE_ID: the plinth-frog id of the visible outro gold frog statue.
const GOLD_FROG_STATUE_ID: int = 8

## Signed jp_snap_time and jp_snap_delay.
var snap_time: int = 0
var snap_delay: int = 0
## Unsigned rb_fall_delay and rb_hops_before.
var fall_delay: int = 0
var hops_before: int = 0
## Signed op_id of an outro plinth, gold frog or stone frog.
var op_id: int = 0
## Outro target positions from signed MR_SVEC components, with unsigned ot_time values.
var outro_targets: Array[Vector3i] = []
var outro_times: PackedInt64Array = PackedInt64Array()

## Copies authored operands without sharing target or time arrays.
func copy() -> EntityJungleDefinition:
	var result := EntityJungleDefinition.new()
	result.snap_time = snap_time
	result.snap_delay = snap_delay
	result.fall_delay = fall_delay
	result.hops_before = hops_before
	result.op_id = op_id
	result.outro_targets = outro_targets.duplicate()
	result.outro_times = outro_times.duplicate()
	return result
