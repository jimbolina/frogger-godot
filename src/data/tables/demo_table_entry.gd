class_name DemoTableEntry
extends Resource
## One attract-mode demo row, with both lists' demo ids for its level.

## Value marking a row to skip.
const SKIP: int = -2

## Level number, or [constant SKIP].
@export var level: int = 0
## Demo resource id for high-poly levels (the only list when there is one).
@export var demo_resource_id: int = 0
## Level that must be unlocked first, or [constant SKIP].
@export var unlock_level: int = 0
## Demo resource id for low-poly levels (same as [member demo_resource_id]
## when the build has one list).
@export var low_poly_demo_resource_id: int = 0


## True when the game skips this row.
func is_skipped() -> bool:
	return level == SKIP or unlock_level == SKIP or demo_resource_id < 0


## The demo for the chosen detail level.
func demo_id(low_poly: bool = false) -> int:
	return low_poly_demo_resource_id if low_poly else demo_resource_id
