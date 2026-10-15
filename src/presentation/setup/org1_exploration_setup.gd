class_name Org1ExplorationSetup
extends RefCounted
## Strict supplied-data admission for the independently proved ORG1 round trip.

const PRESET: String = "org1-turtle-log-bank"
const MANIFEST_PATH: String = "res://src/presentation/setup/org1_exploration_admission.json"

## Validates proof inputs before enabling any custom update or contact exclusion.
static func apply(scenario: TerrainScenario, data: GameData) -> String:
	if scenario.level_code.to_upper() != "ORG1" or scenario.entity_lifecycle:
		return "org1-turtle-log-bank requires high-detail ORG1 and all-attached lifetime"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return "ORG1 admission manifest is unavailable"
	var proof: Dictionary = parsed
	if proof.get("schema") != "org1-route-admission-v1" or data.version.internal_name != proof.get("build"):
		return "ORG1 exploration requires audited pc-retail-v3.0e inputs"
	var map: MapFile = scenario.map_scene.map
	var issue: String = RetailExplorationInputs.validate(data, map, proof, scenario.map_scene.level)
	if not issue.is_empty():
		return "ORG1 exploration proof inputs changed: " + issue
	var frog: MwiEntry = data.find_resource("GEN_FROG.XAR")
	if frog == null or frog.index != _integer(proof.frog_resource_id):
		return "ORG1 admitted frog resource mapping changed"
	var zones: MapPacket = map.packets.get("ZONE")
	if zones != null and zones.count != 0:
		return "ORG1 admission requires no zones"
	var book: ThemeBook = data.tables.theme_book()
	var script_names: NameBank = data.tables.names.scripts
	var callback_names: NameBank = script_names.get_sub_bank("CallbackNames")
	var expected_scripts: Array = proof.get("script_names", [])
	var expected_callbacks: Array = proof.get("callback_names", [])
	if expected_scripts.size() != script_names.size() or callback_names == null or expected_callbacks.size() != callback_names.size():
		return "ORG1 script/callback name inventory changed"
	for index: int in expected_scripts.size():
		if expected_scripts[index] != script_names.get_name(index):
			return "ORG1 script name mapping changed"
	for index: int in expected_callbacks.size():
		if expected_callbacks[index] != callback_names.get_name(index):
			return "ORG1 callback name mapping changed"
	var setup: EntitySetup = EntitySetup.from_map(map, book, scenario.level.source_id, scenario.level.resource_id, data.version.internal_name, true)
	if not setup.error.is_empty() or setup.definitions.size() != _integer(proof.authored_count):
		return "ORG1 requires every authored logical update: " + setup.error
	var models: Dictionary[int, MofFile] = {}
	var bindings: Array = proof.get("name_bindings", [])
	if bindings.size() != setup.definitions.size():
		return "ORG1 named behavior admission is incomplete"
	var problems := PackedStringArray()
	for entity: EntityDefinition in setup.definitions:
		var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		if form == null:
			return "ORG1 missing form"
		var binding: Dictionary = bindings[entity.entity_index]
		if binding.form != entity.form_name or binding.entity != entity.entity_name or binding.script != script_names.get_name(entity.script_id):
			return "ORG1 named behavior mapping changed"
		var model_id: int = data.model_resource_at(data.model_wad_for(form, scenario.map_scene.level, false), form.wad_index()) if form.model_id >= 0 else -1
		if model_id >= 0 and not models.has(entity.form_id):
			models[entity.form_id] = data.read_model(model_id, problems)
		var model: MofFile = models.get(entity.form_id)
		if model != null and model.kind != MofFile.Kind.DUMMY and not form.has_flag(FormBookEntry.FLAG_NO_MODEL):
			if model.static_models.is_empty() or model.static_models[0].parts.is_empty():
				return "ORG1 model lacks admitted animation data"
			for action: MofPart.FlipbookAction in model.static_models[0].parts[0].flipbook_actions:
				entity.action_lengths.append(action.frame_count)
			entity.animation_one_shot = entity.entity_name == "ORG_BABY_FROG"
		if entity.script_id != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(data.tables.scripts(), data.tables.names.scripts, entity.script_id, entity.entity_name, map.entities[entity.entity_index].payload)
			if not scripts.error.is_empty():
				return scripts.error
			entity.script_definition = scripts.definition
			issue = entity.script_definition.validate(entity.action_lengths, entity.form_id, entity.path_definition != null)
			if not issue.is_empty():
				return issue
	if not problems.is_empty():
		return "; ".join(problems)
	var contacts: FormContactSetup = FormContactSetup.from_map(map, book, setup.definitions, models)
	if not contacts.error.is_empty():
		return contacts.error
	var collision := EntityCollisionDefinition.new()
	collision.platforms_enabled = true
	collision.group_base = map.group_base
	collision.group_dimensions = map.group_dimensions
	collision.group_size = map.group_size
	collision.environment = EntityEnvironmentState.new()
	for unused: int in 5:
		collision.environment.checkpoint_positions.append(Vector3i.ZERO)
	var included := PackedInt32Array()
	for value: Variant in proof.included_contact_indices:
		included.append(_integer(value))
	var exclusions: Array = proof.get("contact_exclusions", [])
	if included.size() + exclusions.size() != setup.definitions.size():
		return "ORG1 requires individual excluded-neighbor evidence"
	for slot: int in setup.definitions.size():
		var entity: EntityDefinition = setup.definitions[slot]
		var contact: FormContactDefinition = contacts.definitions[slot]
		var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		contact.form_book_flags = form.flags
		if included.has(slot):
			if not contact.unsupported_reason.is_empty():
				return "ORG1 required contact %d: %s" % [slot, contact.unsupported_reason]
		else:
			for item: Dictionary in exclusions:
				if _integer(item.index) == slot and _integer(item.unique_id) == entity.unique_id and _integer(item.offset) == entity.source_offset:
					contact.admission_exclusion = item.reason
			if contact.admission_exclusion.is_empty():
				return "ORG1 missing exclusion evidence for entity %d" % slot
		if entity.entity_name == "CHECKPOINT":
			var checkpoint: int = entity.form_id & 32767
			if checkpoint < 0 or checkpoint >= 5:
				return "ORG1 checkpoint identity changed"
			collision.environment.checkpoint_positions[checkpoint] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		collision.entities.append(entity)
		collision.contacts.append(contact)
	issue = collision.validate()
	if not issue.is_empty():
		return issue
	var top: PackedInt32Array = setup.definitions[61].matrix12
	var bottom: PackedInt32Array = setup.definitions[60].matrix12
	scenario.level.collision_bounds = Rect2i(top[9], bottom[11], bottom[9] - top[9], top[11] - bottom[11])
	var guard := ExplorationGuard.new()
	var x: Array = proof.admitted_x
	var z: Array = proof.admitted_z
	guard.world_bounds = Rect2i(_integer(x[0]), _integer(z[0]), _integer(x[1]) - _integer(x[0]), _integer(z[1]) - _integer(z[0]))
	for root: Array in proof.frog_roots:
		var values := PackedInt32Array()
		for value: Variant in root:
			values.append(_integer(value))
		guard.frog_roots.append(values)
	for action: Variant in proof.live_frog_actions:
		guard.frog_actions.append(_integer(action))
	issue = guard.validate()
	if not issue.is_empty():
		return issue
	scenario.level.exploration_guard = guard
	scenario.entity_collision = collision
	scenario.level.entity_collision = collision.copy()
	scenario.initial.spawn_cell = Vector2i(10, 7)
	scenario.initial.spawn_direction = 0
	scenario.initial.controller_directions = PackedInt32Array()
	scenario.initial.camera_startup = false
	scenario.identifier = PRESET
	if not scenario.tick_limit_override and not scenario.authored_fixture:
		scenario.tick_limit = 730
	if not scenario.authored_fixture:
		scenario.commands.clear()
	scenario.diagnostics.append("ORG1 audited all-attached exploration; 64 logical updates; ten contact entities; active zones and primitive execution unsupported")
	return ""

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)
