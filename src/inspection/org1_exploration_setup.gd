class_name Org1ExplorationSetup
extends RefCounted
## Strict supplied-data admission for independently proved guarded ORG1 routes.

const PRESET: String = "org1-turtle-log-bank"
const MANIFEST_PATH: String = "res://src/inspection/org1_exploration_admission.json"
const VISIBILITY_PRESET: String = "org1-turtle-log-bank-visibility"
const VISIBILITY_MANIFEST_PATH: String = "res://src/inspection/org1_visibility_admission.json"
const ROAD_PRESET: String = "org1-road-river"
const ROAD_MANIFEST_PATH: String = "res://src/inspection/org1_road_river_admission.json"

## Validates proof inputs before enabling any custom update or contact exclusion.
static func apply(scenario: TerrainScenario, data: AssetCatalog) -> String:
	var road: bool = scenario.options.exploration_preset == ROAD_PRESET
	var visibility: bool = scenario.options.exploration_preset == VISIBILITY_PRESET
	var preset: String = VISIBILITY_PRESET if visibility else ROAD_PRESET if road else PRESET
	if scenario.level_code.to_upper() != "ORG1" or (scenario.options.entity_lifecycle and not visibility):
		return preset + " requires high-detail ORG1 and all-attached lifetime"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VISIBILITY_MANIFEST_PATH if visibility else ROAD_MANIFEST_PATH if road else MANIFEST_PATH))
	if not parsed is Dictionary:
		return "ORG1 admission manifest is unavailable"
	var proof: Dictionary = parsed
	var schema: String = "org1-visibility-admission-v2" if visibility else "org1-road-river-admission-v1" if road else "org1-route-admission-v1"
	if proof.get("schema") != schema or data.version.internal_name != proof.get("build"):
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
	var script_names: NameBank = data.names.scripts
	var callback_names: NameBank = script_names.get_sub_bank("CallbackNames")
	var expected_scripts: Array = proof.get("script_names", [])
	var expected_callbacks: Array = proof.get("callback_names", [])
	if expected_scripts.size() != script_names.size() or callback_names == null or expected_callbacks.size() != callback_names.size():
		return "ORG1 script/callback name inventory changed"
	for index: int in expected_scripts.size():
		if expected_scripts[index] != script_names.name_of(index):
			return "ORG1 script name mapping changed"
	for index: int in expected_callbacks.size():
		if expected_callbacks[index] != callback_names.name_of(index):
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
		if binding.form != entity.form_name or binding.entity != entity.entity_name or binding.script != script_names.name_of(entity.script_id):
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
			entity.behavior.one_shot = entity.behavior.kind == EntityBehavior.Kind.BABY_FROG
		if entity.script_id != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(data.tables.scripts(), data.names.scripts, entity.script_id, entity.behavior, map.entities[entity.entity_index].payload)
			if not scripts.error.is_empty():
				return scripts.error
			entity.script_definition = scripts.definition
			issue = entity.script_definition.validate(entity.action_lengths, entity.form_id, entity.path_definition != null)
			if not issue.is_empty():
				return issue
	if not problems.is_empty():
		return "; ".join(problems)
	if visibility:
		var baby: EntityDefinition = _unique_role(setup.definitions, EntityBehavior.Kind.BABY_FROG)
		if baby == null:
			return "ORG1 requires one baby frog binding"
		baby.behavior.execution = EntityBehavior.Execution.CONTACT
	var contacts: FormContactSetup = FormContactSetup.from_map(map, book, setup.definitions, models, "", -1, "", road)
	if not contacts.error.is_empty():
		return contacts.error
	var collision := EntityCollisionDefinition.new()
	if visibility:
		var lifecycle: EntityLifecycleSetup = EntityLifecycleSetup.from_map(map)
		if not lifecycle.error.is_empty():
			return lifecycle.error
		collision.lifecycle = lifecycle.definition
		scenario.options.lifecycle = ScenarioOptions.Lifecycle.VISIBILITY
	if road:
		var probes: FrogCollisionSetup = FrogCollisionSetup.from_model(scenario.frog_assets.model)
		if not probes.error.is_empty():
			return "ORG1 frog collision points: " + probes.error
		collision.frog_collision = probes.definition
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
					contact.disabled_reason = item.reason
			if contact.disabled_reason.is_empty():
				return "ORG1 missing exclusion evidence for entity %d" % slot
		if entity.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			var checkpoint: int = entity.form_id & 32767
			if checkpoint < 0 or checkpoint >= 5:
				return "ORG1 checkpoint identity changed"
			collision.environment.checkpoint_positions[checkpoint] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		collision.entities.append(entity)
		collision.contacts.append(contact)
	issue = collision.validate()
	if not issue.is_empty():
		return issue
	var top_entity: EntityDefinition = _unique_role(setup.definitions, EntityBehavior.Kind.BOUNDS_TOP_LEFT)
	var bottom_entity: EntityDefinition = _unique_role(setup.definitions, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT)
	if top_entity == null or bottom_entity == null:
		return "ORG1 requires unique boundary bindings"
	var top: PackedInt32Array = top_entity.matrix12
	var bottom: PackedInt32Array = bottom_entity.matrix12
	scenario.level.collision_bounds = Rect2i(top[9], bottom[11], bottom[9] - top[9], top[11] - bottom[11])
	var guard := ExplorationGuard.new()
	if visibility:
		guard.scripted_visibility_admitted = true
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
	scenario.level.tick_guard = guard
	scenario.entity_collision = collision
	scenario.level.entity_collision = collision.copy()
	if road:
		var spawn: Array = proof.spawn_cell
		scenario.initial.spawn_cell = Vector2i(_integer(spawn[0]), _integer(spawn[1]))
		scenario.initial.spawn_direction = _integer(proof.spawn_direction)
	else:
		scenario.initial.spawn_cell = Vector2i(10, 7)
		scenario.initial.spawn_direction = 0
	scenario.initial.controller_directions = PackedInt32Array()
	scenario.initial.camera_startup = false
	scenario.identifier = preset
	if not scenario.options.tick_limit_override and not scenario.options.authored_fixture:
		scenario.tick_limit = _integer(proof.default_ticks) if road else 730
	if not scenario.options.authored_fixture:
		scenario.commands.clear()
	if visibility:
		scenario.diagnostics.append("ORG1 guarded scripted visibility; pink frog pickup and riding; eleven FORMs; active zones and primitive execution unsupported")
	elif road:
		scenario.diagnostics.append("ORG1 audited road-to-river exploration; all-attached lifetime; 64 logical updates; 24 primitive traffic contacts and ten river FORMs; active zones unsupported")
	else:
		scenario.diagnostics.append("ORG1 audited all-attached exploration; 64 logical updates; ten contact entities; active zones and primitive execution unsupported")
	return ""

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

static func _unique_role(definitions: Array[EntityDefinition], kind: EntityBehavior.Kind) -> EntityDefinition:
	var selected: EntityDefinition = null
	for definition: EntityDefinition in definitions:
		if definition.behavior.kind == kind:
			if selected != null:
				return null
			selected = definition
	return selected
