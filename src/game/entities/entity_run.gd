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
func update_candidate_script(slot: int, context: EntityUpdateContext, random: SourceRandom, runtime: EntityScriptRuntime = null) -> EntityUpdateResult:
	return _update_script(slot, context, random, true, runtime)

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
		if definition.behavior == null or definition.behavior.kind == EntityBehavior.Kind.UNKNOWN:
			result.error = "Entity %d has unsupported name %s" % [definition.entity_index, definition.entity_name]
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
		if definition.flags & EntityDefinition.LOCAL_ALIGN or (definition.flags & EntityDefinition.PROJECT_ON_LAND and definition.behavior.kind != EntityBehavior.Kind.HEDGEHOG):
			result.error = "Entity %d requires unsupported alignment or land projection" % definition.entity_index
			return result
		if definition.behavior.layout == EntityBehavior.Layout.MATRIX and (definition.behavior.kind == EntityBehavior.Kind.STATIC or definition.behavior.has_custom_update()):
			if definition.path_definition != null or definition.path_start != null:
				result.error = "Static entity %d cannot attach a path" % definition.entity_index
				return result
		elif definition.behavior.layout == EntityBehavior.Layout.PATH:
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
		if definition.behavior.kind in [EntityBehavior.Kind.HIVE, EntityBehavior.Kind.HEDGEHOG] and definition.forest == null:
			result.error = "Forest behavior requires decoded subtype operands"
			return result
		if definition.behavior.kind in [EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG] and definition.action_lengths.size() < 2:
			result.error = "Forest animal requires both source animation actions"
			return result
		if definition.behavior.has_custom_update() and definition.behavior.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM]:
			if definition.volcano == null:
				result.error = "Volcano behavior requires decoded subtype operands"
				return result
			if definition.behavior.kind == EntityBehavior.Kind.VOL_COLOUR_SWITCH and definition.action_lengths.size() < 2:
				result.error = "Colour switch requires both source animation actions"
				return result
			if definition.behavior.kind == EntityBehavior.Kind.VOL_FALLING_PLATFORM and definition.action_lengths.is_empty():
				result.error = "Falling platform requires a source animation action"
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
			_initialize_instance(entity, definition, null, false, candidates[index])
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
		next_state.entities[index].model_present = previous.model_present
		next_state.entities[index].pop_allocated = previous.pop_allocated
		next_state.entities[index].pop_remaining = previous.pop_remaining
		if previous.live and previous.script_state != null and previous.path == null:
			next_state.entities[index].matrix12 = previous.matrix12.duplicate()
		next_state.entities[index].script_state = previous.script_state.copy() if previous.script_state != null else null
		next_state.entities[index].animation = previous.animation.copy() if previous.animation != null else null
		next_state.entities[index].entity_flags = previous.entity_flags
		next_state.entities[index].custom_state = previous.custom_state.copy() if previous.custom_state != null else null
		next_state.entities[index].live_flags = previous.live_flags
		next_state.entities[index].colour_scale = previous.colour_scale
		next_state.entities[index].ambient = previous.ambient
		if _definitions[index].behavior.kind in [EntityBehavior.Kind.PICKUP, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG, EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG, EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM] or (deferred_updates and _lifecycle != null and previous.live):
			next_state.entities[index].matrix12 = previous.matrix12.duplicate()
	if _lifecycle != null:
		next_state.lifecycle_enabled = true
		next_state.live_order = _state.live_order.duplicate()
		next_state.selected_groups = _state.selected_groups.duplicate()
		next_state.map_group_timers = _state.map_group_timers.duplicate()
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

