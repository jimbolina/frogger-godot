class_name CameraZoneInspection
extends RefCounted
## Deterministic JUN1 camera probe; prescribed positions make no playable-route claim.

const PRESET: String = "jun1-camera-zones"
const TICK_LIMIT: int = 320
const CELLS: Array[Vector2i] = [Vector2i(10, 3), Vector2i(11, 3), Vector2i(11, 4), Vector2i(11, 5), Vector2i(14, 22), Vector2i(15, 22), Vector2i(14, 23), Vector2i(14, 24)]
var error: String = ""
var map_scene: MapSceneData = null
var zones: Array[ZoneDefinition] = []
var definition: GameplayCameraDefinition = null
var grid_base: Vector2i = Vector2i.ZERO
var camera: GameplayCamera = null
var selected: Vector2i = Vector2i(-1, -1)
var tick: int = 0
var cell: Vector2i = CELLS[0]
var world: Vector3i = Vector3i.ZERO
var row: Dictionary = {}
var entity_definitions: Array[EntityDefinition] = []
var lifecycle: EntityLifecycleDefinition = null
var entities: EntityRun = null
var diagnostics: PackedStringArray = PackedStringArray()

## Resolves high-detail JUN1 through the supplied executable and copies its camera data.
static func from_data(data: GameData, visibility_enabled: bool = false) -> CameraZoneInspection:
	var result := CameraZoneInspection.new()
	if data == null or data.version.internal_name != "pc-retail-v3.0e":
		result.error = "jun1-camera-zones inspection is verified only for pc-retail-v3.0e"
		return result
	var number: int = FroggerIds.level_from_code("JUN1")
	result.map_scene = MapSceneData.load_level(data, number, false)
	if not result.map_scene.error.is_empty():
		result.error = result.map_scene.error
		return result
	var book: MapBookEntry = data.map_book_entry(number)
	var setup: ZoneSetup = ZoneSetup.from_map(result.map_scene.map, "JUN1", book.map_id(false), data.version.internal_name)
	if not setup.error.is_empty():
		result.error = setup.error
		return result
	result.zones = setup.definitions
	var grid: TerrainGridSetup = TerrainGridSetup.from_map(result.map_scene.map)
	if not grid.error.is_empty():
		result.error = grid.error
		return result
	result.grid_base = grid.definition.base
	result.definition = GameplayCameraDefinition.new()
	result.definition.source_offset = result.map_scene.map.general.camera_source_offset
	result.definition.target_offset = result.map_scene.map.general.camera_target_offset
	if visibility_enabled:
		var logs: Jun1ZoneLifecycleSetup = Jun1ZoneLifecycleSetup.from_data(data, result.map_scene)
		if not logs.error.is_empty():
			result.error = logs.error
			return result
		result.entity_definitions = logs.definitions
		result.lifecycle = logs.lifecycle
		result.diagnostics = logs.diagnostics
	result.error = result.reset()
	return result

## Rewinds both prescribed sequences and their camera/selection state.
func reset() -> String:
	var next_camera: GameplayCamera = _new_camera(0)
	if not next_camera.error.is_empty():
		return next_camera.error
	var next_entities: EntityRun = EntityRun.create(entity_definitions, lifecycle) if lifecycle != null else null
	if next_entities != null and not next_entities.error.is_empty():
		return next_entities.error
	camera = next_camera
	entities = next_entities
	selected = Vector2i(-1, -1)
	tick = 0
	cell = CELLS[0]
	world = _world(cell)
	row = {}
	return ""

## Advances one exact source camera update, publishing a detached inspection row.
func step() -> String:
	if tick >= TICK_LIMIT:
		return "Camera inspection is complete; reset to replay"
	var next_camera: GameplayCamera = _new_camera(2048) if tick == 160 else camera.copy()
	if not next_camera.error.is_empty():
		return next_camera.error
	var next_entities: EntityRun = entities
	if tick == 160 and lifecycle != null:
		next_entities = EntityRun.create(entity_definitions, lifecycle)
	if next_entities != null:
		if not next_entities.error.is_empty():
			return next_entities.error
		next_entities = next_entities.begin_candidate(tick % 160)
		if not next_entities.error.is_empty():
			return next_entities.error
	@warning_ignore("integer_division")
	var segment: int = tick / 40
	var next_cell: Vector2i = CELLS[segment]
	var next_world: Vector3i = _world(next_cell)
	var pending: Vector2i = ZoneQueries.update_camera_match(zones, next_cell, Vector2i(-1, -1) if tick == 160 else selected)
	var input := GameplayCameraTick.new()
	input.frog_world = next_world
	input.camera_zone = ZoneQueries.definition_for(zones, pending.x)
	var issue: String = next_camera.step(input)
	if not issue.is_empty():
		return issue
	if next_entities != null:
		next_entities.advance_animations()
		issue = next_entities.apply_visibility(next_camera.snapshot())
		if not issue.is_empty():
			return issue
	camera = next_camera
	entities = next_entities
	cell = next_cell
	world = next_world
	selected = pending
	row = {"tick": tick, "sequence": 0 if tick < 160 else 1, "cell": [cell.x, cell.y], "world": [world.x, world.y, world.z], "frog_zone": selected.x, "frog_region": selected.y, "camera": TerrainTrace.facts(camera.snapshot())}
	if entities != null:
		row["entity_lifecycle"] = TerrainTrace.facts(entities.snapshot(), true)
		var total: int = 0
		for group: int in entities.snapshot().selected_groups:
			total += lifecycle.polygon_counts[group]
		row["polygon_total"] = total
	tick += 1
	return ""

func _new_camera(angle: int) -> GameplayCamera:
	var result: GameplayCamera = GameplayCamera.create(definition, Vector3i.ZERO)
	if result.error.is_empty():
		result.error = result.transition_attachment(PlatformMath.yaw(angle), PackedInt32Array(), false)
	return result

func _world(at: Vector2i) -> Vector3i:
	return Vector3i(grid_base.x + at.x * 256 + 128, 0, grid_base.y + at.y * 256 + 128)
