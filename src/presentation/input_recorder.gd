class_name InputRecorder
extends RefCounted
## Records the held keyboard mask sampled for each committed tick in the playthrough fixture format.

const FLAG: String = "--record-inputs"
const DEFAULT_FOLDER: String = "user://playthroughs"

var level_code: String = ""
var output_path: String = ""
## Absolute path of the last written fixture; empty until a completion is saved.
var saved_path: String = ""
var _held_by_tick: Dictionary[int, int] = {}

## Creates a recorder when the command line requests one; an explicit value selects the output file.
static func from_arguments(arguments: PackedStringArray) -> InputRecorder:
	if not ViewerArguments.has_flag(arguments, FLAG) and ViewerArguments.value(arguments, FLAG + "=").is_empty():
		return null
	var result := InputRecorder.new()
	result.output_path = ViewerArguments.value(arguments, FLAG + "=")
	return result

## Starts a fresh recording for one level; earlier samples are discarded.
func reset(code: String) -> void:
	level_code = code
	saved_path = ""
	_held_by_tick.clear()

## Keeps the last held mask sampled for a tick; released ticks are omitted, as the fixture format expects.
func record(command: TickCommand) -> void:
	if command.held_mask == 0:
		_held_by_tick.erase(command.tick_index)
	else:
		_held_by_tick[command.tick_index] = command.held_mask & 255

## Sparse `[tick, mask]` pairs in tick order.
func inputs() -> Array:
	var ticks: Array = _held_by_tick.keys()
	ticks.sort()
	var result: Array = []
	for tick: int in ticks:
		result.append([tick, _held_by_tick[tick]])
	return result

## The fixture document for a run that completed at `final_tick`.
func document(final_tick: int) -> Dictionary:
	return {
		"description": "Normal-start keyboard completion of %s recorded from owner play; input stimulus, not an expected-state golden." % level_code,
		"goal": "complete",
		"level": level_code,
		"ticks": final_tick + 1,
		"inputs": inputs(),
	}

## Writes the fixture and returns an error, or an empty string after recording the absolute path.
func save(final_tick: int) -> String:
	var path: String = output_path
	if path.is_empty():
		path = DEFAULT_FOLDER.path_join(level_code.to_lower() + "_keyboard_playthrough.json")
	var folder: String = path.get_base_dir()
	if not folder.is_empty():
		var created: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder) if folder.begins_with("user://") else folder)
		if created != OK and created != ERR_ALREADY_EXISTS:
			return "Cannot create recording folder " + folder
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot write recording " + path
	file.store_string(JSON.stringify(document(final_tick), "  ") + "\n")
	file.close()
	saved_path = ProjectSettings.globalize_path(path)
	return ""
