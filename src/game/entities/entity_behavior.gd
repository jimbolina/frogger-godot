class_name EntityBehavior
extends RefCounted
## Resolved entity implementation and capabilities, independent of source names.

enum Kind { UNKNOWN, STATIC, PATH_FOLLOWER, TURTLE, BABY_FROG, BONUS_FLY, CHECKPOINT, STATIC_NOISE, BOUNDS_TOP_LEFT, BOUNDS_BOTTOM_RIGHT }
enum Layout { NONE, MATRIX, PATH }
enum Execution { TRANSFORM, UPDATE, CONTACT }

var kind: Kind = Kind.UNKNOWN
var layout: Layout = Layout.NONE
var execution: Execution = Execution.TRANSFORM
var immortal: bool = false
var group_moving: bool = false
var one_shot: bool = false
var payload_offset: int = 0
var payload_register_count: int = 0

## Whether this definition executes a custom update in the current run.
func has_custom_update() -> bool:
	return execution >= Execution.UPDATE and kind in [Kind.BABY_FROG, Kind.BONUS_FLY, Kind.CHECKPOINT, Kind.STATIC_NOISE, Kind.BOUNDS_TOP_LEFT, Kind.BOUNDS_BOTTOM_RIGHT]

## Whether the implemented contact rule may run for this entity.
func has_form_contact() -> bool:
	return kind in [Kind.STATIC, Kind.PATH_FOLLOWER, Kind.TURTLE] or (kind == Kind.BABY_FROG and execution == Execution.CONTACT)

## Detaches setup capabilities before the run retains them.
func copy() -> EntityBehavior:
	var result := EntityBehavior.new()
	result.kind = kind
	result.layout = layout
	result.execution = execution
	result.immortal = immortal
	result.group_moving = group_moving
	result.one_shot = one_shot
	result.payload_offset = payload_offset
	result.payload_register_count = payload_register_count
	return result
