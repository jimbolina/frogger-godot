class_name EntityRun
extends RefCounted
## Owns attached entity transforms and independent path cursors for one run.

var error: String = ""
var _definitions: Array[EntityDefinition] = []
var _scripts: Array[PreparedEntityScript] = []
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
	result._scripts.assign(_scripts)
	for runner: PathRunner in _runners:
		result._runners.append(runner.copy() if runner != null else null)
	result._state = _state.copy() if _state != null else null
	return result

## Builds the next independent tick directly, avoiding a redundant pre-step deep copy.
func begin_candidate(tick_index: int, attached_entity_index: int = -1, deferred_updates: bool = false) -> EntityRun:
	var result := EntityRun.new()
	result._ready = _ready
	result._lifecycle = _lifecycle
	result._definitions.assign(_definitions)
	result._scripts.assign(_scripts)
	result._runners.assign(_runners)
	result._state = _state
	result.error = result.step(tick_index, attached_entity_index, deferred_updates)
	if not result.error.is_empty():
		result._runners.clear()
		result._state = null
	return result

## Adopts a successful private candidate after every aggregate phase has succeeded.
## The candidate is consumed and must not be used again.
func commit_candidate(candidate: EntityRun) -> void:
	assert(candidate != null and candidate != self and candidate.error.is_empty() and candidate._state != null)
	_definitions = candidate._definitions
	_scripts = candidate._scripts
	_runners = candidate._runners
	_state = candidate._state
	_lifecycle = candidate._lifecycle
	_ready = candidate._ready
	candidate._definitions = []
	candidate._scripts = []
	candidate._runners = []
	candidate._state = null
	candidate._ready = false

## Updates a private candidate script without exposing its mutable entity state.
func update_candidate_script(slot: int, context: EntityUpdateContext, random: SourceRandom) -> EntityUpdateResult:
	return _update_script(slot, context, random, true)

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
		if lifecycle != null and definition.is_immortal() and definition.script_id != 0 and definition.script_definition == null:
			result.error = "Immortal scripted entity requires a validated program"
			return result
		if definition.script_definition != null:
			result.error = definition.script_definition.validate(definition.action_lengths, definition.form_id, definition.path_definition != null)
			if not result.error.is_empty():
				return result
		copies.append(definition.copy())
	result._definitions = copies
	for definition: EntityDefinition in copies:
		result._scripts.append(PreparedEntityScript.create(definition.script_definition, definition.action_lengths, definition.form_id, definition.path_definition != null) if definition.script_definition != null else null)
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
		var entity: EntitySnapshot = next_state.entities[index]
		entity.lifecycle_supported = definition.script_id == 0 or definition.script_definition != null
		if _lifecycle == null or definition.is_immortal():
			_initialize_instance(entity, definition)
			if _lifecycle != null:
				entity.generation = 1
				next_state.live_order.insert(0, entity.entity_index)
		else:
			entity.live = false
	if _lifecycle != null:
		next_state.lifecycle_enabled = true
	_runners = candidates
	_state = next_state
	return ""

## Advances all paths, then updates moving transforms, with aggregate rollback.
func step(tick_index: int, attached_entity_index: int = -1, deferred_updates: bool = false) -> String:
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
		candidates.append(runner)
	for index: int in range(candidates.size() - 1, -1, -1):
		var runner: PathRunner = candidates[index]
		if runner == null:
			continue
		runner = runner.advanced_copy(tick_index)
		candidates[index] = runner
		var issue: String = runner.error
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
		if _definitions[index].entity_name in ["ORG_FLY", "ORG_BABY_FROG"] or (deferred_updates and _lifecycle != null and previous.live):
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
		var survivors := PackedInt32Array()
		for entity_id: int in next_state.live_order:
			var slot: int = _slot_for_id(entity_id)
			if slot < 0:
				return "Entity live-list identity is invalid"
			var entity: EntitySnapshot = next_state.entities[slot]
			if not deferred_updates and entity.destroy_pending and entity_id != attached_entity_index:
				_retire_instance(next_state, entity)
			else:
				if not deferred_updates:
					entity.destroy_pending = not _definitions[slot].is_immortal()
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
	return _update_script(slot, context, random, false)

