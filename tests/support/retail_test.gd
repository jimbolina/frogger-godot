class_name RetailTest
extends GutTest
## Base class for tests that need the player's retail Frogger files.
##
## Such tests read the folder named by the [code]FROGGER_DATA_DIR[/code]
## environment variable. Only an unset variable permits a reviewed named skip.
## A supplied invalid folder is an input failure, checked before GUT runs.


## Skips this script only when no retail folder was supplied. (Left without
## a return type because GUT declares it that way and overrides must match.)
@warning_ignore("untyped_declaration")
func should_skip_script():
	var reason: String = retail_skip_reason()
	return reason if not reason.is_empty() else false


## The allowed asset-free skip reason, or "" when a folder was supplied.
static func retail_skip_reason() -> String:
	if not OS.has_environment(GameDataLocator.ENV_VAR):
		return "SKIP: %s is not set" % GameDataLocator.ENV_VAR
	return ""


## The retail install named by [code]FROGGER_DATA_DIR[/code].
func retail_source() -> RetailDirSource:
	return RetailDirSource.new(OS.get_environment(GameDataLocator.ENV_VAR))
