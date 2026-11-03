extends SceneTree
## Prints which forms, entities, scripts, callbacks and remaps of a build the port can play.
##
##   godot --headless --path . -s res://tools/asset_report.gd -- [--assets-root=<folder>]
##       [--index-root=<folder>] [--levels=ORG1,CAV3] [--strict] [--output=<file>]
##
## Without --assets-root the build is the one [AssetLocation] resolves. Prints the
## report as tab-separated lines, then its summary, and writes the
## lines to --output when given. Exits 1 with --strict when a selected level
## uses an unmapped item or could not be read (unplaced forms do not count),
## 2 when the catalog cannot open or the output cannot be written.


func _initialize() -> void:
	_report.call_deferred()


func _report() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index_root: String = ViewerArguments.value(args, "--index-root=")
	var output: String = ViewerArguments.value(args, "--output=")
	var levels := PackedStringArray()
	for code: String in ViewerArguments.value(args, "--levels=").split(",", false):
		levels.append(code.strip_edges().to_upper())
	var data: AssetCatalog = AssetLocation.resolve(args, LauncherStore.load_from()).open("", index_root)
	if not data.is_valid():
		printerr("asset_report: %s" % data.error)
		quit(2)
		return
	var report: LevelSupportReport = LevelSupportReport.from_catalog(data, levels)
	data.close()
	var lines: PackedStringArray = report.to_tsv_lines()
	for line: String in lines:
		print(line)
	for problem: String in report.problems:
		printerr("asset_report: %s" % problem)
	print(report.summary())
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("asset_report: cannot write %s" % output)
			quit(2)
			return
		file.store_string("\n".join(lines) + "\n")
		file.close()
	var failed: bool = not report.unmapped().is_empty() or not report.problems.is_empty()
	quit(1 if ViewerArguments.has_flag(args, "--strict") and failed else 0)
