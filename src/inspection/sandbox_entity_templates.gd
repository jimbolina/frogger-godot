class_name SandboxEntityTemplates
extends RefCounted
## Borrows fully resolved entities from supported player levels as sandbox spawn templates.

## One resolved entity and contact pair copied from a supported level's whole-map setup.
class Template extends RefCounted:
	var entity: EntityDefinition = null
	var contact: FormContactDefinition = null
	var level_code: String = ""
	var theme: int = 0
	## Authored height above (negative) or below the template's own ground.
	var height_offset: int = 0

var error: String = ""
## Levels whose whole-map setup failed, keyed by level code.
var level_errors: Dictionary[String, String] = {}
var rewards: Array[RewardDefinition] = []
var frog_collision: FrogCollisionDefinition = null
var frog_action_lengths: PackedInt32Array = PackedInt32Array()
## Logical sound definitions of every sound bank the executable lists, so placed entities from any theme can play.
var sounds: Array[LogicalSoundDefinition] = []
## Which listed sound banks failed to load, or "".
var sound_error: String = ""
var _data: AssetCatalog = null
var _frog_model: MofFile = null
var _forms: Dictionary[String, Dictionary] = {}
var _setups: Dictionary[String, LevelDefinition] = {}

## Indexes placed forms in every supported level, borrowing `data` until the caller closes it.
static func from_data(data: AssetCatalog, frog_model: MofFile, action_lengths: PackedInt32Array) -> SandboxEntityTemplates:
	var result := SandboxEntityTemplates.new()
	result.error = result._index(data, frog_model, action_lengths)
	return result

## Whether some supported level places `entity_name`, optionally with `form_name`.
func has_entity(entity_name: String, form_name: String = "") -> bool:
	return not level_for(entity_name, form_name).is_empty()

## Lists the placed form names for `entity_name` in supported-level order.
func form_names(entity_name: String) -> PackedStringArray:
	var result := PackedStringArray()
	var forms: Dictionary = _forms.get(entity_name, {})
	for form_name: String in forms:
		result.append(form_name)
	return result

## Returns distinct-form templates from the first level placing the selection, or an empty list.
func templates_for(entity_name: String, form_name: String = "") -> Array[Template]:
	var result: Array[Template] = []
	var code: String = level_for(entity_name, form_name)
	if code.is_empty():
		return result
	var level: LevelDefinition = _setup(code)
	if level == null:
		return result
	var seen: Dictionary[int, bool] = {}
	var collision: EntityCollisionDefinition = level.entity_collision
	for slot: int in collision.entities.size():
		var entity: EntityDefinition = collision.entities[slot]
		if entity.entity_name != entity_name or (not form_name.is_empty() and entity.form_name != form_name) or seen.has(entity.form_id):
			continue
		seen[entity.form_id] = true
		var template := Template.new()
		template.entity = entity.copy()
		template.contact = collision.contacts[slot].copy()
		template.level_code = code
		template.theme = level.theme
		template.height_offset = _height_offset(level.grid, entity)
		result.append(template)
	return result

func _index(data: AssetCatalog, frog_model: MofFile, action_lengths: PackedInt32Array) -> String:
	if data == null or not data.is_valid() or frog_model == null:
		return "Sandbox templates require valid player data and the frog model"
	if data.version.internal_name != "pc-retail-v3.0e":
		return "Sandbox templates require the verified pc-retail-v3.0e build"
	var rewards_setup: RewardSetup = RewardSetup.from_table(data.tables.scores())
	if not rewards_setup.error.is_empty():
		return rewards_setup.error
	var frog: FrogCollisionSetup = FrogCollisionSetup.from_model(frog_model)
	if not frog.error.is_empty():
		return frog.error
	_data = data
	_frog_model = frog_model
	rewards = rewards_setup.definitions
	frog_collision = frog.definition
	frog_action_lengths = action_lengths.duplicate()
	_load_sounds(data)
	for code: String in GameplaySetup.LEVEL_CODES:
		var map: MapFile = _read_map(code)
		if map == null:
			continue
		for span: MapEntitySpan in map.entities:
			var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, span.form_id)
			if form == null:
				continue
			if not _forms.has(form.entity_name):
				_forms[form.entity_name] = {}
			var forms: Dictionary = _forms[form.entity_name]
			if not forms.has(form.form_name):
				forms[form.form_name] = code
	return ""

## Returns the first supported level code placing the selection, or "" when none does.
func level_for(entity_name: String, form_name: String = "") -> String:
	var forms: Dictionary = _forms.get(entity_name, {})
	if not form_name.is_empty():
		return str(forms.get(form_name, ""))
	for code: String in GameplaySetup.LEVEL_CODES:
		if forms.values().has(code):
			return code
	return ""

func _read_map(code: String) -> MapFile:
	var book: MapBookEntry = _data.map_book_entry(FroggerIds.level_from_code(code))
	if book == null or book.map_id(false) <= 0:
		level_errors[code] = "Level has no high-detail map"
		return null
	var problems := PackedStringArray()
	var map: MapFile = _data.read_map(book.map_id(false), problems)
	if map == null:
		level_errors[code] = "Cannot read map: " + "; ".join(problems)
	return map

func _setup(code: String) -> LevelDefinition:
	if _setups.has(code):
		return _setups[code]
	if level_errors.has(code):
		return null
	var map: MapFile = _read_map(code)
	if map == null:
		return null
	var setup: GameplaySetup = GameplaySetup.from_data(_data, FroggerIds.level_from_code(code), map, _frog_model, frog_action_lengths)
	if not setup.error.is_empty():
		level_errors[code] = setup.error
		return null
	_setups[code] = setup.definition
	return setup.definition

static func _height_offset(grid: GridDefinition, entity: EntityDefinition) -> int:
	var position := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	if entity.path_definition != null and entity.path_start != null:
		var segment: PathSegmentDefinition = entity.path_definition.segments[entity.path_start.segment_index]
		var sample: PathSample = PathEvaluator.sample(segment, entity.path_start.distance)
		if not sample.error.is_empty():
			return 0
		position = sample.position
	var info: GridSurfaceInfo = GridQueries.info_at(grid, position.x, position.z)
	return position.y - info.height if info != null else 0

func _load_sounds(data: AssetCatalog) -> void:
	var tables: SoundTables = data.tables.sound_tables()
	if not tables.error.is_empty():
		sound_error = tables.error
		return
	var problems := PackedStringArray()
	for bank_id: int in tables.banks.size():
		if tables.banks[bank_id].x < 0 or tables.banks[bank_id].y < 0:
			continue
		var setup: LogicalSoundSetup = LogicalSoundSetup.from_data(data, PackedInt32Array([bank_id]))
		if setup.error.is_empty():
			sounds.append_array(setup.definitions)
		else:
			problems.append("bank %d: %s" % [bank_id, setup.error])
	sound_error = "; ".join(problems)
