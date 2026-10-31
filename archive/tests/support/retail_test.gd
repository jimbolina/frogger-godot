class_name RetailTest
extends GutTest
## Base class for archive tests that need the player's retail Frogger files.
##
## Such tests read the folder named by the [code]FROGGER_DATA_DIR[/code]
## environment variable. The archive suite runs only when that variable is set,
## after the wrapper has checked the folder, so these tests never skip: without
## the files they fail.


## Describes a missing folder, or "" when one was supplied; setup code uses it
## to avoid opening an absent install.
static func retail_skip_reason() -> String:
	if not OS.has_environment(GameDataLocator.ENV_VAR):
		return "%s is not set" % GameDataLocator.ENV_VAR
	return ""


## The retail install named by [code]FROGGER_DATA_DIR[/code].
func retail_source() -> RetailDirSource:
	return RetailDirSource.new(OS.get_environment(GameDataLocator.ENV_VAR))
