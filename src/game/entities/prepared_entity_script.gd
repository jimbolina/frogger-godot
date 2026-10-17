class_name PreparedEntityScript
extends RefCounted
## Run-owned validated programs and constant-time instruction/loop lookups.
## Caller definitions are detached once; prepared data stays private and read-only.

var error: String = ""
var _definition: EntityScriptDefinition
var _lengths: PackedInt32Array
var _form_id: int
var _has_path: bool
var _next: Dictionary[int, PackedInt32Array] = {}
var _loops: Dictionary[int, PackedInt32Array] = {}

## Validates all program dependencies before retaining an independent definition.
static func create(definition: EntityScriptDefinition, lengths: PackedInt32Array, form_id: int, has_path: bool) -> PreparedEntityScript:
	var result := PreparedEntityScript.new()
	result.error = definition.validate(lengths, form_id, has_path)
	if not result.error.is_empty():
		return result
	result._definition = definition.copy()
	result._lengths = lengths.duplicate()
	result._form_id = form_id
	result._has_path = has_path
	for id: int in result._definition.programs:
		var words: PackedInt32Array = result._definition.programs[id]
		var boundaries := PackedInt32Array()
		var loops := PackedInt32Array()
		boundaries.resize(words.size())
		boundaries.fill(-1)
		loops.resize(words.size())
		loops.fill(-1)
		var cursor: int = 0
		var loop_start: int = -1
		while cursor < words.size():
			var next: int = cursor + EntityScriptDefinition.WIDTHS[words[cursor]]
			boundaries[cursor] = next
			if words[cursor] == 11:
				loop_start = cursor
			elif words[cursor] == 12:
				loops[loop_start] = next
			cursor = next
		result._next[id] = boundaries
		result._loops[id] = loops
	return result

## Checks dependencies without rescanning immutable instruction words.
func matches(animation: EntityAnimationState, context: EntityUpdateContext) -> bool:
	return error.is_empty() and animation.lengths == _lengths and context.form_id == _form_id and context.has_path == _has_path

## Returns the following word offset or -1 for an invalid runtime cursor.
func following(program: int, cursor: int) -> int:
	if not _next.has(program) or cursor < 0 or cursor >= _next[program].size():
		return -1
	return _next[program][cursor]

## Returns the prevalidated instruction after the matching ENDLOOP.
func loop_end(program: int, cursor: int) -> int:
	return _loops[program][cursor]
