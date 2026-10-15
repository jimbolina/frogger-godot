class_name EntityBackgroundState
extends RefCounted
## Owned custom state for the admitted fly and baby-parent invariant.

var mode: int = 0
var timer: int = 60
var checkpoint_index: int = -1
var search_count: int = 0
var model_hidden: bool = false

## Copies every custom continuation value.
func copy() -> EntityBackgroundState:
	var result := EntityBackgroundState.new()
	result.mode = mode
	result.timer = timer
	result.checkpoint_index = checkpoint_index
	result.search_count = search_count
	result.model_hidden = model_hidden
	return result
