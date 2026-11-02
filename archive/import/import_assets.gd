extends SceneTree
## Imports the owner's retail files, or a FrogLord save of them, into an
## asset root once.
##
##   godot --headless --path . -s res://archive/import/import_assets.gd -- \
##       --data-dir=<folder> [--disc=<FROGGER.mds>] [--scratch=<folder>] \
##       --phase=raw|resources [--only=step,step] [--force-music] \
##       [--assets-root=<folder>] [--fallback-root=<folder>]
##
## [code]archive/import/import_assets.sh[/code] runs the phases in order with
## Godot's import step between them. [ImportRun] runs the steps in their fixed
## order; each reports problems and the process exits 1 when any were
## reported. [code]--assets-root[/code] (default [code]res://assets[/code]) is
## where the run writes; [code]--fallback-root[/code] names a complete asset
## root the index falls back to for everything the run did not write, which
## makes the run an overlay. The data folder must hold a pc-retail-v3.0e build:
## the retail files, or FrogLord's [code]modded_[/code] pair whose trailer
## names that build.


func _init() -> void:
	var options: Dictionary[String, String] = _parse(OS.get_cmdline_user_args())
	var phase: String = _option(options, "phase")
	if phase != ImportStep.PHASE_RAW and phase != ImportStep.PHASE_RESOURCES:
		printerr("import: --phase must be raw or resources")
		quit(2)
		return
	var context := ImportContext.new()
	context.scratch = _option(options, "scratch")
	context.disc = _option(options, "disc")
	if context.disc.is_empty():
		context.disc = OS.get_environment("FROGGER_DISC")
	context.force_music = options.has("force-music")
	var assets_root: String = _option(options, "assets-root")
	context.assets_root = assets_root if not assets_root.is_empty() else "res://assets"
	context.fallback_root = _option(options, "fallback-root")
	var data_dir: String = _option(options, "data-dir")
	var located: GameDataLocator.Located = GameDataLocator.new().locate(data_dir)
	if located == null or located.source == null or located.version == null:
		printerr("import: no retail data found; pass --data-dir or set FROGGER_DATA_DIR")
		quit(2)
		return
	context.data = GameData.open(located.source, located.version)
	if not context.data.is_valid():
		printerr("import: %s" % context.data.error)
		quit(2)
		return
	if located.version.internal_name != "pc-retail-v3.0e":
		printerr("import: build %s is not pc-retail-v3.0e" % located.version.internal_name)
		quit(2)
		return
	var only: PackedStringArray = _option(options, "only").split(",", false)
	var problems: int = ImportRun.new().run(context, phase, only)
	if phase == ImportStep.PHASE_RESOURCES:
		_report_support(context)
	context.data.close()
	quit(1 if problems > 0 else 0)


## Prints the [LevelSupportReport] of the source and saves it as
## [code]support_report.tsv[/code] in the scratch folder's [code]logs[/code]
## when the run has one. Unmapped rows are information, not problems.
func _report_support(context: ImportContext) -> void:
	var report: LevelSupportReport = LevelSupportReport.from_catalog(context.data)
	print("import: support %s" % report.summary())
	for row: LevelSupportReport.Row in report.unmapped():
		print("import: unmapped %s" % row.to_tsv())
	for problem: String in report.problems:
		print("import: support problem %s" % problem)
	if context.scratch.is_empty():
		return
	var path: String = context.scratch.path_join("logs").path_join("support_report.tsv")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		context.note("cannot write %s" % path)
		return
	file.store_string("\n".join(report.to_tsv_lines()) + "\n")
	file.close()
	print("import: support report %s" % path)


func _option(options: Dictionary[String, String], key: String) -> String:
	return options[key] if options.has(key) else ""


func _parse(arguments: PackedStringArray) -> Dictionary[String, String]:
	var options: Dictionary[String, String] = {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			continue
		var body: String = argument.substr(2)
		var split: int = body.find("=")
		if split < 0:
			options[body] = ""
		else:
			options[body.substr(0, split)] = body.substr(split + 1)
	return options
