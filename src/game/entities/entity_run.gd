class_name EntityRun
extends RefCounted
## Owns attached entity transforms and independent path cursors for one run.

var error: String = ""
var _definitions: Array[EntityDefinition] = []
var _runners: Array[PathRunner] = []
var _state: EntityRunSnapshot = null
var _ready: bool = false
var _lifecycle: EntityLifecycleDefinition = null

## Clones owned mutable state; private validated definitions are shared read-only.
func copy() -> EntityRun:
	var result := EntityRun.new()
	result.error = error
	result._ready = _ready
	result._lifecycle = _lifecycle
	result._definitions.assign(_definitions)
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
		if definition.background_admitted and lifecycle != null:
			result.error = "Custom background entities require all-attached lifetime"
			return result
		if definition.entity_name == "STATIC" or (definition.background_admitted and definition.entity_name in ["CHECKPOINT", "STATIC_NOISE", "GEN_TOP_LEFT", "GEN_BOTTOM_RIGHT", "ORG_BABY_FROG", "ORG_FLY"]):
			if definition.path_definition != null or definition.path_start != null:
				result.error = "Static entity %d cannot attach a path" % definition.entity_index
				return result
		elif definition.entity_name in ["MOVING", "SUB_TURTLE"]:
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
		for length: int in definition.action_lengths:
			if length <= 0:
				result.error = "Entity animation lengths must be positive"
				return result
		if definition.script_definition != null:
			if lifecycle != null:
				result.error = "Script entities require explicit all-attached lifetime"
				return result
			result.error = definition.script_definition.validate(definition.action_lengths, definition.form_id, definition.path_definition != null)
			if not result.error.is_empty():
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
		if definition.path_definition != null:
			var start: PathStart = definition.path_start.copy()
			start.flags |= PathStart.ACTIVE
			if definition.flags & EntityDefinition.NO_MOVEMENT:
				start.flags &= ~PathStart.ACTIVE
			runner = PathRunner.create(definition.path_definition, start)
			if not runner.error.is_empty():
				return "Entity %d: %s" % [definition.entity_index, runner.error]
		candidates.append(runner)
	var next_state: EntityRunSnapshot = _make_snapshot(candidates, 0)
	for index: int in next_state.entities.size():
		var definition: EntityDefinition = _definitions[index]
		next_state.entities[index].animation = EntityAnimationState.create(definition.action_lengths, definition.animation_one_shot)
		next_state.entities[index].live_flags = 4098 if not definition.action_lengths.is_empty() else 0
		if definition.script_definition != null:
			next_state.entities[index].script_state = EntityScriptState.create(definition.script_definition.root_id)
		if definition.background_admitted:
			var entity: EntitySnapshot = next_state.entities[index]
			entity.background = EntityBackgroundState.new()
			if definition.entity_name == "ORG_FLY":
				entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
				entity.background.model_hidden = true
			elif definition.entity_name == "ORG_BABY_FROG":
				entity.background.timer = 0
				entity.background.model_hidden = true
			elif definition.entity_name == "CHECKPOINT":
				entity.ambient = Vector3i(160, 160, 160)
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
	for index: int in next_state.entities.size():
		var previous: EntitySnapshot = _state.entities[index]
		next_state.entities[index].script_state = previous.script_state.copy() if previous.script_state != null else null
		next_state.entities[index].animation = previous.animation.copy() if previous.animation != null else null
		next_state.entities[index].entity_flags = previous.entity_flags
		next_state.entities[index].background = previous.background.copy() if previous.background != null else null
		next_state.entities[index].live_flags = previous.live_flags
		next_state.entities[index].colour_scale = previous.colour_scale
		next_state.entities[index].ambient = previous.ambient
		if _definitions[index].entity_name == "ORG_FLY":
			next_state.entities[index].matrix12 = previous.matrix12.duplicate()
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

## Updates one candidate entity; the caller applies frog effects before the next visit.
func update_script(entity_index: int, context: EntityUpdateContext, random: SourceRandom) -> EntityUpdateResult:
	var slot: int = _slot_for_id(entity_index)
	if slot < 0 or _state == null or _definitions[slot].script_definition == null:
		var failed := EntityUpdateResult.new()
		failed.error = "Entity has no script state"
		return failed
	var entity: EntitySnapshot = _state.entities[slot]
	var result: EntityUpdateResult = EntityScriptRunner.update(_definitions[slot].script_definition, entity.script_state, entity.animation, context, random)
	if result.error.is_empty():
		entity.script_state = result.script_state.copy()
		entity.animation = result.animation.copy()
		entity.matrix12 = result.matrix12.duplicate()
		entity.requests.assign(result.requests)
		entity.colour_scale = result.script_state.colours
		entity.ambient = result.script_state.ambient
		entity.live_flags = (entity.live_flags & ~65536) | (65536 if result.script_state.no_screen_fade else 0)
		if result.drown:
			entity.live_flags &= ~4
	return result

## Copies one current authored slot without cloning the aggregate.
func entity_snapshot(slot: int) -> EntitySnapshot:
	return _state.entities[slot].copy()

## Captures an ordered update, then applies UpdateLiveEntities' transient clear.
func finish_update(slot: int, previous_flags: int, random: SourceRandom, sounds: int, environment: EntityEnvironmentState, death_requested: bool, capture_observation: bool = true) -> void:
	if death_requested:
		_state.entities[slot].requests.append("death_pgen")
	if capture_observation:
		var observation := EntityUpdateObservation.new()
		observation.entity = _state.entities[slot].copy()
		observation.previous_flags = previous_flags
		observation.rng_state = random.state
		observation.sound_requests = sounds
		observation.environment = environment.copy() if environment != null else null
		_state.updates.append(observation)
	_state.entities[slot].live_flags &= ~25596

## Publishes this tick's frog contact flags for the following entity update.
func set_contact_flags(hits: PackedInt32Array, carries: PackedInt32Array) -> void:
	for entity: EntitySnapshot in _state.entities:
		entity.live_flags &= ~1020
		if hits.has(entity.entity_index):
			entity.live_flags |= 64
		if carries.has(entity.entity_index):
			entity.live_flags |= 4

## Advances authoritative entity clocks once at the aggregate pose phase.
func advance_animations() -> void:
	for entity: EntitySnapshot in _state.entities:
		if entity.animation != null:
			entity.animation.advance()

## Updates one admitted custom neighbor on detached candidate state.
func update_background(entity_index: int, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool) -> EntityBackgroundResult:
	var slot: int = _slot_for_id(entity_index)
	if slot < 0:
		var failed := EntityBackgroundResult.new()
		failed.error = "Unknown background entity"
		return failed
	var definition: EntityDefinition = _definitions[slot]
	var parent_live: bool = false
	if definition.entity_name == "ORG_BABY_FROG":
		for candidate: EntitySnapshot in _state.entities:
			if candidate.unique_id == definition.parent_unique_id:
				parent_live = candidate.live
				break
	var result: EntityBackgroundResult = EntityBackground.update(definition, _state.entities[slot], environment, random, frog_position, hit, parent_live)
	if result.error.is_empty():
		_state.entities[slot] = result.entity.copy()
	return result

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
		entity.entity_flags = definition.flags
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
