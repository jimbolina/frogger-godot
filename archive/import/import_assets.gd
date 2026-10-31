extends SceneTree
## Imports the owner's retail files into [code]res://assets[/code] once.
##
##   godot --headless --path . -s res://archive/import/import_assets.gd -- \
##       --data-dir=<folder> [--disc=<FROGGER.mds>] [--scratch=<folder>] \
##       --phase=raw|resources [--only=step,step] [--force-music]
##
## [code]archive/import/import_assets.sh[/code] runs the phases in order with
## Godot's import step between them. Steps run in the fixed order below; each
## reports problems and the process exits 1 when any were reported.

const STEP_SCRIPTS: Array[String] = [
	"res://archive/import/steps/names_step.gd",
	"res://archive/import/steps/tables_step.gd",
	"res://archive/import/steps/textures_step.gd",
	"res://archive/import/steps/pages_step.gd",
	"res://archive/import/steps/sfx_step.gd",
	"res://archive/import/steps/music_step.gd",
	"res://archive/import/steps/demos_step.gd",
	"res://archive/import/steps/maps_step.gd",
	"res://archive/import/steps/models_step.gd",
	"res://archive/import/steps/options_models_step.gd",
	"res://archive/import/steps/catalog_step.gd",
]


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
	var started: int = Time.get_ticks_msec()
	for script_path: String in STEP_SCRIPTS:
		var expected_name: String = script_path.get_file().trim_suffix("_step.gd")
		if not only.is_empty() and not only.has(expected_name):
			continue
		if not ResourceLoader.exists(script_path):
			print("import: no step at %s" % script_path)
			continue
		var script: GDScript = load(script_path)
		if script == null or not script.can_instantiate():
			printerr("import: step %s does not compile" % script_path)
			quit(2)
			return
		var step: ImportStep = script.new()
		if step.step_name() != expected_name:
			context.report("step %s names itself %s" % [script_path, step.step_name()])
		if not step.phases().has(phase):
			continue
		var step_started: int = Time.get_ticks_msec()
		step.run(context, phase)
		print("import: %s (%s) %d ms" % [step.step_name(), phase, Time.get_ticks_msec() - step_started])
	context.data.close()
	print("import: phase %s wrote %d files, %d unchanged, %d problems, %d ms" % [
		phase, context.written.size(), context.unchanged, context.problems.size(),
		Time.get_ticks_msec() - started])
	quit(1 if not context.problems.is_empty() else 0)


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
