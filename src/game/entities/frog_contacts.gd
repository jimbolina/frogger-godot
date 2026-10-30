class_name FrogContacts
extends RefCounted
## Ordered entity contacts and platform attachment transitions for one frog.

const CAVES3_MAP_INDEX: int = 2

## Scans source-ordered contacts and applies supported reactions.
func contact_entities(frog: Frog, state: GameplayState, result: TickResult) -> String:
	if state.entities == null or state.entities.entities.size() != frog.entity_collision.entities.size():
		return "Entity collision snapshot does not match validated definitions"
	for index: int in frog.entity_collision.entities.size():
		var expected: EntityDefinition = frog.entity_collision.entities[index]
		var actual: EntitySnapshot = state.entities.entities[index]
		if actual == null or actual.entity_index != expected.entity_index or actual.unique_id != expected.unique_id:
			return "Entity collision snapshot identity does not match validated definitions"
	var ordered: PackedInt32Array = EntityContactOrder._indices_validated(frog.entity_collision, state.entities, Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]))
	var forbidden: int = state.attachment.forbidden_entity_index
	for entity_id: int in ordered:
		if frog.tick_guard != null:
			var guard_error: String = frog.check_guard(TickGuard.Phase.CONTACT_POSE, state)
			if not guard_error.is_empty():
				return guard_error
		if entity_id == state.attachment.current_entity_index or entity_id == forbidden:
			continue
		var index: int = -1
		for candidate: int in frog.entity_collision.entities.size():
			if frog.entity_collision.entities[candidate].entity_index == entity_id:
				index = candidate
				break
		if index < 0:
			return "Entity contact order produced an unknown authored index"
		if state.entities.lifecycle_enabled and not state.entities.entities[index].live:
			return "Entity contact order produced a dormant identity"
		var definition: FormContactDefinition = frog.entity_collision.contacts[index]
		var pose: EntitySnapshot = state.entities.entities[index]

		if definition.sphere_callback:
			if pose.live and not pose.effective_flags(definition.entity_flags) & EntityDefinition.NO_COLLISION:
				var delta := Vector3i(PlatformMath.s16(state.frog.matrix12[9] - pose.matrix12[9]), PlatformMath.s16(state.frog.matrix12[10] - pose.matrix12[10]), PlatformMath.s16(state.frog.matrix12[11] - pose.matrix12[11]))
				if PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) < definition.radius_squared:
					return FormCallback.apply(definition.callback_kind, frog, state, pose.entity_index, result.events)
			continue
		if state.frog.flags & FrogFlags.JUMP_FROM_COLLPRIM:
			continue
		if not definition.primitives.is_empty():
			var primitive: EntityPrimitiveContact = contact_primitive(frog, state, definition, pose)
			result.primitive_contacts.append(primitive)
			if primitive.status in [EntityPrimitiveQuery.INVALID, EntityPrimitiveQuery.UNSUPPORTED]:
				return primitive.reason
			if primitive.status == EntityPrimitiveQuery.CONTACT:
				if primitive.reaction == 3:
					var callback_issue: String = FormCallback.apply(definition.callback_kind, frog, state, pose.entity_index, result.events)
					if not callback_issue.is_empty():
						return callback_issue
					if not state.attachment.entity_hit_indices.has(pose.entity_index):
						state.attachment.entity_hit_indices.append(pose.entity_index)
					continue
				var reaction: FormReactionResult = FormReaction.deadly(definition.death_type)
				var issue: String = apply_form_reaction(frog, state, definition, pose, reaction, result, true)
				if not issue.is_empty():
					return issue
				if reaction.status == FormReactionResult.SQUISH:
					for component: int in range(3, 6):
						state.frog.matrix12[component] = 0
				continue
		var contact: FormContactResult = FormContactQuery.query(definition, pose, Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]))
		var reaction: FormReactionResult = FormReaction.evaluate(definition, contact, frog.entity_collision.platforms_enabled)
		if reaction.status == FormReactionResult.INVALID:
			return reaction.reason
		result.entity_contacts.append(reaction)
		var issue: String = apply_form_reaction(frog, state, frog.entity_collision.contacts[index], state.entities.entities[index], reaction, result)
		if not issue.is_empty():
			return issue
	if state.attachment.current_entity_index >= 0 and state.frog.flags & (FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY) == (FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY) and state.frog.remaining_ticks == 1:
		if frog.tick_guard != null:
			var guard_error: String = frog.check_guard(TickGuard.Phase.CONTACT_WORLD, state)
			if not guard_error.is_empty():
				return guard_error
		var pose: EntitySnapshot = platform_pose(frog, state)
		var definition: FormContactDefinition = platform_definition(frog, state)
		var delta: Vector3i = Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]) - Vector3i(pose.matrix12[9], pose.matrix12[10], pose.matrix12[11])
		delta = Vector3i(PlatformMath.s16(delta.x), PlatformMath.s16(delta.y), PlatformMath.s16(delta.z))
		var local: Vector3i = PlatformMath.apply(PlatformMath.transpose(pose.matrix12), delta)
		var cell := Vector2i((local.x - definition.offsets.x) >> 8, (local.z - definition.offsets.y) >> 8)
		if cell.x < 0 or cell.y < 0 or cell.x >= definition.dimensions.x or cell.y >= definition.dimensions.y:
			return "Source same-platform re-reaction cell lies outside authored storage"
		var contact := FormContactResult.new()
		contact.status = FormContactResult.CONTACT
		contact.entity_index = definition.entity_index
		contact.unique_id = definition.unique_id
		contact.form_grid_id = definition.form_grid_id
		contact.form_id = definition.form_id
		contact.form_name = definition.form_name
		contact.local_position = local
		contact.cell = cell
		contact.height = definition.height
		contact.cell_flags = definition.grid_flags[cell.y * definition.dimensions.x + cell.x]
		var reaction: FormReactionResult = FormReaction.evaluate(definition, contact, true)
		if reaction.status in [FormReactionResult.INVALID, FormReactionResult.UNSUPPORTED]:
			return "Same-platform re-reaction requires a supported cell: " + reaction.reason
		result.entity_contacts.append(reaction)
		var issue: String = apply_form_reaction(frog, state, definition, pose, reaction, result)
		if not issue.is_empty():
			return issue
		reaction.hit = true
		if not state.attachment.entity_hit_indices.has(pose.entity_index):
			state.attachment.entity_hit_indices.append(pose.entity_index)
	return ""