## Resets only source-selected paths and instances, retaining the global tick clock.
## FORM bits mean reset in frozen C despite FrogLord's inverse flag labels.
func reset_in_level(checkpoint: bool, environment: EntityEnvironmentState = null, gold_collected: bool = false) -> String:
	var candidate: EntityRun = copy()
	var next_environment: EntityEnvironmentState = environment.copy() if environment != null else null
	var reset_flag: int = 8 if checkpoint else 16
	for slot: int in candidate._definitions.size():
		var definition: EntityDefinition = candidate._definitions[slot]
		var entity: EntitySnapshot = candidate._state.entities[slot]
		if not definition.form_flags & reset_flag:
			continue
		if definition.path_definition != null:
			var start: PathStart = definition.path_start.copy()
			start.flags |= PathStart.ACTIVE
			if entity.entity_flags & EntityDefinition.NO_MOVEMENT:
				start.flags &= ~PathStart.ACTIVE
			var runner: PathRunner = candidate._runners[slot].copy()
			var issue: String = runner.reset_motion(start)
			if not issue.is_empty():
				return issue
			candidate._runners[slot] = runner
			entity.path = runner.snapshot()
		if entity.live:
			if next_environment != null and definition.behavior.kind == EntityBehavior.Kind.CROC_HEAD and entity.custom_state != null and entity.custom_state.checkpoint_index >= 0:
				var bit: int = 1 << entity.custom_state.checkpoint_index
				next_environment.covered &= ~bit
				next_environment.collision_disabled &= ~bit
				candidate.apply_checkpoint_collision(next_environment.collision_disabled)
			candidate._retire_instance(candidate._state, entity)
			var order_slot: int = candidate._state.live_order.find(entity.entity_index)
			if order_slot >= 0:
				candidate._state.live_order.remove_at(order_slot)
	for slot: int in candidate._definitions.size():
		var definition: EntityDefinition = candidate._definitions[slot]
		var entity: EntitySnapshot = candidate._state.entities[slot]
		if not entity.live and (definition.is_immortal() or candidate._lifecycle == null):
			candidate._initialize_instance(entity, definition, next_environment, gold_collected, candidate._runners[slot])
			entity.generation += 1
			candidate._state.live_order.insert(0, entity.entity_index)
			candidate._state.lifecycle_events.append(TickEvent.lifecycle(TickEvent.Kind.CREATE, entity.entity_index, entity.generation))
	commit_candidate(candidate)
	if environment != null:
		environment.active_swarms = next_environment.active_swarms
		environment.covered = next_environment.covered
		environment.collision_disabled = next_environment.collision_disabled
	return ""

## Returns a fully detached source-ordered run snapshot.
func snapshot() -> EntityRunSnapshot:
	return _state.copy() if _state != null else null

## Updates one candidate entity; the caller applies frog effects before the next visit.
func update_script(entity_index: int, context: EntityUpdateContext, random: SourceRandom) -> EntityUpdateResult:
	var slot: int = _slot_for_id(entity_index)
	return _update_script(slot, context, random, false)

func _update_script(slot: int, context: EntityUpdateContext, random: SourceRandom, owned: bool, runtime: EntityScriptRuntime = null) -> EntityUpdateResult:
	if context == null or slot < 0 or _state == null or not _state.entities[slot].live or _definitions[slot].script_definition == null:
		var failed := EntityUpdateResult.new()
		failed.error = "Entity has no script state"
		return failed
	var entity: EntitySnapshot = _state.entities[slot]
	context = context.copy()
	context.authored_matrix = _definitions[slot].matrix12.duplicate()
	context.entity_flags = entity.entity_flags
	context.pop_allocated = entity.pop_allocated
	context.path_flags = entity.path.flags if entity.path != null else 0
	var result: EntityUpdateResult
	if owned:
		var prepared: PreparedEntityScript = _scripts[slot]
		if not prepared.matches(entity.animation, context):
			var issue: String = prepared._definition.validate(entity.animation.lengths, context.form_id, context.has_path)
			if not issue.is_empty():
				var failed := EntityUpdateResult.new()
				failed.error = issue
				return failed
			prepared = null
		result = EntityScriptRunner._update_validated(_scripts[slot]._definition, entity.script_state, entity.animation, context, random, prepared, true, runtime)
	else:
		result = EntityScriptRunner.update_prepared(_scripts[slot], entity.script_state, entity.animation, context, random)
	if result.error.is_empty():
		if result.path_active_request >= 0:
			_runners[slot].set_active(result.path_active_request == 1)
			entity.path = _runners[slot].snapshot()
		entity.script_state = result.script_state if owned else result.script_state.copy()
		entity.animation = result.animation if owned else result.animation.copy()
		entity.matrix12 = result.matrix12.duplicate()
		entity.entity_flags = result.entity_flags
		if result.pop_started:
			entity.pop_allocated = true
			entity.pop_remaining = 32
		entity.requests = TickEvent.copy_all(result.requests)
		entity.colour_scale = result.script_state.colours
		entity.ambient = result.script_state.ambient
		entity.live_flags = (entity.live_flags & ~EntityLiveFlags.NO_SCREEN_FADE) | (65536 if result.script_state.no_screen_fade else 0)
		if result.drown:
			entity.live_flags &= ~EntityLiveFlags.CARRIES_FROG_0
	return result

