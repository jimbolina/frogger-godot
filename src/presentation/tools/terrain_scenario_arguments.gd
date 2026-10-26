class_name TerrainScenarioArguments
extends RefCounted
## Translates process arguments and environment into explicit inspection options.

## Applies CLI selections through the shared options validation boundary.
static func apply(scenario: TerrainScenario, arguments: PackedStringArray) -> String:
	return scenario.options.configure(scenario,
		ViewerArguments.value(arguments, "--entity-reactions="),
		ViewerArguments.value(arguments, "--entity-lifecycle="),
		ViewerArguments.value(arguments, "--exploration="),
		ViewerArguments.value(arguments, "--level="),
		ViewerArguments.has_prefix(arguments, "--data-dir=") or not OS.get_environment("FROGGER_DATA_DIR").is_empty(),
		ViewerArguments.value(arguments, "--seed="),
		ViewerArguments.value(arguments, "--tick-limit="))
