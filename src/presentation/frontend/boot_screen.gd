class_name BootScreen
extends Control
## First screen: finds the player's Frogger files and says what was found.
##
## The data folder comes from, in order: [code]--data-dir=<folder>[/code] on the
## command line (after [code]--[/code]), the [code]FROGGER_DATA_DIR[/code]
## environment variable, or the folder remembered from a previous run. A
## folder found on the command line or in the environment is remembered.

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 16
	_label.offset_top = 16
	_label.offset_right = -16
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	var report: String = build_report(command_line_data_dir())
	_label.text = report
	print(report)


## The folder given as [code]--data-dir=<folder>[/code] after [code]--[/code], or "".
static func command_line_data_dir() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data-dir="):
			return arg.substr("--data-dir=".length())
	return ""


## Locates the game files and returns a human-readable report of the result.
static func build_report(explicit_dir: String) -> String:
	var locator := GameDataLocator.new()
	var found: GameDataLocator.Located = locator.locate(explicit_dir)
	var lines := PackedStringArray(["Frogger", ""])
	if not found.is_ok():
		lines.append("No usable Frogger files were found (%s)." % found.error)
		lines.append("")
		lines.append("This game needs your own copy of Frogger (1997, PC). Point it at the folder")
		lines.append("holding FROGGER.EXE and FROGPSX.MWD (or FrogLord's modded_ files) by either:")
		lines.append("  - starting it with:  -- --data-dir=<folder>")
		lines.append("  - setting the environment variable %s=<folder>" % GameDataLocator.ENV_VAR)
		lines.append("")
		lines.append("Searched:")
		for attempt: String in found.attempts:
			lines.append("  " + attempt)
		return "\n".join(lines)
	if found.origin != "saved setting":
		locator.remember_directory(found.source.directory)
	lines.append("Game data: %s" % found.source.describe())
	lines.append("Found via: %s" % found.origin)
	lines.append("Version: %s (%s), recognised by %s" % [found.version.display_name,
		found.version.internal_name, found.detection_method])
	lines.append("Executable CRC-32: %d" % found.exe_crc32)
	return "\n".join(lines)