## Applies an effect's detached pose and flags to its private candidate target.
func apply_tongue_target(target: EntitySnapshot) -> void:
	var slot: int = _slot_for_id(target.entity_index)
	assert(slot >= 0 and _state.entities[slot].unique_id == target.unique_id)
	_state.entities[slot] = target.copy()

## Copies one current authored slot without cloning the aggregate.
func entity_snapshot(slot: int) -> EntitySnapshot:
	return _state.entities[slot].copy()

## Applies script checkpoint collision flags to the candidate's authored checkpoints.
func apply_checkpoint_collision(disabled: int) -> void:
	for slot: int in _definitions.size():
		if _definitions[slot].behavior.kind != EntityBehavior.Kind.CHECKPOINT:
			continue
		var checkpoint: int = _definitions[slot].form_id & 32767
		if checkpoint >= 5:
			continue
		var entity: EntitySnapshot = _state.entities[slot]
		entity.entity_flags &= ~EntityDefinition.NO_COLLISION
		if disabled & (1 << checkpoint):
			entity.entity_flags |= EntityDefinition.NO_COLLISION

## Captures an ordered update, then applies UpdateLiveEntities' transient clear.
func finish_update(slot: int, previous_flags: int, random: SourceRandom, sounds: int, environment: EntityEnvironmentState, death_requested: bool, capture_observation: bool = true) -> void:
	_state.entities[slot].pop_remaining = maxi(0, _state.entities[slot].pop_remaining - 1)
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
func set_contact_flags(hits: PackedInt32Array, carries: PackedInt32Array, detached: EntityRunSnapshot = null) -> void:
	for slot: int in _state.entities.size():
		var entity: EntitySnapshot = _state.entities[slot]
		entity.live_flags &= ~(EntityLiveFlags.CARRIES_FROG_0 | EntityLiveFlags.CARRIES_FROG_1 | EntityLiveFlags.CARRIES_FROG_2 | EntityLiveFlags.CARRIES_FROG_3 | EntityLiveFlags.HIT_FROG_0 | EntityLiveFlags.HIT_FROG_1 | EntityLiveFlags.HIT_FROG_2 | EntityLiveFlags.HIT_FROG_3)
		if hits.has(entity.entity_index):
			entity.live_flags |= EntityLiveFlags.HIT_FROG_0
		if carries.has(entity.entity_index):
			entity.live_flags |= EntityLiveFlags.CARRIES_FROG_0
		if detached != null:
			assert(detached.entities[slot].entity_index == entity.entity_index)
			detached.entities[slot].live_flags = entity.live_flags

## Copies aggregate visit observations after individually synchronized entity updates.
func sync_update_observations(detached: EntityRunSnapshot) -> void:
	detached.updates.clear()
	for update: EntityUpdateObservation in _state.updates:
		detached.updates.append(update.copy())

## Advances authoritative entity clocks once at the aggregate pose phase.
func advance_animations() -> void:
	for entity: EntitySnapshot in _state.entities:
		if entity.live and entity.animation != null:
			entity.animation.advance()

