extends SceneTree
## Checks protected layers and archive isolation without loading the scanned scripts.
## Run with godot --headless --path . -s res://tools/check/check_architecture.gd.

const Scanner = preload("res://tools/check/architecture_scanner.gd")
const ROOTS: Array[String] = [
	"res://src", "res://scenes", "res://assets", "res://tests", "res://tools", "res://archive",
]
const RESOURCE_ROOTS: Array[String] = ["res://scenes", "res://assets"]


func _init() -> void:
	var sources: Dictionary[String, String] = {}
	var scripts: int = 0
	for root: String in ROOTS:
		scripts += _collect(root, RESOURCE_ROOTS.has(root), sources)
	var scanner := Scanner.new()
	var violations: Array[Scanner.Violation] = scanner.check(sources)
	var failed: Dictionary[String, bool] = {}
	for violation: Scanner.Violation in violations:
		print("ARCHITECTURE FAILED: %s" % violation.format())
		failed[violation.origin] = true
	print("architecture_check: %d scripts, %d failed" % [scripts, failed.size()])
	quit(1 if not failed.is_empty() else 0)


func _collect(directory: String, resources: bool, into: Dictionary[String, String]) -> int:
	if not DirAccess.dir_exists_absolute(directory):
		return 0
	var scripts: int = 0
	for child: String in DirAccess.get_directories_at(directory):
		scripts += _collect(directory.path_join(child), resources, into)
	for file: String in DirAccess.get_files_at(directory):
		var extension: String = file.get_extension()
		var path: String = directory.path_join(file)
		if extension == "gd":
			into[path] = FileAccess.get_file_as_string(path)
			scripts += 1
		elif resources and Scanner.RESOURCE_FILES.has(extension):
			into[path] = FileAccess.get_file_as_string(path)
	return scripts
