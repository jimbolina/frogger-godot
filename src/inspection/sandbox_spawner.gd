class_name SandboxSpawner
extends RefCounted
## Places catalog entities on sandbox cells and rebuilds a valid entity table and run start.

enum Preset { STATIC, LINE, LOOP, SPEED }

const LINE_CELLS: int = 8
const LOOP_CELLS: int = 4
const DEFAULT_SPEED: int = 16
const SPEED_MULTIPLIER: int = 3
const PLATFORM_FORM_NAME: String = "SANDBOX_PLATFORM"
const PLATFORM_HEIGHT: int = -64
const PLATFORM_MAX_Y: int = 64
const PLATFORM_RADIUS_SQUARED: int = 2 * 256 * 256
const CHECKPOINT_COUNT: int = 5
const HALF_CELL: int = SandboxLevel.CELL_SIZE >> 1
const DATA_FREE_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.STATIC, EntityBehavior.Kind.PATH_FOLLOWER]
const UNSPAWNABLE_REASONS: Dictionary[EntityBehavior.Kind, String] = {
	EntityBehavior.Kind.BABY_FROG: "Pink frog requires a parent log and visibility lifecycle",
	EntityBehavior.Kind.LOG_SNAKE: "Log snake requires a parent log",
	EntityBehavior.Kind.BOUNDS_TOP_LEFT: "Level fade bounds markers are not spawnable",
	EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT: "Level fade bounds markers are not spawnable",
}

## Whether a FrogLord entity name can be spawned, and why not when it cannot.
class Availability extends RefCounted:
	var entity_name: String = ""
	var available: bool = false
	var reason: String = ""

## One spawned entity: its request, borrowed source and relocated definitions.
class Placement extends RefCounted:
	var unique_id: int = 0
	var entity_name: String = ""
	var form_name: String = ""
	var cell: Vector2i = Vector2i.ZERO
	var preset: Preset = Preset.STATIC
	var speed: int = 0
	## Source level code and theme of a data template; empty and -1 for data-free entities.
	var level_code: String = ""
	var theme: int = -1
	## Template height above (negative) its source ground, kept on the sandbox ground.
	var height_offset: int = 0
	var entity: EntityDefinition = null
	var contact: FormContactDefinition = null

## Outcome of one add request; `placement` is null when `error` is set.
class Result extends RefCounted:
	var error: String = ""
	var placement: Placement = null

var sandbox: SandboxLevel = null
var templates: SandboxEntityTemplates = null
var placements: Array[Placement] = []
var _next_unique_id: int = 1

## Spawns into `arena`; supplied `entity_templates` enable data-backed kinds.
func _init(arena: SandboxLevel, entity_templates: SandboxEntityTemplates = null) -> void:
	sandbox = arena
	templates = entity_templates if entity_templates != null and entity_templates.error.is_empty() else null

## Lists every FrogLord entity name the behavior catalog resolves, in catalog order.
static func kind_names() -> PackedStringArray:
	var result := PackedStringArray()
	for entity_name: String in EntityBehaviorCatalog.KINDS:
		result.append(entity_name)
	return result

## Reports whether `entity_name` can be spawned with the current data.
func availability(entity_name: String) -> Availability:
	var result := Availability.new()
	result.entity_name = entity_name
	var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(entity_name)
	if behavior.kind == EntityBehavior.Kind.UNKNOWN:
		result.reason = "Unknown FrogLord entity name %s" % entity_name
	elif UNSPAWNABLE_REASONS.has(behavior.kind):
		result.reason = UNSPAWNABLE_REASONS[behavior.kind]
	elif templates != null:
		if not templates.has_entity(entity_name):
			result.reason = "No supported level places %s" % entity_name
	elif behavior.kind not in DATA_FREE_KINDS:
		result.reason = "%s requires scripts, action lengths, forms or payload from player data" % entity_name
	result.available = result.reason.is_empty()
	return result

## Lists the names that can be spawned with the current data.
func available_names() -> PackedStringArray:
	var result := PackedStringArray()
	for entity_name: String in kind_names():
		if availability(entity_name).available:
			result.append(entity_name)
	return result

