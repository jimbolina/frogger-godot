class_name TerrainScenarioJson
extends RefCounted
## Validates authored JSON inputs before constructing detached rule definitions.

static func apply(scenario: TerrainScenario, object: Dictionary) -> String:
	for key: String in ["level", "start", "grid"]:
		if object.has(key) and not object[key] is Dictionary:
			return "Scenario %s must be an object" % key
	var level: Dictionary = object.get("level", {})
	var start: Dictionary = object.get("start", {})
	for pair: Array in [[scenario.level, level, ["spawn_direction", "theme", "theme_death_height", "map_index"]], [scenario.initial, start, ["seed", "spawn_direction", "powerup_flags", "quick_jump_timer", "auto_hop_timer", "super_tongue_timer", "lives", "start_timer", "start_mode"]]]:
		var target: Object = pair[0]
		var values: Dictionary = pair[1]
		var keys: Array = pair[2]
		for key: String in keys:
			if values.has(key):
				if not (_uint32(values[key]) if key in ["seed", "powerup_flags"] else _integer(values[key])):
					return "%s must be an integer" % key
				target.set(key, _number(values[key]))
	for pair: Array in [[scenario.level, level], [scenario.initial, start]]:
		var target: Object = pair[0]
		var values: Dictionary = pair[1]
		if values.has("spawn_cell"):
			if not _vector(values.spawn_cell, 2):
				return "spawn_cell must contain two integers"
			var cell: Array = values.spawn_cell
			target.set("spawn_cell", Vector2i(_number(cell[0]), _number(cell[1])))
	if level.has("collision_enabled"):
		if not level.collision_enabled is bool:
			return "collision_enabled must be boolean"
		scenario.level.collision_enabled = level.collision_enabled
	if start.has("camera_startup"):
		if not start.camera_startup is bool:
			return "camera_startup must be boolean"
		scenario.initial.camera_startup = start.camera_startup
	if level.has("theme_name"):
		if not level.theme_name is String:
			return "theme_name must be a string"
		var theme_name: String = level.theme_name
		scenario.level.theme_name = StringName(theme_name)
	if level.has("collision_bounds"):
		if not _vector(level.collision_bounds, 4):
			return "collision_bounds must contain four integers"
		var bounds: Array = level.collision_bounds
		scenario.level.collision_bounds = Rect2i(_number(bounds[0]), _number(bounds[1]), _number(bounds[2]), _number(bounds[3]))
	for key: String in ["frog_action_lengths", "controller_directions"]:
		var values: Dictionary = level if key == "frog_action_lengths" else start
		if values.has(key):
			if not values[key] is Array:
				return "%s must be an integer array" % key
			var packed := PackedInt32Array()
			for value: Variant in values[key]:
				if not _integer(value):
					return "%s must contain integers" % key
				packed.append(_number(value))
			if key == "frog_action_lengths":
				scenario.level.frog_action_lengths = packed
			else:
				scenario.initial.controller_directions = packed
	if level.has("camera"):
		if not level.camera is Dictionary:
			return "camera must be an object"
		var camera: Dictionary = level.camera
		for key: String in ["source_offset", "target_offset"]:
			if camera.has(key):
				if not _vector(camera[key], 3):
					return "camera %s must contain three integers" % key
				var coordinates: Array = camera[key]
				scenario.level.camera.set(key, Vector3i(_number(coordinates[0]), _number(coordinates[1]), _number(coordinates[2])))
	if not object.has("grid"):
		return ""
	var authored: Dictionary = object.grid
	if not _vector(authored.get("dimensions"), 2) or not _vector(authored.get("base"), 2):
		return "grid dimensions and base must contain two integers"
	if not authored.get("stacks") is Array or not authored.get("squares") is Array:
		return "grid stacks and squares must be arrays"
	var grid := GridDefinition.new()
	var dimensions: Array = authored.dimensions
	var base: Array = authored.base
	grid.dimensions = Vector2i(_number(dimensions[0]), _number(dimensions[1]))
	grid.base = Vector2i(_number(base[0]), _number(base[1]))
	for value: Variant in authored.stacks:
		if not _vector(value, 2):
			return "Each stack must contain first square and count integers"
		var row: Array = value
		var stack := GridStackDefinition.new()
		stack.first_square_index = _number(row[0])
		stack.square_count = _number(row[1])
		grid.stacks.append(stack)
	for value: Variant in authored.squares:
		if not value is Dictionary:
			return "Each grid square must be an object"
		var row: Dictionary = value
		if not _uint32(row.get("flags")) or not row.get("vertices") is Array:
			return "Square flags and vertices are required"
		var vertices: Array = row.vertices
		if vertices.size() != 4:
			return "Each square requires four vertices"
		var square := GridSquareDefinition.new()
		square.flags = _number(row.flags)
		for vertex: Variant in vertices:
			if not _vector(vertex, 3):
				return "Each vertex must contain three integers"
			var coordinates: Array = vertex
			square.vertices.append(Vector3i(_number(coordinates[0]), _number(coordinates[1]), _number(coordinates[2])))
		for key: String in ["source_offset", "polygon_index", "polygon_source_offset"]:
			if row.has(key):
				if not _integer(row[key]):
					return "Square %s must be an integer" % key
				square.set(key, _number(row[key]))
		grid.squares.append(square)
	scenario.level.grid = grid
	return ""

static func _vector(value: Variant, count: int) -> bool:
	if not value is Array:
		return false
	var array: Array = value
	if array.size() != count:
		return false
	for item: Variant in array:
		if not _integer(item):
			return false
	return true

static func _integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = value
	return is_finite(number) and number == floor(number) and number >= -2147483648.0 and number <= 2147483647.0

static func _number(value: Variant) -> int:
	var number: float = value
	return int(number)

static func _uint32(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = value
	return is_finite(number) and number == floor(number) and number >= 0.0 and number <= 4294967295.0
