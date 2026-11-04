extends SceneTree
## Loads every project script so parse errors and warnings-as-errors surface.
##
##   godot --headless --path . -s res://tools/check/check_scripts.gd
##
## Tests only compile the scripts they reach; this compiles all of them
## (src/, scenes/, tests/, tools/, archive/). Engine errors are printed by Godot itself;
## the last line reports how many scripts failed and the exit code is 1 if any did.

const ROOTS: Array[String] = ["res://src", "res://scenes", "res://tests", "res://tools", "res://archive"]


func _init() -> void:
	var paths := PackedStringArray()
	for root: String in ROOTS:
		_collect(root, paths)
	var failed: int = 0
	for path: String in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("CHECK FAILED: %s" % path)
	print("check_scripts: %d scripts, %d failed" % [paths.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(dir: String, into: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			into.append(dir.path_join(file))