func _update_script(slot: int, context: EntityUpdateContext, random: SourceRandom, owned: bool) -> EntityUpdateResult:
	if slot < 0 or _state == null or not _state.entities[slot].live or _definitions[slot].script_definition == null:
		var failed := EntityUpdateResult.new()
		failed.error = "Entity has no script state"
		return failed
	var entity: EntitySnapshot = _state.entities[slot]
	var result: EntityUpdateResult
	if owned and _scripts[slot].matches(entity.animation, context):
		result = EntityScriptRunner._update_validated(_scripts[slot]._definition, entity.script_state, entity.animation, context, random, _scripts[slot], true)
	else:
		result = EntityScriptRunner.update_prepared(_scripts[slot], entity.script_state, entity.animation, context, random)
	if result.error.is_empty():
		entity.script_state = result.script_state if owned else result.script_state.copy()
		entity.animation = result.animation if owned else result.animation.copy()
		entity.matrix12 = result.matrix12.duplicate()
		entity.requests = TickEvent.copy_all(result.requests)
		entity.colour_scale = result.script_state.colours
		entity.ambient = result.script_state.ambient
		entity.live_flags = (entity.live_flags & ~EntityLiveFlags.NO_SCREEN_FADE) | (65536 if result.script_state.no_screen_fade else 0)
		if result.drown:
			entity.live_flags &= ~EntityLiveFlags.CARRIES_FROG_0
	return result

## Copies one current authored slot without cloning the aggregate.
func entity_snapshot(slot: int) -> EntitySnapshot:
	return _state.entities[slot].copy()

## Captures an ordered update, then applies UpdateLiveEntities' transient clear.
func finish_update(slot: int, previous_flags: int, random: SourceRandom, sounds: int, environment: EntityEnvironmentState, death_requested: bool, capture_observation: bool = true) -> void:
	if death_requested:
		_state.entities[slot].requests.append(TickEvent.make(TickEvent.Kind.DEATH_PGEN))
	if capture_observation:
		var observation := EntityUpdateObservation.new()
		observation.entity = _state.entities[slot].copy()
		observation.previous_flags = previous_flags
		observation.rng_state = random.state
		observation.sound_requests = sounds
		observation.environment = environment.copy() if environment != null else null
		_state.updates.append(observation)
	_state.entities[slot].live_flags &= ~EntityLiveFlags.CLEAR_MASK
	if _lifecycle != null:
		_state.entities[slot].destroy_pending = not _definitions[slot].is_immortal()

## Publishes this tick's frog contact flags for the following entity update.
func set_contact_flags(hits: PackedInt32Array, carries: PackedInt32Array) -> void:
	for entity: EntitySnapshot in _state.entities:
		entity.live_flags &= ~(EntityLiveFlags.CARRIES_FROG_0 | EntityLiveFlags.CARRIES_FROG_1 | EntityLiveFlags.CARRIES_FROG_2 | EntityLiveFlags.CARRIES_FROG_3 | EntityLiveFlags.HIT_FROG_0 | EntityLiveFlags.HIT_FROG_1 | EntityLiveFlags.HIT_FROG_2 | EntityLiveFlags.HIT_FROG_3)
		if hits.has(entity.entity_index):
			entity.live_flags |= EntityLiveFlags.HIT_FROG_0
		if carries.has(entity.entity_index):
			entity.live_flags |= EntityLiveFlags.CARRIES_FROG_0

## Advances authoritative entity clocks once at the aggregate pose phase.
func advance_animations() -> void:
	for entity: EntitySnapshot in _state.entities:
		if entity.live and entity.animation != null:
			entity.animation.advance()