## Spawns `entity_name` at `cell` moving by `preset`; `speed` < 0 keeps the default.
func add(entity_name: String, cell: Vector2i, preset: Preset = Preset.STATIC, speed: int = -1, form_name: String = "") -> Result:
	var result := Result.new()
	var allowed: Availability = availability(entity_name)
	if not allowed.available:
		result.error = allowed.reason
		return result
	if sandbox == null or sandbox.flags_at(cell) < 0:
		result.error = "Cell %s is outside the sandbox" % cell
		return result
	var placement := Placement.new()
	placement.entity_name = entity_name
	placement.cell = cell
	placement.preset = preset
	if templates != null:
		result.error = _from_template(placement, form_name)
	else:
		_data_free(placement)
	if not result.error.is_empty():
		return result
	var authored_speed: int = placement.entity.path_start.speed if placement.entity.path_start != null else 0
	placement.speed = speed if speed >= 0 else (authored_speed if authored_speed > 0 else DEFAULT_SPEED) * (SPEED_MULTIPLIER if preset == Preset.SPEED else 1)
	result.error = _place(placement)
	if not result.error.is_empty():
		return result
	placement.unique_id = _next_unique_id
	placements.append(placement)
	var collision: EntityCollisionDefinition = entity_collision()
	result.error = collision.validate()
	if result.error.is_empty():
		result.error = EntityRun.create(collision.entities, collision.lifecycle).error
	if not result.error.is_empty():
		placements.pop_back()
		return result
	_next_unique_id += 1
	result.placement = placement
	return result

## Removes the placement with `unique_id`; returns whether one existed.
func remove(unique_id: int) -> bool:
	for index: int in placements.size():
		if placements[index].unique_id == unique_id:
			placements.remove_at(index)
			return true
	return false

## Removes every placement spawned at `cell`; returns how many were removed.
func remove_at(cell: Vector2i) -> int:
	var removed: int = 0
	for index: int in range(placements.size() - 1, -1, -1):
		if placements[index].cell == cell:
			placements.remove_at(index)
			removed += 1
	return removed

## Removes the most recent placement; returns whether one existed.
func remove_last() -> bool:
	if placements.is_empty():
		return false
	placements.pop_back()
	return true

## Removes every placement.
func clear() -> void:
	placements.clear()

## Rebuilds the arena's entity table with one ordered contact per placement.
func entity_collision() -> EntityCollisionDefinition:
	var collision: EntityCollisionDefinition = SandboxLevel.empty_entity_collision()
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(CHECKPOINT_COUNT)
	if templates != null:
		collision.frog_collision = templates.frog_collision.copy()
	for index: int in placements.size():
		var placement: Placement = placements[index]
		var entity: EntityDefinition = placement.entity.copy()
		var contact: FormContactDefinition = placement.contact.copy()
		entity.entity_index = index
		entity.unique_id = placement.unique_id
		if entity.path_definition != null:
			entity.path_definition.entity_indices = PackedInt32Array([index])
		contact.entity_index = index
		contact.unique_id = placement.unique_id
		collision.entities.append(entity)
		collision.contacts.append(contact)
		if entity.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			collision.environment.checkpoint_positions[entity.form_id & 32767] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	return collision

## Returns each placement's source theme and level in entity-table order, borrowing `data` for model lookup.
func model_origins(data: GameData) -> EntityModelOrigins:
	var origins := EntityModelOrigins.new(data)
	for placement: Placement in placements:
		origins.add(placement.theme, FroggerIds.level_from_code(placement.level_code) if not placement.level_code.is_empty() else -1)
	return origins

## Returns a fresh copy of the arena level carrying the rebuilt entities and any data-backed frog and rewards.
func level_definition() -> LevelDefinition:
	var level := LevelDefinition.new()
	for property: Dictionary in sandbox.level.get_property_list():
		var usage: int = property["usage"]
		if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var property_name: StringName = property["name"]
		var value: Variant = sandbox.level.get(property_name)
		if value is Array:
			var array: Array = value
			value = array.duplicate()
		elif value is PackedInt32Array:
			var packed: PackedInt32Array = value
			value = packed.duplicate()
		level.set(property_name, value)
	level.entity_collision = entity_collision()
	if templates != null:
		level.frog_action_lengths = templates.frog_action_lengths.duplicate()
		level.rewards.clear()
		for reward: RewardDefinition in templates.rewards:
			level.rewards.append(reward.copy())
		level.sounds.clear()
		for sound: LogicalSoundDefinition in templates.sounds:
			level.sounds.append(sound.copy())
	for entity: EntityDefinition in level.entity_collision.entities:
		level.cave_light = level.cave_light or entity.behavior.kind == EntityBehavior.Kind.CAVE_LIGHT
	return level

