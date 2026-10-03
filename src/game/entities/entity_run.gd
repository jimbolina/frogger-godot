class_name EntityRun
extends RefCounted
## Owns attached entity transforms and independent path cursors for one run.

var error: String = ""
var _definitions: Array[EntityDefinition] = []
var _runners: Array[PathRunner] = []
var _state: EntityRunSnapshot = null
var _ready: bool = false
var _lifecycle: EntityLifecycleDefinition = null

## Clones definitions, path runners and the current detached aggregate state.
func copy() -> EntityRun:
	var result := EntityRun.new()
	result.error = error
	result._ready = _ready
	result._lifecycle = _lifecycle.copy() if _lifecycle != null else null
	for definition: EntityDefinition in _definitions:
		result._definitions.append(definition.copy() if definition != null else null)
	for runner: PathRunner in _runners:
		result._runners.append(runner.copy() if runner != null else null)
	result._state = _state.copy() if _state != null else null
	return result

## Validates and copies source-ordered definitions, then creates tick zero.
static func create(definitions: Array[EntityDefinition], lifecycle: EntityLifecycleDefinition = null) -> EntityRun:
	var result := EntityRun.new()
	if lifecycle != null:
		result.error = lifecycle.validate()
		if not result.error.is_empty():
			return result
		result._lifecycle = lifecycle.copy()
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
	if _lifecycle != null:
		next_state.lifecycle_enabled = true
		for entity: EntitySnapshot in next_state.entities:
			entity.lifecycle_supported = _definitions[_slot_for_id(entity.entity_index)].script_id == 0
			entity.live = false
	_runners = candidates
	_state = next_state
	return ""

## Advances all paths, then updates moving transforms, with aggregate rollback.
func step(tick_index: int, attached_entity_index: int = -1) -> String:
	if _state == null:
		return "Entity run has no valid start"
	if tick_index < 0 or tick_index != _state.tick_index:
		return "Entity ticks must be consecutive from zero"
	if attached_entity_index < -1:
		return "Current attached entity must be an authored identity or -1"
	if _lifecycle != null and attached_entity_index >= 0:
		var attached_slot: int = _slot_for_id(attached_entity_index)
		if attached_slot < 0 or not _state.entities[attached_slot].lifecycle_supported or not _state.entities[attached_slot].live:
			return "Current attached entity must be a supported live authored identity"
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
	if _lifecycle != null:
		next_state.lifecycle_enabled = true
		next_state.live_order = _state.live_order.duplicate()
		next_state.selected_groups = _state.selected_groups.duplicate()
		for index: int in next_state.entities.size():
			var current: EntitySnapshot = _state.entities[index]
			var entity: EntitySnapshot = next_state.entities[index]
			entity.lifecycle_supported = current.lifecycle_supported
			entity.live = current.live
			entity.destroy_pending = current.destroy_pending
			entity.generation = current.generation
		# The C live list is traversed from its head. A prior DESTROY flag is
		# checked before this tick's update; an attached frog pins that live object.
		var survivors := PackedInt32Array()
		for entity_id: int in next_state.live_order:
			var slot: int = _slot_for_id(entity_id)
			if slot < 0:
				return "Entity live-list identity is invalid"
			var entity: EntitySnapshot = next_state.entities[slot]
			if entity.destroy_pending and entity_id != attached_entity_index:
				entity.live = false
				entity.destroy_pending = false
				next_state.lifecycle_events.append("destroy:%d:%d" % [entity_id, entity.generation])
			else:
				entity.destroy_pending = true
				survivors.append(entity_id)
		next_state.live_order = survivors
	_runners = candidates
	_state = next_state
	return ""

## Returns a fully detached source-ordered run snapshot.
func snapshot() -> EntityRunSnapshot:
	return _state.copy() if _state != null else null

## Applies the post-camera source view list; new live objects first update next tick.
func apply_visibility(camera: GameplayCameraSnapshot) -> String:
	if _state == null or _lifecycle == null:
		return "Entity run has no lifecycle visibility"
	var selection: MapGroupVisibilityResult = MapGroupVisibility.query(_lifecycle, camera)
	if not selection.error.is_empty():
		return selection.error
	var next_state: EntityRunSnapshot = _state.copy()
	next_state.selected_groups = selection.groups.duplicate()
	for group_index: int in selection.groups:
		for pass_index: int in 2:
			for slot: int in range(_definitions.size() - 1, -1, -1):
				var definition: EntityDefinition = _definitions[slot]
				if (definition.entity_name == "MOVING") != (pass_index == 0):
					continue
				if _group_for(next_state.entities[slot].matrix12[9], next_state.entities[slot].matrix12[11]) != group_index:
					continue
				if definition.flags & EntityDefinition.HIDDEN:
					continue
				var entity: EntitySnapshot = next_state.entities[slot]
				if not entity.lifecycle_supported:
					continue
				if entity.live:
					entity.destroy_pending = false
				else:
					entity.live = true
					entity.destroy_pending = false
					entity.generation += 1
					next_state.live_order.insert(0, entity.entity_index)
					next_state.lifecycle_events.append("create:%d:%d" % [entity.entity_index, entity.generation])
	_state = next_state
	return ""

func _slot_for_id(entity_index: int) -> int:
	for slot: int in _definitions.size():
		if _definitions[slot].entity_index == entity_index:
			return slot
	return -1

func _group_for(x: int, z: int) -> int:
	var group_x: int = clampi(_source_div(_signed32(x - _lifecycle.group_base.x), _lifecycle.group_size.x), 0, _lifecycle.group_dimensions.x - 1)
	var group_z: int = clampi(_source_div(_signed32(z - _lifecycle.group_base.z), _lifecycle.group_size.y), 0, _lifecycle.group_dimensions.y - 1)
	return group_z * _lifecycle.group_dimensions.x + group_x

static func _source_div(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low

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
