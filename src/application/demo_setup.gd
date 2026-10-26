class_name DemoSetup
extends RefCounted
## Resolves recorded resources through the supplied executable's detail-specific list.

var error: String = ""
var demo: SourceDemoFile
var resource_id: int = -1
var resource_name: String = ""

## Reads the first enabled row for a level, preserving saved executable mappings.
static func resolve(data: GameData, level: int, low_poly: bool = false) -> DemoSetup:
	var result := DemoSetup.new()
	if data == null or not data.is_valid():
		result.error = "Demo setup requires valid player data"
		return result
	var table: DemoTable = data.tables.demo_table()
	if not table.error.is_empty():
		result.error = "Demo table: " + table.error
		return result
	var row: DemoTable.Entry = table.entry_for_level(level)
	if row == null:
		result.error = "No enabled demo table entry for level %d" % level
		return result
	result.resource_id = row.demo_id(low_poly)
	var entry: MwiEntry = data.mwi.get_entry(result.resource_id)
	if entry == null:
		result.error = "Demo table level %d refers to missing resource %d" % [level, result.resource_id]
		return result
	result.resource_name = entry.display_name()
	var problems := PackedStringArray()
	var bytes: PackedByteArray = data.read_resource(result.resource_id, problems)
	if not problems.is_empty():
		result.error = "Demo resource %d: %s" % [result.resource_id, "; ".join(problems)]
		return result
	result.demo = SourceDemoFile.parse(bytes, result.resource_name)
	result.error = result.demo.error
	return result

## Overrides only source demo spawn and fast-start context before normal run validation.
static func start_for(value: SourceDemoFile) -> RunStart:
	var start := RunStart.new()
	start.spawn_cell = Vector2i(value.start_grid_x, value.start_grid_z)
	start.start_mode = RunStart.Mode.FAST_RESET
	start.camera_startup = true
	start.start_timer = 30
	return start