## Returns a stationary component start that keeps the frog on `cell` facing `direction`.
static func run_start(cell: Vector2i, direction: int) -> RunStart:
	var start := RunStart.new()
	start.start_mode = RunStart.Mode.COMPONENT
	start.spawn_cell = cell
	start.spawn_direction = direction
	return start

## Returns a component start that keeps the committed frog's cell and direction.
static func run_start_from(state: GameplayState) -> RunStart:
	return run_start(state.frog.cell, state.frog.direction)

## Returns the world centre of `cell` with its terrain height.
func cell_centre(cell: Vector2i) -> Vector3i:
	var x: int = SandboxLevel.BASE.x + cell.x * SandboxLevel.CELL_SIZE + HALF_CELL
	var z: int = SandboxLevel.BASE.y + cell.y * SandboxLevel.CELL_SIZE + HALF_CELL
	var info: GridSurfaceInfo = GridQueries.info_at(sandbox.level.grid, x, z)
	return Vector3i(x, info.height if info != null else 0, z)

func _from_template(placement: Placement, form_name: String) -> String:
	var candidates: Array[SandboxEntityTemplates.Template] = templates.templates_for(placement.entity_name, form_name)
	if candidates.is_empty():
		var code: String = templates.level_for(placement.entity_name, form_name)
		if code.is_empty():
			return "No supported level places %s %s" % [placement.entity_name, form_name]
		return "%s template from %s is unavailable: %s" % [placement.entity_name, code, templates.level_errors.get(code, "no matching entity")]
	var chosen: SandboxEntityTemplates.Template = candidates[0]
	var behavior_kind: EntityBehavior.Kind = chosen.entity.behavior.kind
	if behavior_kind == EntityBehavior.Kind.CHECKPOINT:
		var used: int = _checkpoint_bits()
		chosen = null
		for candidate: SandboxEntityTemplates.Template in candidates:
			var index: int = candidate.entity.form_id & 32767
			if index < CHECKPOINT_COUNT and not used & (1 << index):
				chosen = candidate
				break
		if chosen == null:
			return "Every checkpoint form is already placed"
	if behavior_kind == EntityBehavior.Kind.CAVE_LIGHT:
		for other: Placement in placements:
			if other.entity.behavior.kind == EntityBehavior.Kind.CAVE_LIGHT:
				return "Only one frogger light can be placed"
	placement.entity = chosen.entity.copy()
	placement.contact = chosen.contact.copy()
	placement.form_name = placement.entity.form_name
	placement.level_code = chosen.level_code
	placement.theme = chosen.theme
	placement.entity.flags &= ~EntityDefinition.NO_MOVEMENT
	if placement.entity.volcano != null:
		for target: int in placement.entity.volcano.target_ids.size():
			placement.entity.volcano.target_ids[target] = -1
	placement.height_offset = chosen.height_offset
	return ""

func _data_free(placement: Placement) -> void:
	var entity := EntityDefinition.new()
	entity.entity_name = placement.entity_name
	entity.behavior = EntityBehaviorCatalog.resolve(placement.entity_name)
	entity.form_name = PLATFORM_FORM_NAME
	entity.source_id = SandboxLevel.SOURCE_ID
	var contact := FormContactDefinition.new()
	contact.source_id = SandboxLevel.SOURCE_ID
	contact.form_name = PLATFORM_FORM_NAME
	contact.dimensions = Vector2i.ONE
	contact.offsets = Vector2i(-HALF_CELL, -HALF_CELL)
	contact.height = PLATFORM_HEIGHT
	contact.max_y = PLATFORM_MAX_Y
	contact.radius_squared = PLATFORM_RADIUS_SQUARED
	contact.grid_flags = PackedInt32Array([GridSquareFlags.USABLE | GridSquareFlags.SAFE])
	placement.entity = entity
	placement.contact = contact
	placement.form_name = PLATFORM_FORM_NAME

