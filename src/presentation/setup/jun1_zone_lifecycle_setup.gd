class_name Jun1ZoneLifecycleSetup
extends RefCounted
## Admits only independently pinned JUN1 logs for the prescribed camera probe.

const MANIFEST: String = "res://src/presentation/setup/jun1_zone_lifecycle_admission.json"
var error: String = ""
var definitions: Array[EntityDefinition] = []
var lifecycle: EntityLifecycleDefinition = null
var diagnostics: PackedStringArray = PackedStringArray()

## Resolves supplied behavior names and resources; this does not admit frog contact.
static func from_data(data: GameData, scene: MapSceneData) -> Jun1ZoneLifecycleSetup:
	var result := Jun1ZoneLifecycleSetup.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		result.error = "JUN1 zone/lifecycle admission manifest unavailable"
		return result
	var proof: Dictionary = parsed
	if proof.get("schema") != "jun1-zone-lifecycle-admission-v1" or data.version.internal_name != proof.get("build"):
		result.error = "JUN1 zone/lifecycle requires audited pc-retail-v3.0e data"
		return result
	var book: MapBookEntry = data.map_book_entry(scene.level)
	if book == null or book.map_id(false) != _integer(proof.map_resource_id):
		result.error = "JUN1 zone/lifecycle high-detail map mapping changed"
		return result
	var problems := PackedStringArray()
	if _digest(data.read_resource(book.map_id(false), problems)) != proof.map_sha256:
		result.error = "JUN1 zone/lifecycle map, paths or zones changed"
		return result
	var setup: EntitySetup = EntitySetup.from_map(scene.map, data.tables.theme_book(), "JUN1", book.map_id(false), data.version.internal_name)
	if not setup.error.is_empty():
		result.error = setup.error
		return result
	var bindings: Array = []
	for entity: EntityDefinition in setup.definitions:
		if entity.form_name != "JUN_LOG":
			continue
		var form: FormBookEntry = data.tables.theme_book().get_form(scene.map.general.theme, entity.form_id)
		bindings.append([entity.entity_index, entity.form_id, entity.unique_id, entity.form_name, entity.entity_name,
			entity.script_id, entity.collision_callback, entity.bonus_callback, entity.flags,
			data.model_resource_for(form, scene.level)])
		result.definitions.append(entity.copy())
	if JSON.stringify(JSON.parse_string(JSON.stringify(bindings))) != JSON.stringify(proof.bindings):
		result.error = "JUN1 zone/lifecycle log identities, named behaviors or models changed"
		return result
	for raw: Variant in proof.models:
		var model: Dictionary = raw
		if _digest(data.read_resource(_integer(model.resource_id), problems)) != model.sha256:
			result.error = "JUN1 zone/lifecycle log model changed"
			return result
	if not problems.is_empty():
		result.error = "; ".join(problems)
		return result
	var groups: EntityLifecycleSetup = EntityLifecycleSetup.from_map(scene.map)
	result.error = groups.error
	result.lifecycle = groups.definition
	for index: int in scene.map.entities.size():
		var admitted: bool = false
		for entity: EntityDefinition in result.definitions:
			admitted = admitted or entity.entity_index == index
		if not admitted:
			result.diagnostics.append("JUN1 EMTP[%d]: omitted from log-only camera/lifecycle probe; no behavior or contact executed" % index)
	return result

static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)
