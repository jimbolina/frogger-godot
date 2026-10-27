class_name TongueState
extends RefCounted
## Detached source tongue effect clock and target identity.

enum Mode { IDLE, OUT, GRAB, IN }
var mode: Mode = Mode.IDLE
var target_index: int = -1
var section: int = 0
var counter: int = 0
var tip: Vector3i = Vector3i.ZERO
var curve_target: Vector3i = Vector3i.ZERO
var curve_has_target: bool = false

## Starts a disabled tongue; active effects cannot be restarted by input.
func start(entity_index: int) -> bool:
	if mode != Mode.IDLE:
		return false
	mode = Mode.OUT
	target_index = entity_index
	section = 0
	counter = 0
	return true

## Advances one source effect update and returns a collected entity exactly once.
func advance() -> int:
	match mode:
		Mode.OUT:
			section += 1
			if section == 8:
				mode = Mode.GRAB
				counter = 4 if target_index >= 0 else 8
		Mode.GRAB:
			counter -= 1
			if counter == 0:
				mode = Mode.IN
		Mode.IN:
			section -= 1
			if section == 0:
				mode = Mode.IDLE
				var collected: int = target_index
				target_index = -1
				return collected
	return -1

## Resets effect ownership without changing the former target's source flags.
func reset() -> void:
	mode = Mode.IDLE
	target_index = -1
	section = 0

## Detaches the effect for a gameplay transaction or observer.
func copy() -> TongueState:
	var result := TongueState.new()
	result.mode = mode
	result.target_index = target_index
	result.section = section
	result.counter = counter
	result.tip = tip
	result.curve_target = curve_target
	result.curve_has_target = curve_has_target
	return result