## Validates every cross-target mutation before changing any candidate cursor.
func apply_target_effects(effects: Array[EntityTargetEffect]) -> String:
	var targets: Dictionary[int, EntitySnapshot] = {}
	for effect: EntityTargetEffect in effects:
		var slot: int = -1
		for candidate: int in _state.entities.size():
			if _state.entities[candidate].live and _state.entities[candidate].unique_id == effect.unique_id:
				slot = candidate
				break
		if slot < 0:
			if effect.kind == EntityTargetEffect.Kind.INITIALIZE:
				continue
			return "Colour switch target %d is not live" % effect.unique_id
		if not targets.has(slot):
			targets[slot] = _state.entities[slot].copy()
		var issue: String = EntityVolcanoTarget.apply(effect, targets[slot], _definitions[slot])
		if not issue.is_empty():
			return issue
	for slot: int in targets:
		var target: EntitySnapshot = targets[slot]
		if target.path != null:
			_runners[slot].set_active(bool(target.path.flags & PathStart.ACTIVE))
			_runners[slot].set_backwards(bool(target.path.flags & PathStart.BACKWARDS))
			target.path = _runners[slot].snapshot()
		_state.entities[slot] = target
	return ""

## Executes a switch contact against the private run and returns its frog correction.
func contact_colour_switch(entity_index: int, frog: GameplayState) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	var slot: int = _slot_for_id(entity_index)
	if slot < 0 or _definitions[slot].behavior.kind != EntityBehavior.Kind.VOL_COLOUR_SWITCH:
		result.error = "Colour-switch callback requires a supported switch entity"
		return result
	result.entity = _state.entities[slot].copy()
	result.error = EntityVolcanoSwitch.contact(_definitions[slot], result, frog)
	if result.error.is_empty():
		result.error = apply_target_effects(result.target_effects)
	if result.error.is_empty():
		_state.entities[slot] = result.entity.copy()
	return result

## Updates one supported custom neighbor on detached candidate state.
func update_custom(entity_index: int, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool, contacts: Array[FormContactDefinition] = [], frog: GameplayState = null, grid: GridDefinition = null, collision: EntityCollisionDefinition = null) -> EntityCustomResult:
	var slot: int = _slot_for_id(entity_index)
	if slot < 0:
		var failed := EntityCustomResult.new()
		failed.error = "Unknown background entity"
		return failed
	var definition: EntityDefinition = _definitions[slot]
	var parent_live: bool = false
	var parent: EntitySnapshot = null
	var parent_form: FormContactDefinition = null
	if definition.behavior.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.LOG_SNAKE]:
		for candidate: EntitySnapshot in _state.entities:
			if candidate.unique_id == definition.parent_unique_id:
				parent_live = candidate.live
				parent = candidate
				var parent_slot: int = _slot_for_id(candidate.entity_index)
				if parent_slot < contacts.size():
					parent_form = contacts[parent_slot]
				break
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, _state.entities[slot], environment, random, frog_position, hit, parent_live, parent if _lifecycle != null or definition.behavior.kind == EntityBehavior.Kind.LOG_SNAKE else null, parent_form, frog, _state.entities, _definitions, _state.tick_index - 1, grid, collision, contacts)
	if result.error.is_empty():
		if result.path_reset_requested:
			var start: PathStart = definition.path_start.copy()
			if result.entity.entity_flags & EntityDefinition.NO_MOVEMENT:
				start.flags &= ~PathStart.ACTIVE
			else:
				start.flags |= PathStart.ACTIVE
			result.error = _runners[slot].reset_motion(start)
			if not result.error.is_empty():
				return result
			result.entity.path = _runners[slot].snapshot()
			result.entity.matrix12 = EntityTransform.moving(result.entity.path, result.entity.entity_flags)
		if result.path_active_request >= 0:
			_runners[slot].set_active(result.path_active_request == 1)
			result.entity.path = _runners[slot].snapshot()
		if result.path_speed_request >= 0:
			_runners[slot].set_speed(result.path_speed_request)
			result.entity.path = _runners[slot].snapshot()
		result.error = apply_target_effects(result.target_effects)
		if not result.error.is_empty():
			return result
		_state.entities[slot] = result.entity.copy()
	return result