## Queries the stored collision pose against an entity primitive.
## A static model is framed by the entity matrix and an animated model by its
## primitive part's stored LW transform; the source rotation cache spans checks.
func contact_primitive(frog: Frog, state: GameplayState, definition: FormContactDefinition, pose: EntitySnapshot) -> EntityPrimitiveContact:
	var result := EntityPrimitiveContact.new()
	result.entity_index = pose.entity_index
	result.unique_id = pose.unique_id
	if not definition.disabled_reason.is_empty() or not pose.live or pose.effective_flags(definition.entity_flags) & EntityDefinition.NO_COLLISION:
		result.status = EntityPrimitiveQuery.DISABLED
		result.reason = "Entity has no collision-live instance"
		return result
	if not pose.model_present:
		result.status = EntityPrimitiveQuery.MISS
		result.reason = "Source model absent; FORM fallback remains eligible"
		return result
	if not PlatformMath.valid(pose.matrix12) or state.frog.frog_collision_pose == null:
		result.status = EntityPrimitiveQuery.INVALID
		result.reason = "Primitive contact requires an entity matrix and stored frog pose"
		return result
	var delta := Vector3i(PlatformMath.s16(state.frog.matrix12[9] - pose.matrix12[9]), PlatformMath.s16(state.frog.matrix12[10] - pose.matrix12[10]), PlatformMath.s16(state.frog.matrix12[11] - pose.matrix12[11]))
	var distance: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	if distance >= definition.radius_squared:
		result.status = EntityPrimitiveQuery.MISS
		result.reason = "Outside strict form-book bounding sphere"
		return result
	var part: EntityPrimitivePartDefinition = definition.primitive_part
	var frame: PackedInt32Array = pose.matrix12
	if part != null:
		if pose.primitive_pose == null or pose.primitive_pose.lw12.is_empty():
			result.status = EntityPrimitiveQuery.UNPRIMED
			result.reason = "Animated primitive part has no stored LW transform yet"
			return result
		frame = pose.primitive_pose.lw12
	var probes: FrogCollisionQuery.Sample = state.frog.frog_collision_pose.probes
	var rotation := PackedInt32Array()
	if definition.primitives.size() == 1 and definition.primitives[0] != null and probes != null and not probes.points.is_empty() and FrogCollisionQuery.validate_matrix(frame).is_empty():
		var primitive: EntityPrimitiveDefinition = definition.primitives[0]
		if primitive.validate().is_empty() and not primitive.flags & EntityPrimitiveDefinition.DISABLED:
			var entity: EntityDefinition = null
			if frog != null and frog.entity_collision != null:
				for candidate: EntityDefinition in frog.entity_collision.entities:
					if candidate != null and candidate.entity_index == pose.entity_index:
						entity = candidate
						break
			var frame_key: String = CollisionTransposeCache.frame_key_for(CollisionTransposeCache.is_stationary(entity), part != null, pose.entity_index, pose.generation, primitive.part_index)
			rotation = state.attachment.primitive_transpose.resolve(frame_key, CollisionTransposeCache.matrix_key_for(primitive), frame, primitive)
	var hit: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query(definition.primitives, frame, probes, rotation)
	result.status = hit.status
	result.reason = hit.reason
	result.frog_part_index = hit.part_index
	result.hilite_index = hit.hilite_index
	result.primitive_part_index = hit.primitive_part_index
	result.primitive_index = hit.primitive_index
	result.reaction = hit.reaction
	result.world_point = hit.world_point
	result.local_position = hit.local_position
	return result


