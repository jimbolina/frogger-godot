class_name PathInspectionSession
extends RefCounted
## Seekable path inspection timeline, independent of gameplay pacing.

var runner: PathRunner
var start: PathStart

## Replaces the selected path only after its start validates.
func configure(definition: PathDefinition, requested: PathStart) -> String:
	var candidate: PathRunner = PathRunner.create(definition, requested)
	if not candidate.error.is_empty():
		return candidate.error
	runner = candidate
	start = requested.copy()
	return ""

## Replays from the selected initial state to an absolute inspection tick.
func seek(tick: int) -> String:
	if runner == null or start == null:
		return ""
	var issue: String = runner.reset(start)
	if issue.is_empty():
		for index: int in tick:
			issue = runner.step(index)
			if not issue.is_empty():
				break
	return issue

## Advances one source tick without changing the inspection clock policy.
func step(tick: int) -> String:
	return runner.step(tick) if runner != null else ""

## Returns detached state for drawing and trace output.
func snapshot() -> PathSnapshot:
	return runner.snapshot() if runner != null else null

## Releases the selected timeline.
func clear() -> void:
	runner = null
	start = null
