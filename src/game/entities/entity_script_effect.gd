class_name EntityScriptEffect
extends RefCounted
## One ordered script notification or immediate frog-death operation.

var applied: bool = false
var notification: TickEvent = null
var death_animation: int = -1
var eject: bool = false
var grid_delta: int = 0
var jump_duration: int = 0

## Detaches a notification while retaining its place among frog operations.
static func event(value: TickEvent) -> EntityScriptEffect:
	var result := EntityScriptEffect.new()
	result.notification = value.copy()
	return result

## Records a source FrogKill call without changing a published frog.
static func death(animation: int) -> EntityScriptEffect:
	var result := EntityScriptEffect.new()
	result.death_animation = animation
	return result

## Records a source forced jump or zero-duration freefall in effect order.
static func ejection(delta: int, duration: int) -> EntityScriptEffect:
	var result := EntityScriptEffect.new()
	result.eject = true
	result.grid_delta = delta
	result.jump_duration = duration
	return result