## Applies a FORM death, bounce or attachment reaction.
func apply_form_reaction(frog: Frog, state: GameplayState, definition: FormContactDefinition, pose: EntitySnapshot, reaction: FormReactionResult, result: TickResult, primitive: bool = false) -> String:
	if reaction.status == FormReactionResult.SAFE:
		var issue: String = mount_platform(frog, state, definition, pose, reaction, result.events)
		if not issue.is_empty():
			return issue
	if reaction.status == FormReactionResult.CHECKPOINT:
		for entity: EntityDefinition in frog.entity_collision.entities:
			if entity.entity_index == pose.entity_index:
				var issue: String = CheckpointCollection.collect(frog, state, entity, result.events)
				if not issue.is_empty():
					return issue
				break
	if reaction.status == FormReactionResult.BOUNCE:
		var issue: String = frog.bounce_from_entity(state, pose.entity_index, pose.matrix12, result.events)
		if not issue.is_empty():
			return issue
	if reaction.hit and not state.attachment.entity_hit_indices.has(pose.entity_index):
		state.attachment.entity_hit_indices.append(pose.entity_index)
	if reaction.kill_animation >= 0 and state.attachment.death_entity_index < 0 and state.frog.mode != FrogMode.DYING and not state.frog.flags & FrogFlags.MUST_DIE:
		var velocity: Vector3i = state.frog.velocity_16
		frog.kill(state, reaction.kill_animation, reaction.down_velocity, result.events)
		if reaction.hide_shadow and not primitive and frog.map_index == CAVES3_MAP_INDEX:
			state.frog.velocity_16 = velocity
		state.attachment.death_entity_index = pose.entity_index
		if reaction.status == FormReactionResult.POP and not primitive:
			result.events.append(TickEvent.make(TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST))
		elif reaction.status == FormReactionResult.SQUISH:
			result.events.append(TickEvent.make(TickEvent.Kind.ENTITY_SQUISH))
	if reaction.hide_shadow:
		state.frog.shadow_hidden = true
	if frog.tick_guard != null:
		return frog.check_guard(TickGuard.Phase.CONTACT_WORLD, state)
	return ""