## Applies the post-camera source view list; new live objects first update next tick.
func apply_visibility(camera: GameplayCameraSnapshot, environment: EntityEnvironmentState = null, gold_collected: bool = false) -> String:
	if _state == null or _lifecycle == null:
		return "Entity run has no lifecycle visibility"
	var selection: MapGroupVisibilityResult = MapGroupVisibility.query(_lifecycle, camera)
	if not selection.error.is_empty():
		return selection.error
	if _lifecycle.source_allocation:
		selection = MapGroupAllocation.expand(_lifecycle, selection.groups, _state.map_group_timers)
		if not selection.error.is_empty():
			return selection.error
	var next_state: EntityRunSnapshot = _state.copy()
	next_state.selected_groups = selection.groups.duplicate()
	next_state.map_group_timers = selection.group_timers.duplicate()
	var grouped_slots: Dictionary[int, PackedInt32Array] = _visibility_slots(next_state, selection.groups)
	for group_index: int in selection.groups:
		for slot: int in grouped_slots[group_index]:
			var definition: EntityDefinition = _definitions[slot]
			var entity: EntitySnapshot = next_state.entities[slot]
			if entity.live:
				entity.destroy_pending = false
				entity.live_flags &= ~EntityLiveFlags.DESTROY
			else:
				_initialize_instance(entity, definition, environment, gold_collected, _runners[slot])
				entity.generation += 1
				next_state.live_order.insert(0, entity.entity_index)
				next_state.lifecycle_events.append(TickEvent.lifecycle(TickEvent.Kind.CREATE, entity.entity_index, entity.generation))
	_state = next_state
	return ""


func _visibility_slots(state: EntityRunSnapshot, selected: PackedInt32Array) -> Dictionary[int, PackedInt32Array]:
	var groups: Dictionary[int, PackedInt32Array] = {}
	for group_index: int in selected:
		groups[group_index] = PackedInt32Array()
	for pass_index: int in 2:
		for slot: int in range(_definitions.size() - 1, -1, -1):
			var definition: EntityDefinition = _definitions[slot]
			var moving: bool = definition.is_group_moving()
			if moving != (pass_index == 0):
				continue
			var entity: EntitySnapshot = state.entities[slot]
			if entity.entity_flags & EntityDefinition.HIDDEN or not entity.lifecycle_supported:
				continue
			var point := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
			if entity.path != null:
				point = entity.path.position
			elif not moving:
				point = Vector3i(definition.matrix12[9], definition.matrix12[10], definition.matrix12[11])
			var group_index: int = _group_for(point.x, point.z)
			if groups.has(group_index):
				var slots: PackedInt32Array = groups[group_index]
				slots.append(slot)
				groups[group_index] = slots
	return groups

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
		entity.flags_authoritative = true
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

