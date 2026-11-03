class_name ImportRun
extends RefCounted
## Runs the importer's steps for one phase against an [ImportContext].
##
## Steps run in the fixed order of [constant STEP_SCRIPTS]. A step that does
## not take part in the phase, or is left out of the [code]only[/code] list,
## is skipped. Each step's time and the phase totals are printed as
## [code]import:[/code] lines. Before the steps run, the context restores what
## earlier phases of the same run recorded in its scratch folder; afterwards it
## keeps this phase's record there. A run whose context is cancelled stops
## before its next step with a problem.

## The steps in the order they run.
const STEP_SCRIPTS: Array[String] = [
	"res://archive/import/steps/names_step.gd",
	"res://archive/import/steps/tables_step.gd",
	"res://archive/import/steps/textures_step.gd",
	"res://archive/import/steps/sfx_step.gd",
	"res://archive/import/steps/music_step.gd",
	"res://archive/import/steps/demos_step.gd",
	"res://archive/import/steps/maps_step.gd",
	"res://archive/import/steps/models_step.gd",
	"res://archive/import/steps/options_models_step.gd",
	"res://archive/import/steps/catalog_step.gd",
]

## Called as [code]on_step.call(step_name, phase)[/code] before each step runs;
## unset when nobody follows the run.
var on_step: Callable = Callable()


## Runs every step of [param phase] ([constant ImportStep.PHASE_RAW] or
## [constant ImportStep.PHASE_RESOURCES]) whose name is in [param only], or
## every step when [param only] is empty, and returns the number of problems
## the context holds afterwards. A step that does not compile is reported and
## ends the phase.
func run(context: ImportContext, phase: String, only: PackedStringArray = PackedStringArray()) -> int:
	var started: int = Time.get_ticks_msec()
	context.restore_record()
	if only.is_empty() and not context.complete_phases.has(phase):
		context.complete_phases.append(phase)
	for script_path: String in STEP_SCRIPTS:
		var expected_name: String = script_path.get_file().trim_suffix("_step.gd")
		if not only.is_empty() and not only.has(expected_name):
			continue
		if not ResourceLoader.exists(script_path):
			print("import: no step at %s" % script_path)
			continue
		var script: GDScript = load(script_path)
		if script == null or not script.can_instantiate():
			context.report("step %s does not compile" % script_path)
			break
		var step: ImportStep = script.new()
		if step.step_name() != expected_name:
			context.report("step %s names itself %s" % [script_path, step.step_name()])
		if not step.phases().has(phase):
			continue
		if context.is_cancelled():
			context.report("the import was cancelled")
			break
		if on_step.is_valid():
			on_step.call(step.step_name(), phase)
		var step_started: int = Time.get_ticks_msec()
		step.run(context, phase)
		if context.is_cancelled():
			context.report("the import was cancelled")
			break
		print("import: %s (%s) %d ms" % [step.step_name(), phase, Time.get_ticks_msec() - step_started])
	context.keep_record()
	print("import: phase %s wrote %d files, %d unchanged, %d problems, %d ms" % [
		phase, context.written.size(), context.unchanged, context.problems.size(),
		Time.get_ticks_msec() - started])
	return context.problems.size()
