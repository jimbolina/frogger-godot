class_name EntityBeaver
extends RefCounted
## Source path-gap chase, bite and dive state machine.

enum Mode { SWIMMING, WAITING_FIRST, WAITING_END, WAITING_GAP, FINISHING_BITE, DIVING }

## Updates a candidate using the authored path-neighbor order and advanced paths.
static func update(definition: EntityDefinition, result: EntityCustomResult, neighbors: Array[EntitySnapshot], definitions: Array[EntityDefinition], frog: GameplayState) -> String:
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	if definition.path_definition == null or entity.path == null or not definition.path_definition.entity_list_error.is_empty():
		return "Beaver requires a valid path and authored neighbor list"
	if entity.animation == null or entity.animation.lengths.size() < 2:
		return "Beaver requires swim and bite animation actions"
	var hit: int = -1
	var following: EntitySnapshot = null
	for neighbor: EntitySnapshot in neighbors:
		if neighbor.entity_index == custom.parent_entity_index:
			following = neighbor
	if custom.mode in [Mode.SWIMMING, Mode.FINISHING_BITE, Mode.DIVING]:
		entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
	if custom.mode in [Mode.SWIMMING, Mode.WAITING_FIRST, Mode.WAITING_END, Mode.WAITING_GAP]:
		for authored_index: int in definition.path_definition.entity_indices:
			if authored_index == definition.entity_index:
				continue
			var slot: int = -1
			for index: int in neighbors.size():
				if neighbors[index].entity_index == authored_index:
					slot = index
					break
			if slot < 0 or slot >= definitions.size() or neighbors[slot].path == null:
				return "Beaver path neighbor %d is missing its path dependency" % authored_index
			var delta := Vector3i.ZERO
			for axis: int in 3:
				delta[axis] = PlatformMath.s16(entity.matrix12[9 + axis] - neighbors[slot].path.position[axis])
			var squared: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
			if squared < 1000 + definitions[slot].radius_squared:
				hit = authored_index
				break
	match custom.mode:
		Mode.WAITING_FIRST:
			result.path_active_request = 0
			custom.model_hidden = true
			if hit >= 0:
				custom.parent_entity_index = hit
				custom.mode = Mode.WAITING_END
		Mode.WAITING_END:
			if hit < 0:
				custom.delay = definition.authored_delay & 65535
				custom.mode = Mode.WAITING_GAP
		Mode.WAITING_GAP:
			var expired: bool = custom.delay == 0
			custom.delay = (custom.delay - 1) & 65535
			if expired:
				custom.mode = Mode.SWIMMING
				entity.animation.one_shot = false
				entity.animation.select(0)
				result.path_active_request = 1
				if custom.moving_sound.is_empty():
					custom.moving_sound = PackedInt32Array([19, 1024, 2048])
					entity.requests.append(TickEvent.moving_sound(19, 1024, 2048))
			elif hit >= 0 and hit != custom.parent_entity_index:
				custom.mode = Mode.WAITING_FIRST
		Mode.SWIMMING:
			custom.model_hidden = false
			if following == null:
				return "Beaver has no resolved chase target"
			if not following.live:
				custom.mode = Mode.WAITING_FIRST
				result.path_reset_requested = true
			elif hit == custom.parent_entity_index:
				custom.mode = Mode.DIVING
				custom.delay = 30
				if frog != null and frog.attachment.current_entity_index == custom.parent_entity_index:
					var delta := Vector3i.ZERO
					for axis: int in 3:
						delta[axis] = PlatformMath.s32(frog.frog.matrix12[9 + axis] - entity.matrix12[9 + axis])
					var squared: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
					if int(sqrt(maxi(0, squared))) < 262:
						entity.animation.select(1)
						entity.animation.one_shot = true
						result.death_animation = FrogAnimationCatalog.BITTEN
						custom.timer = 20
						custom.mode = Mode.FINISHING_BITE
				if custom.mode != Mode.FINISHING_BITE:
					custom.count = 0
		Mode.FINISHING_BITE:
			custom.timer = (custom.timer - 1) & 65535
			if custom.timer == 0:
				custom.mode = Mode.WAITING_FIRST
				result.path_reset_requested = true
		Mode.DIVING:
			var expired: bool = custom.delay == 0
			custom.delay = (custom.delay - 1) & 65535
			if expired:
				custom.mode = Mode.WAITING_FIRST
				result.path_reset_requested = true
				entity.live_flags &= ~EntityLiveFlags.NO_SCREEN_FADE
			else:
				custom.count = (custom.count + 4) & 65535
				entity.matrix12[10] += custom.count
				var height: int = entity.path.position.y - entity.matrix12[10]
				entity.colour_scale = Vector3i(maxi(0, 128 + height) & 255, maxi(0, 128 - (height >> 1)) & 255, maxi(0, 128 - (height << 1)) & 255)
				entity.ambient = Vector3i(64, 64, 192)
				entity.live_flags |= EntityLiveFlags.NO_SCREEN_FADE
	return ""