func _initialize_instance(entity: EntitySnapshot, definition: EntityDefinition, environment: EntityEnvironmentState = null, gold_collected: bool = false, runner: PathRunner = null) -> void:
	entity.live = true
	entity.model_present = true
	entity.matrix12 = definition.matrix12.duplicate()
	if entity.path != null:
		entity.matrix12 = EntityTransform.moving(entity.path, definition.flags)
	entity.destroy_pending = false
	entity.animation = EntityAnimationState.create(definition.action_lengths, definition.behavior.one_shot)
	entity.live_flags = EntityLiveFlags.ANIMATED | EntityLiveFlags.FLIPBOOK if not definition.action_lengths.is_empty() else 0
	entity.script_state = EntityScriptState.create(definition.script_definition.root_id) if definition.script_definition != null else null
	entity.colour_scale = Vector3i.ZERO
	entity.ambient = Vector3i.ZERO
	entity.pop_allocated = false
	entity.pop_remaining = 0
	entity.requests.clear()
	if definition.behavior.has_custom_update():
		entity.custom_state = EntityCustomState.new()
		if definition.behavior.kind == EntityBehavior.Kind.VOL_COLOUR_SWITCH:
			entity.custom_state.mode = EntityVolcanoSwitch.Mode.OFF_UP
			entity.custom_state.timer = 0
			entity.custom_state.texture_animation_paused = true
			entity.custom_state.texture_animation_cel = 0
			entity.animation.select(1)
			entity.animation.one_shot = true
		elif definition.behavior.kind == EntityBehavior.Kind.VOL_FALLING_PLATFORM:
			entity.custom_state.timer = 0
			entity.animation.cel = 0
			entity.animation.stepping = false
			entity.entity_flags &= ~EntityDefinition.NO_COLLISION
		elif definition.behavior.kind == EntityBehavior.Kind.HIVE:
			entity.custom_state.swarm = EntitySwarmState.new()
			entity.custom_state.moving_sound = PackedInt32Array([64, 512, 1024])
			if environment != null:
				environment.active_swarms = 0
		elif definition.behavior.kind == EntityBehavior.Kind.BREAKING_BRANCH:
			entity.custom_state.timer = definition.authored_delay
			entity.entity_flags &= ~EntityDefinition.NO_COLLISION
		elif definition.behavior.kind == EntityBehavior.Kind.SQUIRREL:
			entity.animation.select(0)
			if not entity.animation.lengths.is_empty():
				entity.custom_state.delay = maxi(0, PlatformMath.divide(definition.authored_delay, entity.animation.lengths[0]) - 1) & 65535
		elif definition.behavior.kind == EntityBehavior.Kind.HEDGEHOG:
			var speed: int = EntityHedgehog.start(definition, entity, false)
			if runner != null:
				runner.set_speed(speed)
				entity.path = runner.snapshot()
		elif definition.behavior.kind == EntityBehavior.Kind.PICKUP:
			EntityBonusFly.initialize(definition, entity)
		elif definition.behavior.kind in [EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.CROC_HEAD]:
			entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
			entity.custom_state.model_hidden = true
		elif definition.behavior.kind == EntityBehavior.Kind.DOG:
			entity.custom_state.timer = definition.authored_delay
			if runner != null:
				runner.set_active(false)
				entity.path = runner.snapshot()
		elif definition.behavior.kind == EntityBehavior.Kind.BEAVER:
			entity.custom_state.mode = EntityBeaver.Mode.WAITING_FIRST
		elif definition.behavior.kind == EntityBehavior.Kind.BABY_FROG:
			entity.custom_state.timer = 0
			entity.custom_state.model_hidden = true
		elif definition.behavior.kind == EntityBehavior.Kind.CHECKPOINT:
			var checkpoint: int = definition.form_id & 32767
			if environment != null and environment.collected & (1 << checkpoint):
				entity.entity_flags |= EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY | EntityDefinition.HIDDEN
				entity.animation = null
				entity.model_present = false
				entity.live_flags = 0
				entity.custom_state.model_hidden = true
			else:
				entity.entity_flags &= ~(EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY | EntityDefinition.HIDDEN)
				entity.ambient = Vector3i(160, 160, 160)
		elif definition.behavior.kind == EntityBehavior.Kind.GOLD_FROG and gold_collected:
			entity.animation = null
			entity.model_present = false
			entity.live_flags = 0
			entity.custom_state.model_hidden = true

func _retire_instance(state: EntityRunSnapshot, entity: EntitySnapshot) -> void:
	entity.live = false
	entity.model_present = false
	entity.destroy_pending = false
	entity.script_state = null
	entity.animation = null
	entity.custom_state = null
	entity.live_flags = 0
	entity.pop_allocated = false
	entity.pop_remaining = 0
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

## Synchronizes source moving-object and voice ownership before entity updates.
func set_sound_state(entity_index: int, has_object: bool, has_voice: bool) -> void:
	var slot: int = _slot_for_id(entity_index)
	if slot < 0:
		return
	var entity: EntitySnapshot = _state.entities[slot]
	if entity.custom_state != null:
		entity.custom_state.moving_voice_active = has_voice
		if not has_object:
			entity.custom_state.moving_sound.clear()
	if entity.script_state != null and not has_object:
		entity.script_state.moving_sound.clear()