## Updates one admitted custom neighbor on detached candidate state.
func update_background(entity_index: int, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool, contacts: Array[FormContactDefinition] = [], frog: RunSnapshot = null) -> EntityBackgroundResult:
	var slot: int = _slot_for_id(entity_index)
	if slot < 0:
		var failed := EntityBackgroundResult.new()
		failed.error = "Unknown background entity"
		return failed
	var definition: EntityDefinition = _definitions[slot]
	var parent_live: bool = false
	var parent: EntitySnapshot = null
	var parent_form: FormContactDefinition = null
	if definition.entity_name == "ORG_BABY_FROG":
		for candidate: EntitySnapshot in _state.entities:
			if candidate.unique_id == definition.parent_unique_id:
				parent_live = candidate.live
				parent = candidate
				var parent_slot: int = _slot_for_id(candidate.entity_index)
				if parent_slot < contacts.size():
					parent_form = contacts[parent_slot]
				break
	var result: EntityBackgroundResult = EntityBackground.update(definition, _state.entities[slot], environment, random, frog_position, hit, parent_live, parent if _lifecycle != null else null, parent_form, frog)
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
				if definition.is_group_moving() != (pass_index == 0):
					continue
				var pose: EntitySnapshot = next_state.entities[slot]
				var group_point := Vector3i(pose.matrix12[9], pose.matrix12[10], pose.matrix12[11])
				if pose.path != null:
					group_point = pose.path.position
				elif not definition.is_group_moving():
					group_point = Vector3i(definition.matrix12[9], definition.matrix12[10], definition.matrix12[11])
				if _group_for(group_point.x, group_point.z) != group_index:
					continue
				if next_state.entities[slot].entity_flags & EntityDefinition.HIDDEN:
					continue
				var entity: EntitySnapshot = next_state.entities[slot]
				if not entity.lifecycle_supported:
					continue
				if entity.live:
					entity.destroy_pending = false
					entity.live_flags &= ~EntityLiveFlags.DESTROY
				else:
					_initialize_instance(entity, definition)
					entity.generation += 1
					next_state.live_order.insert(0, entity.entity_index)
					next_state.lifecycle_events.append(TickEvent.lifecycle(TickEvent.Kind.CREATE, entity.entity_index, entity.generation))
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

func _initialize_instance(entity: EntitySnapshot, definition: EntityDefinition) -> void:
	entity.live = true
	if entity.path != null:
		entity.matrix12 = EntityTransform.moving(entity.path, definition.flags)
	entity.destroy_pending = false
	entity.animation = EntityAnimationState.create(definition.action_lengths, definition.animation_one_shot)
	entity.live_flags = EntityLiveFlags.ANIMATED | EntityLiveFlags.FLIPBOOK if not definition.action_lengths.is_empty() else 0
	entity.script_state = EntityScriptState.create(definition.script_definition.root_id) if definition.script_definition != null else null
	entity.colour_scale = Vector3i.ZERO
	entity.ambient = Vector3i.ZERO
	entity.requests.clear()
	if definition.background_admitted:
		entity.background = EntityBackgroundState.new()
		if definition.entity_name == "ORG_FLY":
			entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
			entity.background.model_hidden = true
		elif definition.entity_name == "ORG_BABY_FROG":
			entity.background.timer = 0
			entity.background.model_hidden = true
		elif definition.entity_name == "CHECKPOINT":
			entity.ambient = Vector3i(160, 160, 160)

func _retire_instance(state: EntityRunSnapshot, entity: EntitySnapshot) -> void:
	entity.live = false
	entity.destroy_pending = false
	entity.script_state = null
	entity.animation = null
	entity.background = null
	entity.live_flags = 0
	entity.requests.clear()
	entity.colour_scale = Vector3i.ZERO
	entity.ambient = Vector3i.ZERO
	state.lifecycle_events.append(TickEvent.lifecycle(TickEvent.Kind.DESTROY, entity.entity_index, entity.generation))

## Returns detached slots in actual live-list order, or the original all-attached order.
func update_slots() -> PackedInt32Array:
	var result := PackedInt32Array()
	if _lifecycle != null:
		for entity_id: int in _state.live_order:
			result.append(_slot_for_id(entity_id))
	else:
		for slot: int in range(_definitions.size() - 1, -1, -1):
			result.append(slot)
	return result

## Applies retirement and base update at the source visit, before custom/script work.
func begin_update(slot: int, attached: int) -> bool:
	if _lifecycle == null:
		return true
	var entity: EntitySnapshot = _state.entities[slot]
	if entity.destroy_pending and entity.entity_index != attached:
		_retire_instance(_state, entity)
		_state.live_order.remove_at(_state.live_order.find(entity.entity_index))
		return false
	entity.live_flags = (entity.live_flags & ~EntityLiveFlags.DESTROY) | int(entity.destroy_pending)
	if entity.path != null:
		entity.matrix12 = EntityTransform.moving(entity.path, _definitions[slot].flags)
	return true
