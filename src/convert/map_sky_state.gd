class_name MapSkyState
extends RefCounted
## UpdateSkyLand integer drift, independent of future gameplay RNG.
## MR_SYS.H maps rand to MRrand; this local stream defaults to seed zero.
## Inject random_source to share a future gameplay stream with other consumers.

var tick: int = -1
var seed: int = 0
var random_source: Callable
var position: Vector3i = Vector3i.ZERO
var velocity: Vector3i = Vector3i.ZERO
var acceleration: Vector3i = Vector3i.ZERO
var random_state: int = 0


## Restores load-time drift and this instance's configured RNG seed.
func reset() -> void:
	tick = -1
	position = Vector3i.ZERO
	velocity = Vector3i.ZERO
	acceleration = Vector3i.ZERO
	random_state = seed & 0xffffffff


## Timer increments before UpdateSkyLand: first visible update is timer one.
func step() -> void:
	tick += 1
	var timer: int = tick + 1
	if not (timer & 127):
		var direction := Vector3i.ZERO
		if absi(position.x >> 16) > 0xb00 or absi(position.z >> 16) > 0xb00:
			direction = Vector3i(-position.x >> 16, -position.y >> 16, -position.z >> 16)
		else:
			direction = Vector3i(_random() & 1023, 0, _random() & 1023)
		var length: float = Vector3(direction).length()
		if length > 0.0:
			acceleration = Vector3i(roundi(float(direction.x) * 4096.0 / length),
				roundi(float(direction.y) * 4096.0 / length),
				roundi(float(direction.z) * 4096.0 / length)) * 8
		else:
			acceleration = Vector3i.ZERO
	elif (timer & 255) < 0x60:
		velocity += acceleration
	else:
		velocity = Vector3i((velocity.x >> 5) * 31, (velocity.y >> 5) * 31,
			(velocity.z >> 5) * 31)
	position += velocity
	position.x = clampi(position.x, -0x10000000, 0x10000000)
	position.z = clampi(position.z, -0x10000000, 0x10000000)


## Restarts and replays this deterministic seed; injected RNG must rewind itself.
func seek(to_tick: int) -> void:
	reset()
	for _index: int in maxi(0, to_tick + 1):
		step()


## Integer game-space translation used by the sky backdrop's camera matrix.
func translation() -> Vector3i:
	return Vector3i(position.x >> 16, position.y >> 16, position.z >> 16)


func _random() -> int:
	if random_source.is_valid():
		var result: int = random_source.call()
		return result
	random_state = (random_state * 0x41c64e6d + 0x3039) & 0xffffffff
	return (random_state >> 16) & 32767
