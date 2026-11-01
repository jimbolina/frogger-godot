class_name MapSkyState
extends RefCounted
## Render-timeline UpdateSkyLand drift for the map viewer, sharing SkyDriftState's integer math.
## MR_SYS.H maps rand to MRrand; this local stream defaults to seed zero.
## Inject random_source to draw from another stream instead of the local one.

var tick: int = -1
var seed: int = 0
var random_source: Callable
var position: Vector3i:
	get:
		return _drift.position
var velocity: Vector3i:
	get:
		return _drift.velocity
var acceleration: Vector3i:
	get:
		return _drift.acceleration
var random_state: int:
	get:
		return _random.state
var _drift := SkyDriftState.new()
var _random: SourceRandom = SourceRandom.create(0)
var _injected := InjectedRandom.new()


## Labelled draws served by the injected random_source instead of the local LCG.
class InjectedRandom extends SourceRandom:
	var source: Callable

	## Records the consumer and returns the injected source's next value.
	func next_value(consumer: String = "unlabelled") -> int:
		draw_count += 1
		consumers.append(consumer)
		var result: int = source.call()
		return result


## Restores load-time drift and this instance's configured RNG seed.
func reset() -> void:
	tick = -1
	_drift.clear()
	_random = SourceRandom.create(seed)


## Timer increments before UpdateSkyLand: first visible update is timer one.
func step() -> void:
	tick += 1
	_injected.source = random_source
	_drift.step(tick + 1, _injected if random_source.is_valid() else _random)
	_random.begin_tick()
	_injected.begin_tick()


## Restarts and replays this deterministic seed; injected RNG must rewind itself.
func seek(to_tick: int) -> void:
	reset()
	for _index: int in maxi(0, to_tick + 1):
		step()


## Integer game-space translation used by the sky backdrop's camera matrix.
func translation() -> Vector3i:
	return _drift.translation()

