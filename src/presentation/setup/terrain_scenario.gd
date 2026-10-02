class_name TerrainScenario
extends RefCounted
## Decodes debug stimuli outside gameplay. Built-ins mirror the C component fixtures.

var error: String = ""
var identifier: String = "normal"
var scenario_index: int = 0
var level: LevelDefinition
var initial: RunStart
var tick_limit: int = 16
var commands: Dictionary[int, TickCommand] = {}
var map_scene: MapSceneData = null
var frog_assets: TerrainFrogAssets = null
var diagnostics: PackedStringArray = PackedStringArray()
var level_code: String = ""
var entity_collision: EntityCollisionDefinition = null
var entity_reactions: bool = false
var collision_enabled_authored: bool = false
var authored_fixture: bool = false
var tick_limit_override: bool = false

## Creates authored flat terrain; these inputs contain no expected rule results.
static func builtin(name: String) -> TerrainScenario:
	var scenario := TerrainScenario.new()
	scenario.identifier = name
	scenario.scenario_index = ["normal", "blocked", "buffer"].find(name)
	if scenario.scenario_index < 0:
		scenario.error = "Unknown terrain scenario '%s'; choose normal, blocked or buffer" % name
		return scenario
	scenario.level = LevelDefinition.new()
	scenario.level.source_id = "synthetic:" + name
	scenario.level.map_index = 0
	scenario.level.spawn_cell = Vector2i(1, 1)
	scenario.level.grid = GridDefinition.new()
	scenario.level.camera = GameplayCameraDefinition.new()
	for action: int in FrogAnimationCatalog.ACTION_NAMES.size():
		scenario.level.frog_action_lengths.append(3 + action % 3)
	var grid: GridDefinition = scenario.level.grid
	grid.dimensions = Vector2i(4, 4)
	grid.base = Vector2i(-512, -512)
	for index: int in 16:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 0 if name == "blocked" and index == 9 else 3
		var x: int = -512 + (index % 4) * 256
		@warning_ignore("integer_division")
		var z: int = -512 + (index / 4) * 256
		square.vertices = [Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)]
		grid.squares.append(square)
	scenario.initial = RunStart.new()
	for tick: int in scenario.tick_limit:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
		command.held_mask = command.pressed_mask
		if name == "buffer" and tick >= 2 and tick <= 8:
			command.pressed_mask = TickCommand.EAST if tick == 2 else 0
			command.held_mask = TickCommand.EAST
		scenario.commands[tick] = command
	return scenario

## Resolves player resources before creating rules; scene records never enter gameplay.
func attach_data(data: GameData, selected_level_code: String = "", assets: TerrainFrogAssets = null) -> String:
	level_code = selected_level_code
	frog_assets = assets if assets != null else TerrainFrogAssets.from_data(data)
	if not frog_assets.error.is_empty():
		return frog_assets.error
	level.frog_action_lengths = frog_assets.action_lengths.duplicate()
	if level_code.is_empty():
		return ""
	var number: int = FroggerIds.level_from_code(level_code)
	if number < 0 or GameData.is_multiplayer_level(number):
		return "Terrain inspection requires a known single-player level code"
	map_scene = MapSceneData.load_level(data, number, false)
	if not map_scene.error.is_empty():
		return map_scene.error
	var setup: TerrainGridSetup = TerrainGridSetup.from_map(map_scene.map)
	if not setup.error.is_empty():
		return setup.error
	var theme: ThemeBookEntry = data.theme_book_entry(map_scene.map.general.theme)
	var book: MapBookEntry = data.map_book_entry(number)
	if theme == null or book == null:
		return "Terrain inspection requires map and theme table entries"
	level.grid = setup.definition
	level.spawn_cell = map_scene.map.general.start_grid
	level.spawn_direction = map_scene.map.general.start_rotation
	level.theme = map_scene.map.general.theme
	level.theme_name = &"JUN" if level.theme == 4 else &"VOL" if level.theme == 10 else &"SUB"
	level.theme_death_height = theme.death_height
	level.source_id = data.version.internal_name + ":" + level_code.to_upper()
	level.resource_id = book.map_id(false)
	level.map_index = number
	level.camera = GameplayCameraDefinition.new()
	level.camera.source_offset = map_scene.map.general.camera_source_offset
	level.camera.target_offset = map_scene.map.general.camera_target_offset
	level.collision_enabled = true
	# mapload.C establishes these limits before any P8 entity boundary markers run.
	level.collision_bounds = Rect2i(-32767, -32767, 65534, 65534)
	identifier = level_code.to_upper().to_lower() + "-terrain"
	if entity_reactions:
		var collision_setup: EntityCollisionSetup = EntityCollisionSetup.from_data(data, number)
		if not collision_setup.error.is_empty():
			return collision_setup.error
		entity_collision = collision_setup.definition
		level.entity_collision = entity_collision.copy()
		for diagnostic: EntitySetupDiagnostic in collision_setup.diagnostics:
			diagnostics.append(diagnostic.to_text())
		diagnostics.append("Entity POP inspection omits platforms, zones, scripts and authored boundary markers")
		apply_des2_inspection_defaults()
	else:
		diagnostics.append("Terrain inspection omits entities, forms, platforms, zones and authored boundary markers")
	return ""

## Selects the bounded DES2 hop only for the uncustomized built-in run.
func apply_des2_inspection_defaults() -> void:
	if not entity_reactions or level_code.to_upper() != "DES2" or authored_fixture:
		return
	initial.spawn_cell = Vector2i(17, 30)
	initial.spawn_direction = 1
	initial.controller_directions = PackedInt32Array()
	initial.camera_startup = false
	if not tick_limit_override:
		tick_limit = 80
	commands.clear()
	var east := TickCommand.new()
	east.tick_index = 0
	east.pressed_mask = TickCommand.EAST
	east.held_mask = TickCommand.EAST
	commands[0] = east

