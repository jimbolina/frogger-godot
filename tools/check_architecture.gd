extends SceneTree
## Checks protected data/gameplay layers without loading the scanned scripts.
## Run with godot --headless --path . -s res://tools/check_architecture.gd.

const Scanner = preload("res://tools/support/architecture_scanner.gd")
const ROOTS: Array[String] = ["res://src", "res://scenes", "res://tests", "res://tools"]


func _init() -> void:
	var sources: Dictionary[String, String] = {}
	for root: String in ROOTS:
		_collect(root, sources)
	var scanner := Scanner.new()
	var violations: Array[Scanner.Violation] = scanner.check(sources)
	var failed: Dictionary[String, bool] = {}
	for violation: Scanner.Violation in violations:
		print("ARCHITECTURE FAILED: %s" % violation.format())
		failed[violation.origin] = true
	print("architecture_check: %d scripts, %d failed" % [sources.size(), failed.size()])
	quit(1 if not failed.is_empty() else 0)


func _collect(directory: String, into: Dictionary[String, String]) -> void:
	for child: String in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(child), into)
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() == "gd":
			var path: String = directory.path_join(file)
			into[path] = FileAccess.get_file_as_string(path)
