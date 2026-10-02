class_name EntityScenario
extends RefCounted
## Detached entity run stimulus for inspection and schedule comparisons.

var definitions: Array[EntityDefinition] = []
var error: String = ""
var name: String = ""
var tick_limit: int = 16
var level_code: String = ""
var diagnostics: PackedStringArray = PackedStringArray()

## Builds a source-free group with shared path cursors and a static anchor.
static func builtin(selected: String) -> EntityScenario:
	var scenario := EntityScenario.new()
	scenario.name = selected
	if selected != "shared-path":
		scenario.error = "Unknown entity scenario '%s'; choose shared-path" % selected
		return scenario
	var path := PathDefinition.new()
	path.source_id = "synthetic:shared-path"
	path.path_index = 0
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 200
	segment.start = Vector3i(-100, 0, 0)
	segment.end = Vector3i(100, 0, 0)
	path.segments.append(segment)
	var anchor := EntityDefinition.new()
	anchor.source_id = path.source_id
	anchor.entity_index = 0
	anchor.unique_id = 10
	anchor.form_name = "SYNTHETIC_STATIC"
	anchor.entity_name = "STATIC"
	anchor.matrix12[9] = -150
	scenario.definitions.append(anchor)
	for index: int in 3:
		var moving := EntityDefinition.new()
		moving.source_id = path.source_id
		moving.entity_index = index + 1
		moving.unique_id = 11 + index
		moving.form_name = "SYNTHETIC_MOVING"
		moving.entity_name = "MOVING"
		moving.path_definition = path.copy()
		moving.path_start = PathStart.new()
		moving.path_start.speed = 10 + index * 2
		moving.path_start.flags = PathStart.ACTIVE | PathStart.REPEAT
		if index == 1:
			moving.flags = EntityDefinition.NO_MOVEMENT
		if index == 2:
			moving.flags = EntityDefinition.ALIGN_TO_WORLD
			moving.path_start.flags |= PathStart.BACKWARDS
			moving.path_start.distance = 160
		scenario.definitions.append(moving)
	scenario.error = EntityRun.create(scenario.definitions).error
	return scenario

## Resolves the selected high-detail player map and copies supported entities.
func attach_data(data: GameData, selected_level_code: String = "ORG1") -> String:
	if data == null or not data.is_valid():
		return "Entity inspection requires valid player data"
	var number: int = FroggerIds.level_from_code(selected_level_code)
	if number < 0 or GameData.is_multiplayer_level(number):
		return "Entity inspection requires a known single-player level code"
	var book: MapBookEntry = data.map_book_entry(number)
	if book == null:
		return "Entity inspection cannot find the level's map entry"
	var resource_id: int = book.map_id(false)
	var problems := PackedStringArray()
	var map: MapFile = data.read_map(resource_id, problems)
	if map == null:
		return "Entity inspection cannot read map: " + "; ".join(problems)
	var selected_code: String = selected_level_code.to_upper()
	var setup: EntitySetup = EntitySetup.from_map(map, data.tables.theme_book(), data.version.internal_name + ":" + selected_code, resource_id, data.version.internal_name)
	if not setup.error.is_empty():
		return setup.error
	var copies: Array[EntityDefinition] = []
	for item: EntityDefinition in setup.definitions:
		copies.append(item.copy())
	var run: EntityRun = EntityRun.create(copies)
	if not run.error.is_empty():
		return run.error
	definitions = copies
	diagnostics.clear()
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		diagnostics.append(diagnostic.to_text())
	level_code = selected_code
	name = selected_code.to_lower() + "-entities"
	return ""
