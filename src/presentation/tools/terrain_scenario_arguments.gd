class_name TerrainScenarioArguments
extends RefCounted
## Translates process arguments into explicit inspection options.

## Applies CLI selections through the shared options validation boundary.
static func apply(scenario: TerrainScenario, arguments: PackedStringArray) -> String:
	return scenario.options.configure(scenario,
		ViewerArguments.value(arguments, "--entity-reactions="),
		ViewerArguments.value(arguments, "--entity-lifecycle="),
		ViewerArguments.value(arguments, "--exploration="),
		ViewerArguments.value(arguments, "--level="),
		ViewerArguments.uses_assets(arguments),
		ViewerArguments.value(arguments, "--seed="),
		ViewerArguments.value(arguments, "--tick-limit="))
