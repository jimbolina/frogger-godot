class_name EntityAnimationState
extends RefCounted
## Authoritative flipbook action/cel using decoded retail action lengths.

var lengths: PackedInt32Array = PackedInt32Array()
var action: int = -1
var cel: int = -1
var stepping: bool = true
var one_shot: bool = false

## Initializes the source factory's first action before its first cel advance.
static func create(action_lengths: PackedInt32Array, single_play: bool = false) -> EntityAnimationState:
	var result := EntityAnimationState.new()
	result.lengths = action_lengths.duplicate()
	result.action = 0 if not action_lengths.is_empty() else -1
	result.one_shot = single_play
	return result

## Copies clocks and lengths independently of presentation.
func copy() -> EntityAnimationState:
	var result: EntityAnimationState = EntityAnimationState.create(lengths, one_shot)
	result.stepping = stepping
	result.action = action
	result.cel = cel
	return result

## SET_ACTION restarts even when selecting the current action.
func select(next_action: int) -> void:
	action = next_action
	cel = -1

## Advances once after frog animation scripts, at the source pose phase.
func advance() -> void:
	if stepping and action >= 0:
		cel = mini(cel + 1, lengths[action] - 1) if one_shot else (cel + 1) % lengths[action]

## Whether the current action shows its last cel; false without lengths or a valid action.
func finished() -> bool:
	if action < 0 or action >= lengths.size():
		return false
	return cel >= lengths[action] - 1
