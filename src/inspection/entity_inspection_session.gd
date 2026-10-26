class_name EntityInspectionSession
extends RefCounted
## Seekable entity inspection timeline with detached setup ownership.

var run: EntityRun
var definitions: Array[EntityDefinition] = []

## Accepts definitions only after the replacement run validates.
func configure(values: Array[EntityDefinition]) -> String:
	var copies: Array[EntityDefinition] = []
	for definition: EntityDefinition in values:
		copies.append(definition.copy() if definition != null else null)
	var candidate: EntityRun = EntityRun.create(copies)
	if not candidate.error.is_empty():
		return candidate.error
	definitions = copies
	run = candidate
	return ""

## Replays to an absolute tick, including backward inspection seeks.
func seek(tick: int) -> String:
	if run == null:
		return ""
	var issue: String = run.reset()
	if issue.is_empty():
		for index: int in tick:
			issue = run.step(index)
			if not issue.is_empty():
				break
	return issue

## Advances one source tick under the viewer's independent clock.
func step(tick: int) -> String:
	return run.step(tick) if run != null else ""

## Returns detached entity state.
func snapshot() -> EntityRunSnapshot:
	return run.snapshot() if run != null else null

## Releases the inspection timeline and its definitions.
func clear() -> void:
	run = null
	definitions.clear()