## Finds the current live platform pose.
func platform_pose(_frog: Frog, state: GameplayState) -> EntitySnapshot:
	if state.entities != null:
		for pose: EntitySnapshot in state.entities.entities:
			if pose != null and pose.entity_index == state.attachment.current_entity_index and PlatformMath.valid(pose.matrix12):
				if state.entities.lifecycle_enabled and (not pose.live or not pose.lifecycle_supported):
					return null
				return pose
	return null


## Finds the current platform contact definition.
func platform_definition(frog: Frog, state: GameplayState) -> FormContactDefinition:
	if frog.entity_collision != null:
		for definition: FormContactDefinition in frog.entity_collision.contacts:
			if definition.entity_index == state.attachment.current_entity_index:
				return definition
	return null


## Records a platform carrying this frog.
func mark_carry(_frog: Frog, state: GameplayState, index: int) -> void:
	if not state.attachment.entity_carry_indices.has(index):
		state.attachment.entity_carry_indices.append(index)


## Establishes platform-local attachment and camera state.
func mount_platform(frog: Frog, state: GameplayState, definition: FormContactDefinition, pose: EntitySnapshot, reaction: FormReactionResult, events: Array[TickEvent]) -> String:
	var matrix: PackedInt32Array = pose.matrix12
	if PlatformMath.s32(matrix[2] * matrix[2] + matrix[8] * matrix[8]) < 0x700 * 0x700:
		reaction.status = FormReactionResult.NONE
		reaction.reason = "SAFE platform is too vertical"
		return ""
	if state.frog.flags & (FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY) != (FrogFlags.JUMP_TO_ENTITY | FrogFlags.JUMP_FROM_ENTITY):
		var previous: PackedInt32Array = PackedInt32Array()
		if state.attachment.current_entity_index >= 0:
			previous = platform_pose(frog, state).matrix12
		frog.react_fall(state, state.frog.matrix12[10] - state.frog.old_y, reaction.contact.cell_flags, events)
		var outcome: TerrainCallbackResult = TerrainPlatform.land(state, definition, reaction.contact, pose, frog.camera, previous)
		frog.apply_requests(state, outcome, events)
		if not outcome.error.is_empty():
			return outcome.error
		frog.update_world(state)
		mark_carry(frog, state, pose.entity_index)
		events.append(TickEvent.make(TickEvent.Kind.PLATFORM_ATTACHMENT))
	reaction.hit = true
	return ""


## Clears attachment with the source camera transition.
func detach_platform(frog: Frog, state: GameplayState, events: Array[TickEvent]) -> void:
	if state.attachment.current_entity_index < 0:
		return
	frog.callback_error = frog.camera.transition_attachment(platform_pose(frog, state).matrix12, PackedInt32Array(), false)
	state.attachment.current_entity_index = -1
	events.append(TickEvent.make(TickEvent.Kind.PLATFORM_DEPARTURE))