## Reads a scenario JSON object with builtin, tick_limit and optional command overrides.
static func from_file(path: String) -> TerrainScenario:
	var failed := TerrainScenario.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failed.error = "Cannot read terrain scenario '%s': %s" % [path, error_string(FileAccess.get_open_error())]
		return failed
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		failed.error = "Terrain scenario must be a JSON object: " + path
		return failed
	var object: Dictionary = json.data
	return from_object(object)

## Decodes every typed command field from an authored JSON-compatible object.
static func from_object(object: Dictionary) -> TerrainScenario:
	var failed := TerrainScenario.new()
	if not object.get("builtin", "normal") is String:
		failed.error = "Scenario builtin must be a string"
		return failed
	var builtin_name: String = object.get("builtin", "normal")
	var scenario: TerrainScenario = builtin(builtin_name)
	if not scenario.error.is_empty():
		return scenario
	scenario.authored_fixture = true
	var limit: Variant = object.get("tick_limit", 16)
	if not _integer(limit) or _to_int(limit) < 0 or _to_int(limit) > 100000:
		scenario.error = "Scenario tick_limit must be an integer in 0..100000"
		return scenario
	scenario.tick_limit = _to_int(limit)
	var decode_error: String = TerrainScenarioJson.apply(scenario, object)
	if not decode_error.is_empty():
		scenario.error = decode_error
		return scenario
	var authored_level: Dictionary = object.get("level", {})
	scenario.collision_enabled_authored = authored_level.has("collision_enabled")
	if authored_level.has("entity_collision"):
		if object.get("name") is String:
			var case_name: String = object.name
			scenario.identifier = case_name
		var errors := PackedStringArray()
		scenario.entity_collision = EntityCollisionScenarioJson.decode(authored_level.entity_collision, errors)
		if scenario.entity_collision == null:
			scenario.error = "; ".join(errors)
			return scenario
	if not object.has("commands"):
		return scenario
	if not object.commands is Array:
		scenario.error = "Scenario commands must be an array"
		return scenario
	scenario.commands.clear()
	for value: Variant in object.commands:
		if not value is Dictionary:
			scenario.error = "Each scenario command must be an object"
			return scenario
		var row: Dictionary = value
		if not _integer(row.get("tick")) or not _integer(row.get("pressed")) or not _integer(row.get("held")):
			scenario.error = "Command tick, pressed and held must be integers"
			return scenario
		var command := TickCommand.new()
		command.tick_index = _to_int(row.tick)
		command.pressed_mask = _to_int(row.pressed)
		command.held_mask = _to_int(row.held)
		var timer: Variant = row.get("start_timer_context", -1)
		if not _integer(timer) or _to_int(timer) < -1 or _to_int(timer) > 2147483647:
			scenario.error = "start_timer_context must be an integer in -1..2147483647"
			return scenario
		command.start_timer_context = _to_int(timer)
		var completion: Variant = row.get("start_sequence_complete", false)
		if not completion is bool:
			scenario.error = "start_sequence_complete must be boolean"
			return scenario
		command.start_sequence_complete = completion
		if command.pressed_mask < 0 or command.pressed_mask > 127 or command.held_mask < 0 or command.held_mask > 127:
			scenario.error = "Command masks must be integers in 0..127"
			return scenario
		if command.tick_index < 0 or command.tick_index >= scenario.tick_limit or scenario.commands.has(command.tick_index):
			scenario.error = "Command ticks must be unique and within the scenario"
			return scenario
		scenario.commands[command.tick_index] = command
	return scenario

## Returns a detached command; missing rows explicitly mean no buttons held or pressed.
func command_at(tick: int) -> TickCommand:
	var command := TickCommand.new()
	command.tick_index = tick
	if commands.has(tick):
		command.pressed_mask = commands[tick].pressed_mask
		command.held_mask = commands[tick].held_mask
		command.start_timer_context = commands[tick].start_timer_context
		command.start_sequence_complete = commands[tick].start_sequence_complete
	return command

## Applies explicit command-line seed and duration overrides in both driver surfaces.
func apply_arguments(arguments: PackedStringArray) -> String:
	var reaction: String = ViewerArguments.value(arguments, "--entity-reactions=")
	if not reaction.is_empty() and reaction != "pop":
		return "entity-reactions must be pop"
	entity_reactions = reaction == "pop"
	level.entity_collision = entity_collision.copy() if entity_reactions and entity_collision != null else null
	if entity_reactions and entity_collision != null:
		if collision_enabled_authored and not level.collision_enabled:
			return "Entity reaction scenario requires collision_enabled=true"
		level.collision_enabled = true
	for key: String in ["seed", "tick-limit"]:
		var text: String = ViewerArguments.value(arguments, "--" + key + "=")
		if text.is_empty():
			continue
		if not text.is_valid_int():
			return "%s must be an integer" % key
		var number: int = text.to_int()
		if key == "seed":
			if number < 0 or number > 0xffffffff:
				return "seed must be in 0..4294967295"
			initial.seed = number
		else:
			if number < 0 or number > 100000:
				return "tick-limit must be in 0..100000"
			tick_limit = number
			tick_limit_override = true
	return ""

static func _integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = value
	return is_finite(number) and number == floor(number)

static func _to_int(value: Variant) -> int:
	var number: float = value
	return int(number)
