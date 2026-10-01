class_name BootScreen
extends Control
## First screen: finds the player's Frogger files and says what was found.
##
## The data folder comes from, in order: [code]--data-dir=<folder>[/code] on the
## command line (after [code]--[/code]), the [code]FROGGER_DATA_DIR[/code]
## environment variable, or the folder remembered from a previous run. A
## folder found on the command line or in the environment is remembered.
##
## A menu at the top opens the texture, model and map inspection tools.

## The texture viewer's scene.
const TEXTURE_VIEWER_SCENE: String = "res://scenes/tools/texture_viewer.tscn"
## The model viewer's scene.
const MODEL_VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"
## The map inspection tool.
const MAP_VIEWER_SCENE: String = "res://scenes/tools/map_viewer.tscn"

var _label: Label


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16
	layout.offset_top = 16
	layout.offset_right = -16
	layout.offset_bottom = -16
	add_child(layout)
	var menu := HBoxContainer.new()
	layout.add_child(menu)
	var viewer_button := Button.new()
	viewer_button.text = "Texture viewer"
	viewer_button.pressed.connect(open_texture_viewer)
	menu.add_child(viewer_button)
	var model_button := Button.new()
	model_button.text = "Model viewer"
	model_button.pressed.connect(open_model_viewer)
	menu.add_child(model_button)
	var map_button := Button.new()
	map_button.text = "Map viewer"
	map_button.pressed.connect(open_map_viewer)
	menu.add_child(map_button)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_label)
	var report: String = build_report(command_line_data_dir())
	_label.text = report
	print(report)
	viewer_button.grab_focus()


## Switches to the texture viewer.
func open_texture_viewer() -> void:
	get_tree().change_scene_to_file(TEXTURE_VIEWER_SCENE)


## Switches to the model viewer.
func open_model_viewer() -> void:
	get_tree().change_scene_to_file(MODEL_VIEWER_SCENE)


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
	lines.append("")
	lines.append_array(describe_archive(found.source, found.version))
	lines.append("")
	lines.append_array(describe_tables(found.source, found.version))
	return "\n".join(lines)


## A few lines counting the game tables read from the executable: a quick
## smoke check that the tables decode.
static func describe_tables(source: GameDataSource, version: GameVersionConfig) -> PackedStringArray:
	var lines := PackedStringArray()
	var data: GameData = GameData.open(source, version)
	if not data.is_valid():
		lines.append("Game tables: unreadable: %s" % data.error)
		return lines
	var tables: ExeTables = data.tables
	var used_levels: int = 0
	for e: MapBookEntry in tables.map_book().entries:
		if e.high_map_id > 0:
			used_levels += 1
	var form_counts := PackedStringArray()
	for t: ThemeBookEntry in tables.theme_book().entries:
		if not t.forms.is_empty():
			form_counts.append("%s %d" % [t.theme_name(), t.forms.size()])
	lines.append("Levels: %d rows, %d with a map" % [tables.map_book().size(), used_levels])
	lines.append("Themes: %d; forms %d (%s)" % [tables.theme_book().entries.size(), tables.theme_book().form_count(),
		", ".join(form_counts)])
	lines.append("Scripts: %d (%d commands); texture remaps: %d; texture ids: %d" % [tables.scripts().size(),
		tables.scripts().command_count(), tables.remaps().size(), tables.bmp_pointers().size()])
	lines.append("Music entries: %d; demos: %d; level select: %d arcade + %d race; bug kinds: %d" % [
		tables.music().size(), tables.demo_table().size(), tables.level_select().arcade.size(),
		tables.level_select().race.size(), tables.pickups().size()])
	var problems: PackedStringArray = tables.errors()
	if not problems.is_empty():
		lines.append("Table problems: %s" % "; ".join(problems))
	data.close()
	return lines


## A few lines summarising the archive index and checking the archive opens:
## a quick smoke check that the data can be read.
static func describe_archive(source: GameDataSource, version: GameVersionConfig) -> PackedStringArray:
	var lines := PackedStringArray()
	var index: MwiIndex = MwiIndex.from_exe(source.get_exe_bytes(), version)
	if not index.is_valid():
		lines.append("Archive index (MWI): unreadable: %s" % index.error)
		return lines
	lines.append("Archive index (MWI): %d entries, %d WADs, %d compressed" % [
		index.size(), index.wad_entries().size(), index.compressed_count()])
	var counts: Dictionary[int, int] = index.count_by_type()
	var type_ids: Array[int] = counts.keys()
	type_ids.sort()
	var parts := PackedStringArray()
	for type_id: int in type_ids:
		parts.append("type %d: %d" % [type_id, counts[type_id]])
	lines.append("Entries by type: " + ", ".join(parts))
	var problems := PackedStringArray()
	var archive: MwdArchive = MwdArchive.open(source.get_mwd_path(), problems)
	if archive == null:
		lines.append("Archive (MWD): unreadable: %s" % ", ".join(problems))
	else:
		lines.append("Archive (MWD): %d bytes, header OK" % archive.size())
		archive.close()
	return lines


## Switches to the map inspection tool.
func open_map_viewer() -> void:
	get_tree().change_scene_to_file(MAP_VIEWER_SCENE)
