class_name ImportStep
extends RefCounted
## One stage of the importer, run in a fixed order by [code]import_assets.gd[/code].
##
## A step declares the phases it takes part in: [code]raw[/code] writes files
## that Godot must import first (PNG, WAV), [code]resources[/code] writes
## resources that reference imported files. Steps report problems through
## [method ImportContext.report] and never throw.

const PHASE_RAW: String = "raw"
const PHASE_RESOURCES: String = "resources"


## The step's name for logs and the [code]--only[/code] selection.
func step_name() -> String:
	return "step"


## The phases in which [method run] does work.
func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


## Performs the step's work for [param phase] against [param context].
@warning_ignore("unused_parameter")
func run(context: ImportContext, phase: String) -> void:
	pass
