class_name SourceRandom
extends RefCounted
## Explicit frozen MRrand unsigned 32-bit state shared by ordered game consumers.

var state: int = 0
var draw_count: int = 0
var consumers: Array[String] = []

## Creates a stream with the supplied seed; no clock or global random source is used.
static func create(seed: int) -> SourceRandom:
	var stream := SourceRandom.new()
	stream.state = seed & 4294967295
	return stream

## Advances exactly one source LCG step and returns its high 15 bits.
func next_value(consumer: String = "unlabelled") -> int:
	state = (state * 1103515245 + 12345) & 4294967295
	draw_count += 1
	consumers.append(consumer)
	return (state >> 16) & 32767

## Clears per-tick diagnostics while preserving the stream and total draw count.
func begin_tick() -> void:
	consumers.clear()

## Copies state for a transactional candidate tick.
func copy() -> SourceRandom:
	var result: SourceRandom = SourceRandom.create(state)
	result.draw_count = draw_count
	result.consumers.assign(consumers)
	return result
