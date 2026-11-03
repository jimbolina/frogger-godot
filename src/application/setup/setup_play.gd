class_name SetupPlay
extends SetupPage
## The last page: whether the setup screen opens on every start, and the way
## into the game.

## Whether the setup screen opens on every start.
var show_setup_on_start: bool = false


func title() -> String:
	return "Play"


## Puts the choice into [param launcher].
func write_launcher(launcher: LauncherSettings) -> void:
	launcher.show_setup_on_start = show_setup_on_start
