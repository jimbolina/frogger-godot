class_name DemoSetup
extends RefCounted
## Resolves a level's recorded demo through the executable's detail-specific demo list.

## Lives for demo playback. Frozen C never reinitialises lives between attract demos
## (tempopt.c:1437-1440 calls GameStart only), so a lone demo has no faithful count;
## FROG_MAX_LIVES (10) is the most C can carry and no retail demo loses that many.
const DEMO_LIVES: int = 10

var error: String = ""
var demo: SourceDemoFile
var resource_id: int = -1
var resource_name: String = ""

## Reads the first enabled row for a level, preserving saved executable mappings.
static func resolve(data: AssetCatalog, level: int, low_poly: bool = false) -> DemoSetup:
	var result := DemoSetup.new()
	if data == null or not data.is_valid():
		result.error = "Demo setup requires valid player data"
		return result
	var table: DemoTable = data.tables.demo_table()
	if not table.error.is_empty():
		result.error = "Demo table: " + table.error
		return result
	var row: DemoTableEntry = table.entry_for_level(level)
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
	result.demo = data.read_demo(result.resource_id, problems)
	if result.demo == null:
		result.error = "Demo resource %d: %s" % [result.resource_id, "; ".join(problems)]
		return result
	result.error = result.demo.error
	return result

## Overrides only source demo spawn and fast-start context before normal run validation.
static func start_for(value: SourceDemoFile) -> RunStart:
	var start := RunStart.new()
	start.spawn_cell = Vector2i(value.start_grid_x, value.start_grid_z)
	start.start_mode = RunStart.Mode.FAST_RESET
	start.camera_startup = true
	start.start_timer = 30
	start.lives = DEMO_LIVES
	return start
