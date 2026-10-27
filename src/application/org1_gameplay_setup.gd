class_name Org1GameplaySetup
extends RefCounted
## Whole-map ORG1 dependency validation without route or byte-identity admission.

var error: String = ""
var definition: LevelDefinition = null
var diagnostics: Array[EntitySetupDiagnostic] = []

## Resolves player tables, scripts, callbacks, geometry and visibility once at setup.
static func from_data(data: GameData, map: MapFile, frog_model: MofFile, action_lengths: PackedInt32Array) -> Org1GameplaySetup:
	var result := Org1GameplaySetup.new()
	result.error = result._build(data, map, frog_model, action_lengths)
	if not result.error.is_empty():
		result.definition = null
	return result

func _build(data: GameData, map: MapFile, frog_model: MofFile, action_lengths: PackedInt32Array) -> String:
	if data.version.internal_name != "pc-retail-v3.0e":
		return "ORG1 gameplay requires the verified pc-retail-v3.0e build"
	var number: int = FroggerIds.level_from_code("ORG1")
	var book: MapBookEntry = data.map_book_entry(number)
	var theme: ThemeBookEntry = data.theme_book_entry(map.general.theme)
	if book == null or theme == null:
		return "ORG1 gameplay requires map and theme definitions"
	var source: String = data.version.internal_name + ":ORG1"
	var grid: TerrainGridSetup = TerrainGridSetup.from_map(map)
	var zones: ZoneSetup = ZoneSetup.from_map(map, source, book.map_id(false), data.version.internal_name)
	var lifecycle: EntityLifecycleSetup = EntityLifecycleSetup.from_map(map)
	var frog: FrogCollisionSetup = FrogCollisionSetup.from_model(frog_model)
	var rewards: RewardSetup = RewardSetup.from_table(data.tables.scores())
	var sounds: LogicalSoundSetup = LogicalSoundSetup.from_data(data, PackedInt32Array([0, 5]))
	for issue: String in [grid.error, zones.error, lifecycle.error, frog.error, rewards.error, sounds.error]:
		if not issue.is_empty():
			return issue
	var entities: EntitySetup = EntitySetup.from_map(map, data.tables.theme_book(), source, book.map_id(false), data.version.internal_name, true)
	diagnostics.append_array(entities.diagnostics)
	if not entities.error.is_empty():
		return entities.error
	if entities.definitions.size() != map.entities.size():
		var messages := PackedStringArray()
		for diagnostic: EntitySetupDiagnostic in diagnostics:
			messages.append(diagnostic.to_text())
		return "Whole-map ORG1 requires every entity dependency: " + "; ".join(messages)
	var models: Dictionary[int, MofFile] = {}
	var problems := PackedStringArray()
	var identities: Dictionary[int, EntityDefinition] = {}
	for entity: EntityDefinition in entities.definitions:
		if identities.has(entity.unique_id):
			return "ORG1 entity unique ID %d is duplicated" % entity.unique_id
		identities[entity.unique_id] = entity
		var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, entity.form_id)
		if form == null:
			return "ORG1 entity %d has no form" % entity.entity_index
		if entity.bonus_kind == FormCallback.Kind.UNKNOWN:
			return "ORG1 entity %d at 0x%X has unknown bonus callback 0x%X" % [entity.entity_index, entity.source_offset, entity.bonus_callback]
		if form.model_id >= 0 and not models.has(entity.form_id):
			var model_id: int = data.model_resource_at(data.model_wad_for(form, number, false), form.wad_index())
			if model_id >= 0:
				models[entity.form_id] = data.read_model(model_id, problems)
		var model: MofFile = models.get(entity.form_id)
		if model != null and model.kind != MofFile.Kind.DUMMY and not form.has_flag(FormBookEntry.FLAG_NO_MODEL):
			if model.static_models.is_empty() or model.static_models[0].parts.is_empty():
				return "ORG1 entity %d lacks source model parts" % entity.entity_index
			for action: MofPart.FlipbookAction in model.static_models[0].parts[0].flipbook_actions:
				entity.action_lengths.append(action.frame_count)
		if entity.behavior.kind == EntityBehavior.Kind.PICKUP:
			entity.pickup_reward = rewards.definitions[EntityBonusFly.REWARD_IDS[entity.pickup_type]].copy()
		if entity.behavior.has_custom_update():
			entity.behavior.execution = EntityBehavior.Execution.CONTACT
		if entity.script_id != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(data.tables.scripts(), data.tables.names.scripts, entity.script_id, entity.behavior, map.entities[entity.entity_index].payload)
			if not scripts.error.is_empty():
				return "ORG1 entity %d: %s" % [entity.entity_index, scripts.error]
			entity.script_definition = scripts.definition
			var issue: String = entity.script_definition.validate(entity.action_lengths, entity.form_id, entity.path_definition != null)
			if not issue.is_empty():
				return "ORG1 entity %d: %s" % [entity.entity_index, issue]
	if not problems.is_empty():
		return "; ".join(problems)
	for entity: EntityDefinition in entities.definitions:
		if entity.behavior.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.LOG_SNAKE] and not identities.has(entity.parent_unique_id):
			return "ORG1 entity %d has an unresolved parent %d" % [entity.entity_index, entity.parent_unique_id]
	var contacts: FormContactSetup = FormContactSetup.from_map(map, data.tables.theme_book(), entities.definitions, models, source, book.map_id(false), data.version.internal_name, true)
	diagnostics.append_array(contacts.diagnostics)
	if not contacts.error.is_empty():
		return contacts.error
	var collision := EntityCollisionDefinition.new()
	collision.platforms_enabled = true
	collision.lifecycle = lifecycle.definition
	collision.frog_collision = frog.definition
	collision.group_base = map.group_base
	collision.group_dimensions = map.group_dimensions
	collision.group_size = map.group_size
	collision.entities = entities.definitions
	collision.contacts = contacts.definitions
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	var checkpoint_bits: int = 0
	var top: EntityDefinition = null
	var bottom: EntityDefinition = null
	for slot: int in collision.entities.size():
		var entity: EntityDefinition = collision.entities[slot]
		var contact: FormContactDefinition = collision.contacts[slot]
		contact.form_book_flags = entity.form_flags
		if not contact.unsupported_reason.is_empty():
			return "ORG1 entity %d at 0x%X: %s" % [entity.entity_index, entity.source_offset, contact.unsupported_reason]
		if entity.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			var index: int = entity.form_id & 32767
			if index >= 5 or checkpoint_bits & (1 << index):
				return "ORG1 requires five distinct single-player checkpoints"
			checkpoint_bits |= 1 << index
			collision.environment.checkpoint_positions[index] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		if entity.behavior.kind == EntityBehavior.Kind.BOUNDS_TOP_LEFT:
			if top != null:
				return "ORG1 has duplicate top-left bounds"
			top = entity
		if entity.behavior.kind == EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT:
			if bottom != null:
				return "ORG1 has duplicate bottom-right bounds"
			bottom = entity
	if checkpoint_bits != 31 or top == null or bottom == null:
		return "ORG1 requires five checkpoints and authored bounds"
	var issue: String = collision.validate()
	if not issue.is_empty():
		return issue
	definition = LevelDefinition.new()
	definition.grid = grid.definition
	definition.entity_collision = collision
	definition.camera_zones = zones.definitions
	definition.rewards = rewards.definitions
	definition.sounds = sounds.definitions
	definition.music_pitch_offset = sounds.music_pitches[number].x << 7
	definition.source_id = source
	definition.resource_id = book.map_id(false)
	definition.map_index = number
	definition.spawn_cell = map.general.start_grid
	definition.spawn_direction = map.general.start_rotation
	definition.theme = map.general.theme
	definition.theme_name = FroggerIds.animation_theme(definition.theme)
	definition.theme_death_height = theme.death_height
	definition.collision_enabled = true
	definition.collision_bounds = Rect2i(top.matrix12[9], bottom.matrix12[11], bottom.matrix12[9] - top.matrix12[9], top.matrix12[11] - bottom.matrix12[11])
	definition.camera = GameplayCameraDefinition.new()
	definition.camera.source_offset = map.general.camera_source_offset
	definition.camera.target_offset = map.general.camera_target_offset
	definition.frog_action_lengths = action_lengths.duplicate()
	definition.flow_enabled = true
	definition.level_time = map.general.time_limit * 30
	return ""
