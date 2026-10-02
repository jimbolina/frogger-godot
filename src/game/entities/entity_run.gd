class_name EntityRun
extends RefCounted
## Owns attached entity transforms and independent path cursors for one run.

var error: String = ""
var _definitions: Array[EntityDefinition] = []
var _runners: Array[PathRunner] = []
var _state: EntityRunSnapshot = null
var _ready: bool = false

## Validates and copies source-ordered definitions, then creates tick zero.
static func create(definitions: Array[EntityDefinition]) -> EntityRun:
	var result := EntityRun.new()
	var copies: Array[EntityDefinition] = []
	var previous_entity_index: int = -1
	for index: int in definitions.size():
		var definition: EntityDefinition = definitions[index]
		if definition == null:
			result.error = "Entity %d is null" % index
			return result
		if definition.entity_index <= previous_entity_index:
			result.error = "Entity index %d is not strictly increasing" % definition.entity_index
			return result
		previous_entity_index = definition.entity_index
		if definition.matrix12.size() != 12:
			result.error = "Entity %d matrix requires 12 values" % definition.entity_index
			return result
		if definition.flags & ~EntityDefinition.ALL_FLAGS:
			result.error = "Entity %d has unsupported flags" % definition.entity_index
			return result
		if definition.flags & (EntityDefinition.LOCAL_ALIGN | EntityDefinition.PROJECT_ON_LAND):
			result.error = "Entity %d requires unsupported alignment or land projection" % definition.entity_index
			return result
		if definition.entity_name == "STATIC":
			if definition.path_definition != null or definition.path_start != null:
				result.error = "Static entity %d cannot attach a path" % definition.entity_index
				return result
		elif definition.entity_name == "MOVING":
			if definition.path_definition == null or definition.path_start == null:
				result.error = "Moving entity %d requires a path and start" % definition.entity_index
				return result
			var path_issue: String = PathRunner.validate_definition(definition.path_definition)
			if not path_issue.is_empty():
				result.error = "Entity %d: %s" % [definition.entity_index, path_issue]
				return result
		else:
			result.error = "Entity %d has unsupported name %s" % [definition.entity_index, definition.entity_name]
			return result
		copies.append(definition.copy())
	result._definitions = copies
	result._ready = true
	result.error = result.reset()
	if not result.error.is_empty():
		result._ready = false
		result._definitions.clear()
	return result

## Recreates all path cursors and transforms atomically at tick zero.
func reset() -> String:
	if not _ready:
		return "Entity run has no validated definitions"
	var candidates: Array[PathRunner] = []
	for index: int in _definitions.size():
		var definition: EntityDefinition = _definitions[index]
		var runner: PathRunner = null
		if definition.entity_name == "MOVING":
			var start: PathStart = definition.path_start.copy()
			start.flags |= PathStart.ACTIVE
			if definition.flags & EntityDefinition.NO_MOVEMENT:
				start.flags &= ~PathStart.ACTIVE
			runner = PathRunner.create(definition.path_definition, start)
			if not runner.error.is_empty():
				return "Entity %d: %s" % [definition.entity_index, runner.error]
		candidates.append(runner)
	var next_state: EntityRunSnapshot = _make_snapshot(candidates, 0)
	_runners = candidates
	_state = next_state
	return ""

## Advances all paths, then updates moving transforms, with aggregate rollback.
func step(tick_index: int) -> String:
	if _state == null:
		return "Entity run has no valid start"
	if tick_index < 0 or tick_index != _state.tick_index:
		return "Entity ticks must be consecutive from zero"
	var candidates: Array[PathRunner] = []
	for runner: PathRunner in _runners:
		candidates.append(runner.copy() if runner != null else null)
	for index: int in range(candidates.size() - 1, -1, -1):
		var runner: PathRunner = candidates[index]
		if runner == null:
			continue
		var issue: String = runner.step(tick_index)
		if not issue.is_empty():
			return "Entity %d: %s" % [_definitions[index].entity_index, issue]
	var next_state: EntityRunSnapshot = _make_snapshot(candidates, tick_index + 1)
	_runners = candidates
	_state = next_state
	return ""

## Returns a fully detached source-ordered run snapshot.
func snapshot() -> EntityRunSnapshot:
	return _state.copy() if _state != null else null

func _make_snapshot(runners: Array[PathRunner], tick_index: int) -> EntityRunSnapshot:
	var result := EntityRunSnapshot.new()
	result.tick_index = tick_index
	for index: int in _definitions.size():
		var definition: EntityDefinition = _definitions[index]
		var entity := EntitySnapshot.new()
		entity.entity_index = definition.entity_index
		entity.unique_id = definition.unique_id
		entity.matrix12 = definition.matrix12.duplicate()
		result.entities.append(entity)
	for index: int in range(_definitions.size() - 1, -1, -1):
		var runner: PathRunner = runners[index]
		if runner == null:
			continue
		var entity: EntitySnapshot = result.entities[index]
		entity.path = runner.snapshot()
		entity.matrix12 = EntityTransform.moving(entity.path, _definitions[index].flags)
	return result