## Prepares a jump from the current platform.
func jump_platform(frog: Frog, state: GameplayState, input: int, events: Array[TickEvent], is_super: bool, distance: int, duration: int = 0, forced: bool = false) -> String:
	var definition: FormContactDefinition = platform_definition(frog, state)
	var pose: EntitySnapshot = platform_pose(frog, state)
	if definition == null or pose == null:
		return "Platform departure requires a current definition and pose"
	var old_direction: int = state.frog.direction
	var old_y: int = state.frog.target_y
	var selection: PlatformJumpResult = TerrainPlatform.prepare_jump(state, definition, pose, frog.grid, frog.controller_directions, input, is_super, distance, forced)
	if not selection.error.is_empty():
		return selection.error
	if selection.blocked:
		state.requests.animation_requests += 1
		frog.request_animation(FrogAnimationCatalog.OUCH, state)
		events.append(TickEvent.make(TickEvent.Kind.OUCH))
		return ""
	if not selection.moved:
		return ""
	if selection.detach:
		detach_platform(frog, state, events)
		if not frog.callback_error.is_empty():
			return frog.callback_error
	state.frog.mode = FrogMode.JUMPING
	state.frog.remaining_ticks = 15 if is_super else 3 if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else 6
	if duration != 0:
		state.frog.remaining_ticks = duration
	state.frog.old_y = old_y
	if is_super:
		state.frog.flags |= FrogFlags.SUPERJUMP
	var origin: Vector3i = state.attachment.entity_offset_16 if state.attachment.current_entity_index >= 0 and not state.frog.flags & FrogFlags.JUMP_TO_LAND else state.frog.position_16
	state.frog.velocity_16.x = PlatformMath.divide(state.frog.target_16.x - origin.x, state.frog.remaining_ticks)
	state.frog.velocity_16.z = PlatformMath.divide(state.frog.target_16.z - origin.z, state.frog.remaining_ticks)
	state.frog.velocity_16.y = PlatformMath.divide((state.frog.target_y - state.frog.matrix12[10]) << 16, state.frog.remaining_ticks + 1) - ((Frog.GRAVITY_16 * (state.frog.remaining_ticks + 1)) >> 1)
	var roll: bool = old_direction == state.frog.direction and state.frog.buffered_input_count > 3 and not is_super and not state.frog.powerup_flags & (PowerupFlags.QUICK_JUMP | PowerupFlags.AUTO_HOP)
	if roll:
		state.frog.buffered_input_count = 0
	var sound_issue: String = frog.play_sound(state, 7 if is_super else 6, 0 if is_super else (state.tick_index & 3) << 7)
	if not sound_issue.is_empty():
		return sound_issue
	state.requests.animation_requests += 1
	frog.request_animation(FrogAnimationCatalog.SUPERJUMP if is_super else FrogAnimationCatalog.SUPERHOP if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else FrogAnimationCatalog.AUTOHOP if state.frog.powerup_flags & PowerupFlags.AUTO_HOP else FrogAnimationCatalog.ROLL if roll else FrogAnimationCatalog.HOP, state)
	state.requests.sound_requests += 1
	events.append(TickEvent.make(TickEvent.Kind.SUPER_HOP) if is_super else TickEvent.make(TickEvent.Kind.QUICK_HOP) if state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else TickEvent.make(TickEvent.Kind.AUTO_HOP) if state.frog.powerup_flags & PowerupFlags.AUTO_HOP else TickEvent.make(TickEvent.Kind.ROLL) if roll else TickEvent.make(TickEvent.Kind.HOP))
	events.append(TickEvent.make(TickEvent.Kind.HOP_SOUND))
	if is_super or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP or not state.frog.powerup_flags & PowerupFlags.AUTO_HOP:
		state.requests.score_requests += 1
		var reward_issue: String = GameplayRewards.apply(frog.rewards[1 if is_super else 3 if roll or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else 0], state, events, frog.random)
		if not reward_issue.is_empty():
			return reward_issue
		events.append(TickEvent.make(TickEvent.Kind.SCORE_10_REQUEST) if is_super else TickEvent.make(TickEvent.Kind.SCORE_50_REQUEST) if roll or state.frog.powerup_flags & PowerupFlags.QUICK_JUMP else TickEvent.make(TickEvent.Kind.SCORE_5_REQUEST))
	return ""


