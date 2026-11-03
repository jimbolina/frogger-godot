class_name ImportCommand
extends RefCounted
## The command line of a setup import process: the game run again, headless,
## on the setup scene in import mode.
##
## The setup screen imports in a child process of the same executable because
## saving model meshes stalls on a worker thread; a headless process imports
## on its main thread instead. [method arguments] builds the child's command
## line and [method parse] reads it back in the child. The child writes its
## progress as [ImportProgress] lines to [member progress_path] and refuses to
## run when its [code]user://[/code] folder is not [member user_dir], so the
## import lands where the parent will read it.

## The user argument that puts the setup scene in import mode.
const IMPORT_FLAG: String = "--setup-import"
## The value arguments the child reads.
const DATA_DIR_ARGUMENT: String = "--data-dir="
const DISC_ARGUMENT: String = "--disc="
const TARGET_ARGUMENT: String = "--target="
const PROGRESS_ARGUMENT: String = "--progress="
const USER_DIR_ARGUMENT: String = "--user-dir="

## The folder holding the player's game files.
var data_dir: String = ""
## The disc image, or "" for no music.
var disc_path: String = ""
## The root to import into, such as [code]user://assets/<fingerprint>[/code].
var target_root: String = ""
## The absolute path of the progress file the child writes.
var progress_path: String = ""
## The absolute path of the parent's [code]user://[/code] folder.
var user_dir: String = ""
## Why [method parse] could not read a command, or "".
var error: String = ""


## Whether the user arguments [param given] ask for import mode.
static func is_requested(given: PackedStringArray) -> bool:
	return given.has(IMPORT_FLAG)


## The child's full command line (engine arguments, then [code]--[/code] and the
## user arguments) for running [param scene] headless. A run from source
## ([param from_source]) names its [param project_dir] with [code]--path[/code];
## an exported game needs none. The engine writes its log to [param log_path].
func arguments(scene: String, from_source: bool, project_dir: String, log_path: String) -> PackedStringArray:
	var command := PackedStringArray(["--headless"])
	if from_source:
		command.append_array(["--path", project_dir])
	if not log_path.is_empty():
		command.append_array(["--log-file", log_path])
	command.append(scene)
	command.append("--")
	command.append_array(user_arguments())
	return command


## The user arguments alone, as [method parse] reads them.
func user_arguments() -> PackedStringArray:
	var values := PackedStringArray([IMPORT_FLAG, DATA_DIR_ARGUMENT + data_dir])
	if not disc_path.is_empty():
		values.append(DISC_ARGUMENT + disc_path)
	values.append_array([TARGET_ARGUMENT + target_root, PROGRESS_ARGUMENT + progress_path,
		USER_DIR_ARGUMENT + user_dir])
	return values


## Reads a command from the user arguments [param given]; check [member error].
static func parse(given: PackedStringArray) -> ImportCommand:
	var command := ImportCommand.new()
	command.data_dir = _value(given, DATA_DIR_ARGUMENT)
	command.disc_path = _value(given, DISC_ARGUMENT)
	command.target_root = _value(given, TARGET_ARGUMENT)
	command.progress_path = _value(given, PROGRESS_ARGUMENT)
	command.user_dir = _value(given, USER_DIR_ARGUMENT)
	var missing := PackedStringArray()
	if not is_requested(given):
		missing.append(IMPORT_FLAG)
	for pair: Array in [[DATA_DIR_ARGUMENT, command.data_dir], [TARGET_ARGUMENT, command.target_root],
			[PROGRESS_ARGUMENT, command.progress_path], [USER_DIR_ARGUMENT, command.user_dir]]:
		var value: String = pair[1]
		if value.is_empty():
			var name: String = pair[0]
			missing.append(name.trim_suffix("="))
	if not missing.is_empty():
		command.error = "the import command lacks %s" % ", ".join(missing)
	return command


## Whether [param folder] (the child's own [code]user://[/code], made absolute)
## is the [member user_dir] the parent named.
func same_user_dir(folder: String) -> bool:
	return _folder(folder) == _folder(user_dir)


static func _folder(path: String) -> String:
	var simplified: String = path.replace("\\", "/").simplify_path()
	while simplified.length() > 1 and simplified.ends_with("/"):
		simplified = simplified.substr(0, simplified.length() - 1)
	if simplified.length() >= 2 and simplified.substr(1, 1) == ":":
		return simplified.to_lower()
	return simplified


static func _value(given: PackedStringArray, prefix: String) -> String:
	for argument: String in given:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""
