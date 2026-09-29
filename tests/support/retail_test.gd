class_name RetailTest
extends GutTest
## Base class for tests that need the player's retail Frogger files.
##
## Such tests read the folder named by the [code]FROGGER_DATA_DIR[/code]
## environment variable. When it is unset, or the folder lacks
## [code]FROGGER.EXE[/code] / [code]FROGPSX.MWD[/code], the whole test script is
## skipped (and reported as SKIPPED by name) instead of failing, so the
## asset-free tests still run anywhere.


## Skips this script when the retail files are not available. (Left without
## a return type because GUT declares it that way and overrides must match.)
@warning_ignore("untyped_declaration")
func should_skip_script():
	var reason: String = retail_skip_reason()
	return reason if not reason.is_empty() else false


## Why the retail files cannot be used, or "" when they can.
static func retail_skip_reason() -> String:
	var dir: String = OS.get_environment(GameDataLocator.ENV_VAR)
	if dir.is_empty():
		return "SKIP: %s is not set" % GameDataLocator.ENV_VAR
	if not RetailDirSource.looks_like(dir):
		return "SKIP: %s (%s) has no %s + %s" % [GameDataLocator.ENV_VAR, dir,
			RetailDirSource.EXE_NAME, RetailDirSource.MWD_NAME]
	return ""


## The retail install named by [code]FROGGER_DATA_DIR[/code].
func retail_source() -> RetailDirSource:
	return RetailDirSource.new(OS.get_environment(GameDataLocator.ENV_VAR))
