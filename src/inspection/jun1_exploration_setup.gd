class_name Jun1ExplorationSetup
extends RefCounted
## Admits only the independently audited JUN1 inputs for bounded bank/log inspection.

const MANIFEST_PATH: String = "res://src/inspection/jun1_exploration_admission.json"
const PRESET: String = "jun1-log-bank"

## Validates proof dependencies and copies decoded zones into an inspection guard.
static func apply(scenario: TerrainScenario, data: GameData) -> String:
	if scenario.level_code.to_upper() != "JUN1" or scenario.options.entity_lifecycle:
		return "jun1-log-bank requires high-detail JUN1 and all-attached lifetime"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return "JUN1 exploration admission manifest is unavailable"
	var proof: Dictionary = parsed
	if proof.get("schema", "") != "jun1-route-admission-v1" or data.version.internal_name != proof.get("build", ""):
		return "jun1-log-bank requires audited pc-retail-v3.0e inputs"
	var issue: String = _validate_inputs(data, scenario.map_scene.map, proof)
	if not issue.is_empty():
		return "JUN1 exploration proof inputs changed: " + issue
	if scenario.entity_collision == null:
		return "JUN1 exploration requires detached entity collision setup"
	for slot: int in range(scenario.entity_collision.entities.size() - 1, -1, -1):
		var entity: EntityDefinition = scenario.entity_collision.entities[slot]
		if entity.behavior.kind == EntityBehavior.Kind.PATH_FOLLOWER and entity.behavior.tongueable:
			scenario.entity_collision.entities.remove_at(slot)
			scenario.entity_collision.contacts.remove_at(slot)
	scenario.level.entity_collision = scenario.entity_collision.copy()
	scenario.diagnostics.append("JUN1 bounded proof omits moving tongue collectables; whole-map behavior is unaffected")
	var zones: ZoneSetup = ZoneSetup.from_map(scenario.map_scene.map, scenario.level.source_id, scenario.level.resource_id, data.version.internal_name)
	if not zones.error.is_empty():
		return zones.error
	var guard := ExplorationGuard.new()
	var bounds_x: Array = proof.admitted_x
	var bounds_z: Array = proof.admitted_z
	guard.world_bounds = Rect2i(_integer(bounds_x[0]), _integer(bounds_z[0]), _integer(bounds_x[1]) - _integer(bounds_x[0]), _integer(bounds_z[1]) - _integer(bounds_z[0]))
	for zone: ZoneDefinition in zones.definitions:
		guard.zones.append(zone.copy())
	issue = guard.validate()
	if not issue.is_empty():
		return issue
	scenario.level.tick_guard = guard
	scenario.initial.spawn_cell = Vector2i(22, 10)
	scenario.initial.spawn_direction = 3
	scenario.initial.controller_directions = PackedInt32Array()
	scenario.initial.camera_startup = false
	scenario.identifier = PRESET
	if not scenario.options.tick_limit_override and not scenario.options.authored_fixture:
		scenario.tick_limit = 60
	if not scenario.options.authored_fixture:
		scenario.commands.clear()
	scenario.diagnostics.append("JUN1 bounded exploration: audited inputs only; all-attached lifetime; active camera zones unsupported")
	scenario.diagnostics.append("World boundary X[1900,2304), Z[-5376,-4864); rejected ticks roll back and pause")
	return ""

static func _validate_inputs(data: GameData, map: MapFile, proof: Dictionary) -> String:
	return RetailExplorationInputs.validate(data, map, proof, 18)

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)