## Advances an attached jump and handles landing or departure. A hop-off that finds no
## land enters freefall with old_y set to the jump's reference height, as frozen
## FROG_MOVEMENT_CALLBACK_UPDATE_OLD_POS does after block_15.
func move_platform_jumping(frog: Frog, state: GameplayState, events: Array[TickEvent], react_on_land: bool) -> void:
	var pose: EntitySnapshot = platform_pose(frog, state)
	state.frog.remaining_ticks -= 1
	if state.frog.remaining_ticks > 0:
		platform_freefall(frog, state, pose, events)
		return
	if state.frog.flags & (FrogFlags.JUMP_FROM_ENTITY | FrogFlags.JUMP_TO_ENTITY) == (FrogFlags.JUMP_FROM_ENTITY | FrogFlags.JUMP_TO_ENTITY):
		var definition: FormContactDefinition = platform_definition(frog, state)
		state.frog.flags = (state.frog.flags & ~TerrainPlatform.LANDED_CLEAR) | FrogFlags.ON_ENTITY
		state.frog.mode = FrogMode.STATIONARY
		state.requests.animation_requests += 1
		frog.request_animation(FrogAnimationCatalog.PANT, state)
		state.attachment.entity_offset_16 = state.frog.target_16
		state.attachment.entity_transform12 = PlatformMath.project(PlatformMath.multiply(state.frog.matrix12, PlatformMath.transpose(pose.matrix12)))
		state.frog.position_16 = PlatformMath.world(pose.matrix12, state.attachment.entity_offset_16) * 65536
		state.frog.velocity_16 = Vector3i.ZERO
		var flags: int = definition.grid_flags[state.attachment.entity_cell.y * definition.dimensions.x + state.attachment.entity_cell.x]
		frog.react_fall(state, state.frog.world_position.y - state.frog.old_y, flags, events)
		frog.update_world(state)
		frog.update_matrix(state)
		if react_on_land:
			frog.react(state, flags, events)
		state.frog.old_position_16 = state.frog.position_16
		return
	if state.frog.flags & FrogFlags.JUMP_TO_LAND:
		if not state.frog.flags & FrogFlags.JUMP_FROM_ENTITY:
			state.frog.position_16.x = state.frog.target_16.x
			state.frog.position_16.z = state.frog.target_16.z
		detach_platform(frog, state, events)
		frog.land(state, events)
		frog.update_world(state)
		frog.update_matrix(state)
		if react_on_land:
			frog.react(state, frog.grid.squares[state.frog.square_index].flags, events)
		state.frog.old_position_16 = state.frog.position_16
		return
	platform_freefall(frog, state, pose, events)
	detach_platform(frog, state, events)
	if state.frog.square_index < 0:
		var stack: GridStackDefinition = frog.grid.stack_at(state.frog.cell)
		if stack == null:
			frog.callback_error = "Source platform final-hop stack lookup lies outside authored storage"
			return
		for index: int in range(stack.first_square_index + stack.square_count - 1, stack.first_square_index - 1, -1):
			if frog.grid.squares[index].flags & GridSquareFlags.USABLE and GridQueries.square_height(frog.grid.squares[index]) >= state.frog.world_position.y:
				state.frog.square_index = index
				break
	state.frog.flags = (state.frog.flags & ~TerrainPlatform.LANDED_CLEAR) | FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION
	state.frog.remaining_ticks = 0x7FFFFFF
	state.frog.velocity_16.x = 0
	state.frog.velocity_16.z = 0
	state.frog.old_y = state.frog.target_y
	frog.update_world(state)
	state.frog.old_position_16 = state.frog.position_16


## Starts freefall after a platform departure.
func platform_freefall(frog: Frog, state: GameplayState, pose: EntitySnapshot, events: Array[TickEvent]) -> void:
	state.frog.velocity_16.y += Frog.GRAVITY_16
	if state.frog.flags & (FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION) == (FrogFlags.FREEFALL | FrogFlags.FREEFALL_NO_ANIMATION) and state.frog.world_position.y - state.frog.old_y >= 0:
		state.requests.animation_requests += 1
		frog.request_animation(FrogAnimationCatalog.FREEFALL if frog.map_index >= 42 and frog.map_index <= 47 else FrogAnimationCatalog.FALLING, state)
		state.frog.flags &= ~FrogFlags.FREEFALL_NO_ANIMATION
		events.append(TickEvent.make(TickEvent.Kind.FALLING))
	if not state.frog.flags & FrogFlags.JUMP_TO_LAND:
		TerrainPlatform.airborne(state, pose)
	else:
		state.frog.position_16 += state.frog.velocity_16

