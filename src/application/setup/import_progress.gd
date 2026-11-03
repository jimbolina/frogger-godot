class_name ImportProgress
extends RefCounted
## The progress file a setup import process writes and the setup screen reads.
##
## The file is plain text, one record per line, fields separated by a tab:
## [br][code]progress<TAB><fraction><TAB><label>[/code] as the import advances;
## [br][code]note<TAB><text>[/code] for a remark that does not fail the import;
## [br][code]problem<TAB><text>[/code] for each reason it failed;
## [br][code]done<TAB>ok[/code] or [code]done<TAB>failed[/code] as the last line.
## [br]The writer appends whole lines, so [method parse] reads only lines ended
## by a newline and ignores a line still being written. Unknown records are
## counted and otherwise ignored, so later writers may add records.

## The record kinds.
const PROGRESS: String = "progress"
const NOTE: String = "note"
const PROBLEM: String = "problem"
const DONE: String = "done"
## The values of a [constant DONE] record.
const DONE_OK: String = "ok"
const DONE_FAILED: String = "failed"
const _SEPARATOR: String = "\t"

## The last reported fraction, 0 to 1.
var fraction: float = 0.0
## The last reported label.
var label: String = ""
## The remarks, in order.
var notes := PackedStringArray()
## The reasons the import failed, in order.
var problems := PackedStringArray()
## Whether the final record was read.
var finished: bool = false
## Whether the final record said the import succeeded.
var succeeded: bool = false
## Lines that were not a known record.
var unknown_lines: int = 0


## The line reporting [param at] (clamped to 0 to 1) and [param what].
static func progress_line(at: float, what: String) -> String:
	return _line(PackedStringArray([PROGRESS, "%.4f" % clampf(at, 0.0, 1.0), what]))


## The line reporting the remark [param text].
static func note_line(text: String) -> String:
	return _line(PackedStringArray([NOTE, text]))


## The line reporting the failure [param text].
static func problem_line(text: String) -> String:
	return _line(PackedStringArray([PROBLEM, text]))


## The final line: whether the import [param ok].
static func done_line(ok: bool) -> String:
	return _line(PackedStringArray([DONE, DONE_OK if ok else DONE_FAILED]))


## Reads the complete lines of [param text].
static func parse(text: String) -> ImportProgress:
	var read := ImportProgress.new()
	var complete: String = text.substr(0, text.rfind("\n") + 1)
	for line: String in complete.split("\n", false):
		read._take(line.trim_suffix("\r"))
	return read


func _take(line: String) -> void:
	var fields: PackedStringArray = line.split(_SEPARATOR)
	match fields[0]:
		PROGRESS:
			if fields.size() >= 3 and fields[1].is_valid_float():
				fraction = maxf(fraction, clampf(fields[1].to_float(), 0.0, 1.0))
				label = fields[2]
				return
		NOTE:
			if fields.size() >= 2:
				notes.append(fields[1])
				return
		PROBLEM:
			if fields.size() >= 2:
				problems.append(fields[1])
				return
		DONE:
			if fields.size() >= 2 and (fields[1] == DONE_OK or fields[1] == DONE_FAILED):
				finished = true
				succeeded = fields[1] == DONE_OK and problems.is_empty()
				return
	unknown_lines += 1


static func _line(fields: PackedStringArray) -> String:
	var clean := PackedStringArray()
	for field: String in fields:
		clean.append(field.replace("\r", " ").replace("\n", " ").replace(_SEPARATOR, " "))
	return _SEPARATOR.join(clean) + "\n"
