class_name GameplaySetup
extends RefCounted
## Whole-map single-player dependency validation using supplied executable tables.

const LEVEL_CODES: PackedStringArray = ["ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "SUB1", "FOR1", "FOR2"]

var error: String = ""
var definition: LevelDefinition = null
var diagnostics: Array[EntitySetupDiagnostic] = []

## Whether the selected level has complete single-player dependency support.
static func supports_level(level_number: int) -> bool:
	return FroggerIds.level_code(level_number) in LEVEL_CODES

## Resolves player tables, scripts, callbacks, geometry and visibility once at setup.
static func from_data(data: GameData, level_number: int, map: MapFile, frog_model: MofFile, action_lengths: PackedInt32Array) -> GameplaySetup:
	var result := GameplaySetup.new()
	result.error = result._build(data, level_number, map, frog_model, action_lengths)
	if not result.error.is_empty():
		result.definition = null
	return result

func _build(data: GameData, number: int, map: MapFile, frog_model: MofFile, action_lengths: PackedInt32Array) -> String:
	if not supports_level(number):
		return "Gameplay setup requires ORG1–ORG5, SUB1 or FOR1–FOR2"
	if data == null or not data.is_valid() or map == null or frog_model == null:
		return "Gameplay setup requires valid player data, map and frog model"
	var code: String = FroggerIds.level_code(number)
	if data.version.internal_name != "pc-retail-v3.0e":
		return "Gameplay requires the verified pc-retail-v3.0e build"
	var book: MapBookEntry = data.map_book_entry(number)
	var theme: ThemeBookEntry = data.theme_book_entry(map.general.theme)
	if book == null or theme == null:
		return "Gameplay requires map and theme definitions"
	var source: String = data.version.internal_name + ":" + code
	var grid: TerrainGridSetup = TerrainGridSetup.from_map(map)
	var zones: ZoneSetup = ZoneSetup.from_map(map, source, book.map_id(false), data.version.internal_name)
	var lifecycle: EntityLifecycleSetup = EntityLifecycleSetup.from_map(map)
	var frog: FrogCollisionSetup = FrogCollisionSetup.from_model(frog_model)
	var rewards: RewardSetup = RewardSetup.from_table(data.tables.scores())
	var sounds: LogicalSoundSetup = LogicalSoundSetup.from_data(data, PackedInt32Array([FroggerIds.THEME_GENERAL, map.general.theme]))
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
		return "Whole-map " + code + " requires every entity dependency: " + "; ".join(messages)
	var models: Dictionary[int, MofFile] = {}
	var problems := PackedStringArray()
	var identities: Dictionary[int, EntityDefinition] = {}
	var needs_swarm: bool = false
	for entity: EntityDefinition in entities.definitions:
		if identities.has(entity.unique_id):
			return code + " entity unique ID %d is duplicated" % entity.unique_id
		identities[entity.unique_id] = entity
		needs_swarm = needs_swarm or entity.behavior.kind == EntityBehavior.Kind.HIVE
		var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, entity.form_id)
		if form == null:
			return code + " entity %d has no form" % entity.entity_index
		if entity.bonus_kind == FormCallback.Kind.UNKNOWN:
			return code + " entity %d at 0x%X has unknown bonus callback 0x%X" % [entity.entity_index, entity.source_offset, entity.bonus_callback]
		if form.model_id >= 0 and not models.has(entity.form_id):
			var model_id: int = data.model_resource_at(data.model_wad_for(form, number, false), form.wad_index())
			if model_id >= 0:
				models[entity.form_id] = data.read_model(model_id, problems)
		var model: MofFile = models.get(entity.form_id)
		if model != null and model.kind != MofFile.Kind.DUMMY and not form.has_flag(FormBookEntry.FLAG_NO_MODEL):
			if model.static_models.is_empty() or model.static_models[0].parts.is_empty():
				return code + " entity %d lacks source model parts" % entity.entity_index
			entity.action_lengths = model_action_lengths(model)
		if entity.behavior.kind == EntityBehavior.Kind.PICKUP:
			entity.pickup_reward = rewards.definitions[EntityBonusFly.REWARD_IDS[entity.pickup_type]].copy()
		if entity.bonus_kind == FormCallback.Kind.BUTTERFLY_SCORE or FormCallbackCatalog.resolve(data.version.internal_name, entity.collision_callback) == FormCallback.Kind.BUTTERFLY_SCORE:
			if entity.butterfly_type < 0 or entity.butterfly_type >= EntityBonusFly.REWARD_IDS.size():
				return code + " entity %d has no valid butterfly reward type" % entity.entity_index
			entity.butterfly_reward = rewards.definitions[EntityBonusFly.REWARD_IDS[entity.butterfly_type]].copy()
		if entity.behavior.has_custom_update():
			entity.behavior.execution = EntityBehavior.Execution.CONTACT
		if entity.script_id != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(data.tables.scripts(), data.tables.names.scripts, entity.script_id, entity.behavior, map.entities[entity.entity_index].payload)
			if not scripts.error.is_empty():
				return code + " entity %d: %s" % [entity.entity_index, scripts.error]
			entity.script_definition = scripts.definition
			entity.script_definition.original_turtle_splashes = map.general.theme == FroggerIds.THEMES.find("ORIGINAL")
			var issue: String = entity.script_definition.validate(entity.action_lengths, entity.form_id, entity.path_definition != null)
			if not issue.is_empty():
				return code + " entity %d: %s" % [entity.entity_index, issue]
	if not problems.is_empty():
		return "; ".join(problems)
	if needs_swarm:
		var swarm_issue: String = _swarm_texture_issue(data, theme)
		if not swarm_issue.is_empty():
			return code + ": " + swarm_issue
	for entity: EntityDefinition in entities.definitions:
		if entity.behavior.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.LOG_SNAKE] and not identities.has(entity.parent_unique_id):
			return code + " entity %d has an unresolved parent %d" % [entity.entity_index, entity.parent_unique_id]
	var contacts: FormContactSetup = FormContactSetup.from_map(map, data.tables.theme_book(), entities.definitions, models, source, book.map_id(false), data.version.internal_name, true, true)
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
			return code + " entity %d at 0x%X: %s" % [entity.entity_index, entity.source_offset, contact.unsupported_reason]
		if entity.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			var index: int = entity.form_id & 32767
			if index >= 5 or checkpoint_bits & (1 << index):
				return code + " requires five distinct single-player checkpoints"
			checkpoint_bits |= 1 << index
			collision.environment.checkpoint_positions[index] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		if entity.behavior.kind == EntityBehavior.Kind.BOUNDS_TOP_LEFT:
			if top != null:
				return code + " has duplicate top-left bounds"
			top = entity
		if entity.behavior.kind == EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT:
			if bottom != null:
				return code + " has duplicate bottom-right bounds"
			bottom = entity
	if checkpoint_bits != 31:
		return code + " requires five distinct single-player checkpoints"
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
	definition.collision_bounds = bounds_for(top, bottom)
	definition.camera = GameplayCameraDefinition.new()
	definition.camera.source_offset = map.general.camera_source_offset
	definition.camera.target_offset = map.general.camera_target_offset
	definition.frog_action_lengths = action_lengths.duplicate()
	definition.flow_enabled = true
	definition.level_time = map.general.time_limit * 30
	return ""

