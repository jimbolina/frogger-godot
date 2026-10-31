class_name HighScoreStore
extends RefCounted
## The port's own high-score file: the main table and three rows for each level.
##
## The fields mirror [HighScoreTable] so tables copy straight across. The
## store holds no default scores: when [member present] is false the caller
## fills it from the executable's tables. A missing file is not an error. An
## unreadable, malformed or other-version file leaves [member present] false
## and sets [member error]. Saving validates first, then writes a temporary
## file beside the target and renames it over the target, so an interrupted
## save leaves the previous file intact.

## Default save file.
const DEFAULT_PATH: String = "user://high_scores.cfg"
## Version written to and expected in the file.
const FORMAT_VERSION: int = 1
## Highest checkpoint time (an unsigned 16-bit count of whole seconds).
const MAX_TIME: int = 0xffff
const _TEMP_SUFFIX: String = ".tmp"
const _META: String = "meta"
const _MAIN: String = "main"
const _LEVELS: String = "levels"

## True when the values came from a valid file.
var present: bool = false
## Main-table initials, best first.
var main_initials: PackedStringArray = PackedStringArray()
## Main-table scores, best first.
var main_scores: PackedInt32Array = PackedInt32Array()
## Main-table checkpoint times, five per row.
var main_times: PackedInt32Array = PackedInt32Array()
## Per-level initials, index [code]level * 3 + rank[/code].
var level_initials: PackedStringArray = PackedStringArray()
## Per-level scores, index [code]level * 3 + rank[/code].
var level_scores: PackedInt32Array = PackedInt32Array()
## Per-level checkpoint times, five per row.
var level_times: PackedInt32Array = PackedInt32Array()
## Why the last load found no usable file, or "".
var error: String = ""


## Reads [param path]; any problem yields an empty store that is not [member present].
static func load_from(path: String = DEFAULT_PATH) -> HighScoreStore:
	var store := HighScoreStore.new()
	if not FileAccess.file_exists(path):
		return store
	var file := ConfigFile.new()
	var status: Error = file.load(path)
	if status != OK:
		store.error = "high-score file %s could not be read (%s); using defaults" % [path, error_string(status)]
		return store
	var problem: String = store._read(file)
	if not problem.is_empty():
		var empty := HighScoreStore.new()
		empty.error = "high-score file %s %s; using defaults" % [path, problem]
		return empty
	store.present = true
	return store


## Writes these values to [param path]; returns "" or why saving failed.
func save(path: String = DEFAULT_PATH) -> String:
	var problem: String = _validate()
	if not problem.is_empty():
		return "high scores not saved: " + problem
	var directory: String = path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return "high-score folder %s could not be created (%s)" % [directory, error_string(made)]
	var file := ConfigFile.new()
	file.set_value(_META, "format_version", FORMAT_VERSION)
	file.set_value(_MAIN, "initials", main_initials)
	file.set_value(_MAIN, "scores", main_scores)
	file.set_value(_MAIN, "times", main_times)
	file.set_value(_LEVELS, "initials", level_initials)
	file.set_value(_LEVELS, "scores", level_scores)
	file.set_value(_LEVELS, "times", level_times)
	var temporary: String = path + _TEMP_SUFFIX
	var written: Error = file.save(temporary)
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return "high-score file %s could not be written (%s)" % [temporary, error_string(written)]
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return "high-score file %s could not replace %s (%s)" % [temporary, path, error_string(renamed)]
	return ""


func _read(file: ConfigFile) -> String:
	if not file.has_section_key(_META, "format_version"):
		return "has no format version"
	var version: Variant = file.get_value(_META, "format_version")
	if typeof(version) != TYPE_INT:
		return "has a non-integer format version"
	if version != FORMAT_VERSION:
		return "has format version %d, expected %d" % [version, FORMAT_VERSION]
	var values: Array[Variant] = []
	for key: Array in [[_MAIN, "initials", TYPE_PACKED_STRING_ARRAY], [_MAIN, "scores", TYPE_PACKED_INT32_ARRAY],
			[_MAIN, "times", TYPE_PACKED_INT32_ARRAY], [_LEVELS, "initials", TYPE_PACKED_STRING_ARRAY],
			[_LEVELS, "scores", TYPE_PACKED_INT32_ARRAY], [_LEVELS, "times", TYPE_PACKED_INT32_ARRAY]]:
		var section: String = key[0]
		var name: String = key[1]
		var expected: int = key[2]
		if not file.has_section_key(section, name):
			return "has no %s %s" % [section, name]
		var value: Variant = file.get_value(section, name)
		if typeof(value) != expected:
			return "has malformed %s %s" % [section, name]
		values.append(value)
	main_initials = values[0]
	main_scores = values[1]
	main_times = values[2]
	level_initials = values[3]
	level_scores = values[4]
	level_times = values[5]
	var problem: String = _validate()
	return "" if problem.is_empty() else "has " + problem


func _validate() -> String:
	var problem: String = _validate_rows("main", main_initials, main_scores, main_times, HighScoreTable.MAIN_COUNT)
	if problem.is_empty():
		problem = _validate_rows("levels", level_initials, level_scores, level_times,
				HighScoreTable.LEVEL_COUNT * HighScoreTable.LEVEL_RANKS)
	return problem


static func _validate_rows(label: String, initials: PackedStringArray, scores: PackedInt32Array,
		times: PackedInt32Array, rows: int) -> String:
	if initials.size() != rows:
		return "%d %s initials, expected %d" % [initials.size(), label, rows]
	if scores.size() != rows:
		return "%d %s scores, expected %d" % [scores.size(), label, rows]
	if times.size() != rows * HighScoreTable.TIMES_PER_ROW:
		return "%d %s times, expected %d" % [times.size(), label, rows * HighScoreTable.TIMES_PER_ROW]
	for row: int in rows:
		if initials[row].length() != HighScoreTable.INITIALS_LENGTH:
			return "%s initials %d of length %d, expected %d" % [label, row, initials[row].length(),
					HighScoreTable.INITIALS_LENGTH]
		if scores[row] < 0:
			return "negative %s score %d at row %d" % [label, scores[row], row]
	for index: int in times.size():
		if times[index] < 0 or times[index] > MAX_TIME:
			return "%s time %d at %d outside 0..%d" % [label, times[index], index, MAX_TIME]
	return ""