func _place(placement: Placement) -> String:
	var entity: EntityDefinition = placement.entity
	var centre: Vector3i = cell_centre(placement.cell) + Vector3i(0, placement.height_offset, 0)
	entity.source_id = SandboxLevel.SOURCE_ID
	entity.resource_id = -1
	entity.source_offset = 0
	if entity.behavior.layout == EntityBehavior.Layout.PATH:
		entity.path_definition = _path(placement.cell, centre, placement.preset)
		if placement.preset == Preset.STATIC:
			placement.speed = 0
		entity.path_start = PathStart.new()
		entity.path_start.speed = placement.speed
		entity.path_start.flags = PathStart.ACTIVE | PathStart.REPEAT
	elif placement.preset != Preset.STATIC:
		return "%s has a fixed matrix layout and cannot follow a path" % placement.entity_name
	else:
		placement.speed = 0
		entity.path_definition = null
		entity.path_start = null
		var authored := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		var shift := Vector3i(centre.x - authored.x, 0, centre.z - authored.z)
		entity.matrix12[9] = centre.x
		entity.matrix12[10] = centre.y
		entity.matrix12[11] = centre.z
		if entity.behavior.kind == EntityBehavior.Kind.DES_FALLING_ROCK and entity.desert != null:
			var issue: String = _anchor_rock_targets(entity.desert, shift)
			if not issue.is_empty():
				return issue
		if entity.swamp != null:
			_anchor_swamp_targets(entity, authored, centre)
	var contact: FormContactDefinition = placement.contact
	contact.source_id = entity.source_id
	contact.build_id = entity.build_id
	contact.resource_id = entity.resource_id
	contact.source_offset = entity.source_offset
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.form_name = entity.form_name
	contact.entity_flags = entity.flags
	return ""

## Keeps a borrowed squirt's authored drop height above the arena floor and moves a rat's four
## targets with its start target, so the relocated behaviors cover the same relative ground.
func _anchor_swamp_targets(entity: EntityDefinition, authored: Vector3i, centre: Vector3i) -> void:
	var swamp: EntitySwampDefinition = entity.swamp
	if entity.behavior.kind == EntityBehavior.Kind.SWP_SQUIRT:
		entity.matrix12[10] = centre.y - maxi(0, swamp.target.y - authored.y)
		swamp.target = centre
	elif entity.behavior.kind == EntityBehavior.Kind.SWP_RAT and swamp.rat_targets.size() == 4:
		var rat_shift: Vector3i = centre - swamp.rat_targets[0]
		for index: int in swamp.rat_targets.size():
			swamp.rat_targets[index] += rat_shift

## Moves a borrowed rock's landing targets with the rock and snaps them to the arena floor.
func _anchor_rock_targets(desert: EntityDesertDefinition, shift: Vector3i) -> String:
	var authored: Array[Vector3i] = []
	for target: Vector3i in desert.rock_targets:
		authored.append(target + shift)
	var resolved: EntityDesertRockTargets = EntityDesertRockTargets.resolve(authored, sandbox.level.grid, desert.rock_bounces)
	if not resolved.error.is_empty():
		return "Falling rock targets leave the arena: " + resolved.error
	desert.rock_targets = resolved.targets
	desert.rock_targets_resolved = true
	return ""

func _path(cell: Vector2i, centre: Vector3i, preset: Preset) -> PathDefinition:
	var path := PathDefinition.new()
	path.source_id = SandboxLevel.SOURCE_ID
	var x_step: int = 1 if cell.x + LINE_CELLS < SandboxLevel.DIMENSIONS.x else -1
	var corners: Array[Vector3i] = [centre]
	if preset == Preset.LOOP:
		var loop_x: int = 1 if cell.x + LOOP_CELLS < SandboxLevel.DIMENSIONS.x else -1
		var loop_z: int = 1 if cell.y + LOOP_CELLS < SandboxLevel.DIMENSIONS.y else -1
		var side: int = LOOP_CELLS * SandboxLevel.CELL_SIZE
		corners.append(centre + Vector3i(loop_x * side, 0, 0))
		corners.append(centre + Vector3i(loop_x * side, 0, loop_z * side))
		corners.append(centre + Vector3i(0, 0, loop_z * side))
		corners.append(centre)
	elif preset == Preset.STATIC:
		corners.append(centre + Vector3i(x_step, 0, 0))
	else:
		corners.append(centre + Vector3i(x_step * LINE_CELLS * SandboxLevel.CELL_SIZE, 0, 0))
	for index: int in corners.size() - 1:
		var segment := PathSegmentDefinition.new()
		segment.segment_type = PathSegmentDefinition.LINE
		segment.start = corners[index]
		segment.end = corners[index + 1]
		segment.length = absi(segment.end.x - segment.start.x) + absi(segment.end.z - segment.start.z)
		path.segments.append(segment)
	return path

func _checkpoint_bits() -> int:
	var bits: int = 0
	for placement: Placement in placements:
		if placement.entity.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			bits |= 1 << (placement.entity.form_id & 32767)
	return bits