## Applies authored fade markers independently to the native map-load defaults.
static func bounds_for(top: EntityDefinition, bottom: EntityDefinition) -> Rect2i:
	var top_left := Vector2i(-32767, 32767)
	var bottom_right := Vector2i(32767, -32767)
	if top != null:
		top_left = Vector2i(top.matrix12[9], top.matrix12[11])
	if bottom != null:
		bottom_right = Vector2i(bottom.matrix12[9], bottom.matrix12[11])
	return Rect2i(top_left.x, bottom_right.y, bottom_right.x - top_left.x, top_left.y - bottom_right.y)

## Reads source virtual-action lengths for skeletal and flipbook entities.
static func model_action_lengths(model: MofFile) -> PackedInt32Array:
	var lengths := PackedInt32Array()
	if model == null or not model.error.is_empty():
		return lengths
	if model.kind == MofFile.Kind.ANIMATED and model.animated != null:
		for action: MofAnimated.Action in model.animated.actions_for(0):
			lengths.append(action.frame_count if action.error.is_empty() else 0)
	elif model.kind == MofFile.Kind.STATIC and not model.static_models.is_empty() and not model.static_models[0].parts.is_empty():
		for action: MofPart.FlipbookAction in model.static_models[0].parts[0].flipbook_actions:
			lengths.append(action.frame_count)
	return lengths

static func _swarm_texture_issue(data: GameData, theme: ThemeBookEntry) -> String:
	if data.tables.names.images == null:
		return "Hive swarm requires named player textures"
	var texture_id: int = data.tables.names.images.index_of("for_swarm")
	if texture_id < 0:
		return "Hive swarm image for_swarm is not named in the supplied configuration"
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	var found: bool = false
	var problems := PackedStringArray()
	for bank_theme: ThemeBookEntry in [general, theme]:
		if bank_theme == null:
			return "Hive swarm requires general and theme texture banks"
		var bank: VloFile = data.read_texture_bank(bank_theme.vlo_id(false, false), problems)
		if bank == null:
			return "Hive swarm texture bank is unavailable: " + "; ".join(problems)
		found = found or bank.find_texture(texture_id) != null
	return "" if found else "Hive swarm image for_swarm is missing from the supplied banks"
