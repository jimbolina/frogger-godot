class_name EntityScenario
extends RefCounted
## Detached entity run stimulus for inspection and schedule comparisons.

var definitions: Array[EntityDefinition] = []
var contact_definitions: Array[FormContactDefinition] = []
var probe_world: Vector3i = Vector3i.ZERO
var contact_entity_index: int = -1
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
	anchor.behavior = EntityBehaviorCatalog.resolve(anchor.entity_name)
	anchor.matrix12[9] = -150
	scenario.definitions.append(anchor)
	for index: int in 3:
		var moving := EntityDefinition.new()
		moving.source_id = path.source_id
		moving.entity_index = index + 1
		moving.unique_id = 11 + index
		moving.form_name = "SYNTHETIC_MOVING"
		moving.entity_name = "MOVING"
		moving.behavior = EntityBehaviorCatalog.resolve(moving.entity_name)
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
	for definition: EntityDefinition in scenario.definitions:
		var contact := FormContactDefinition.new()
		contact.source_id = definition.source_id
		contact.entity_index = definition.entity_index
		contact.unique_id = definition.unique_id
		contact.form_grid_id = definition.form_grid_id
		contact.form_id = definition.form_id
		contact.form_name = definition.form_name
		contact.entity_flags = definition.flags
		contact.dimensions = Vector2i(2, 2)
		contact.offsets = Vector2i(-256, -256)
		contact.height = -32
		contact.max_y = 32
		contact.radius_squared = 1000000
		contact.grid_flags = PackedInt32Array([3, 1, 5, 7])
		scenario.contact_definitions.append(contact)
	scenario.contact_entity_index = 1
	scenario.probe_world = Vector3i(-100, 0, 0)
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
	var contacts: FormContactSetup = FormContactSetup.from_data(data, number, false, copies)
	if not contacts.error.is_empty():
		return contacts.error
	definitions = copies
	contact_definitions.clear()
	for contact: FormContactDefinition in contacts.definitions:
		contact_definitions.append(contact.copy())
	contact_entity_index = 12 if selected_code == "ORG1" and _has_contact_index(12) else -1
	if contact_entity_index < 0:
		for contact: FormContactDefinition in contact_definitions:
			if contact.unsupported_reason.is_empty() and not (contact.entity_flags & EntityDefinition.NO_COLLISION):
				contact_entity_index = contact.entity_index
				break
	if contact_entity_index < 0 and not contact_definitions.is_empty():
		contact_entity_index = contact_definitions[0].entity_index
	if contact_entity_index >= 0:
		var selected_definition: FormContactDefinition = _contact_at(contact_entity_index)
		var first_entity: EntitySnapshot = _entity_at(run.snapshot(), contact_entity_index)
		probe_world = _first_cell_world(selected_definition, first_entity)
	diagnostics.clear()
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		diagnostics.append(diagnostic.to_text())
	for diagnostic: EntitySetupDiagnostic in contacts.diagnostics:
		diagnostics.append(diagnostic.to_text())
	level_code = selected_code
	name = selected_code.to_lower() + "-entities"
	return ""

## Returns the selected contact definition by authored entity index.
func selected_contact() -> FormContactDefinition:
	return _contact_at(contact_entity_index)

## Returns the detached query result at the fixed scenario probe point.
func contact_at(snapshot: EntityRunSnapshot) -> FormContactResult:
	if snapshot == null:
		return null
	var contact: FormContactDefinition = _contact_at(contact_entity_index)
	var entity: EntitySnapshot = _entity_at(snapshot, contact_entity_index)
	if contact == null or entity == null:
		return null
	return FormContactQuery.query(contact, entity, probe_world)

func _has_contact_index(index: int) -> bool:
	return _contact_slot(index) >= 0

func _contact_slot(index: int) -> int:
	for slot: int in contact_definitions.size():
		if contact_definitions[slot].entity_index == index:
			return slot
	return -1

func _contact_at(index: int) -> FormContactDefinition:
	var slot: int = _contact_slot(index)
	return contact_definitions[slot] if slot >= 0 else null

static func _entity_at(snapshot: EntityRunSnapshot, index: int) -> EntitySnapshot:
	if snapshot == null:
		return null
	for entity: EntitySnapshot in snapshot.entities:
		if entity.entity_index == index:
			return entity
	return null

static func _first_cell_world(contact: FormContactDefinition, entity: EntitySnapshot) -> Vector3i:
	if entity == null:
		return Vector3i.ZERO
	var matrix: PackedInt32Array = entity.matrix12
	if contact == null or matrix.size() != 12 or contact.dimensions.x <= 0 or contact.dimensions.y <= 0:
		return Vector3i(matrix[9], matrix[10], matrix[11]) if matrix.size() == 12 else Vector3i.ZERO
	var local: Vector3i = Vector3i(contact.offsets.x + 128, contact.height, contact.offsets.y + 128)
	return Vector3i(matrix[9] + ((matrix[0] * local.x + matrix[1] * local.y + matrix[2] * local.z) >> 12),
		matrix[10] + ((matrix[3] * local.x + matrix[4] * local.y + matrix[5] * local.z) >> 12),
		matrix[11] + ((matrix[6] * local.x + matrix[7] * local.y + matrix[8] * local.z) >> 12))
