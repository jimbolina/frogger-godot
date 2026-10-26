class_name EntityBaby
extends RefCounted
## Frozen pink frog search, autonomous hops, pickup and riding behavior.

enum Mode { SEARCHING, ON_ENTITY, JUMPING, ON_FROG, NOTHING, WAIT_TO_SEARCH_AGAIN }

## Advances one privately owned baby against the parent's pose at this live-list visit.
static func update(entity: EntitySnapshot, parent: EntitySnapshot, form: FormContactDefinition, frog: RunSnapshot = null, hit: bool = false) -> String:
	var state: EntityCustomState = entity.background
	if parent == null or form == null or form.dimensions.x <= 0 or form.dimensions.y <= 0:
		return "Baby requires a resolved authored parent and FORM"
	entity.requests.clear()
	match state.mode:
		Mode.SEARCHING:
			if parent.live:
				state.search_count += 1
				if state.search_count >= 2:
					state.search_count = 0
					state.parent_entity_index = parent.entity_index
					state.direction = 0
					state.cell = Vector2i.ZERO
					state.count = 0
					state.delay = 30
					state.velocity_16 = Vector3i.ZERO
					state.offset_16 = Vector3i((form.offsets.x + 128) << 16, (form.height - 30) << 16, (form.offsets.y + 128) << 16)
					state.mode = Mode.ON_ENTITY
					entity.animation.select(1)
				else:
					state.mode = Mode.WAIT_TO_SEARCH_AGAIN
		Mode.WAIT_TO_SEARCH_AGAIN:
			if not parent.live:
				state.mode = Mode.SEARCHING
		Mode.ON_ENTITY:
			if not parent.live:
				state.mode = Mode.SEARCHING
				state.parent_entity_index = -1
				state.delay = 0
				state.search_count = 0
			else:
				var expired: bool = state.delay == 0
				state.delay -= 1
				if expired:
					var issue: String = _hop(entity, form)
					if not issue.is_empty():
						return issue
		Mode.JUMPING:
			state.count -= 1
			if state.count == 0:
				state.offset_16 = Vector3i(state.target.x << 16, state.target.y << 16, state.target.z << 16)
				state.velocity_16 = Vector3i.ZERO
				state.mode = Mode.ON_ENTITY
				state.delay = 30
				entity.animation.select(1)
			else:
				state.offset_16 += state.velocity_16
		Mode.ON_FROG:
			if frog == null or state.carrier_index != 0:
				return "Pink frog requires its single-player carrier"
			state.direction = 0
			if state.carried_jump_ticks != 0:
				state.carried_jump_ticks -= 1
			if frog.mode == FrogMode.DYING and not state.dead:
				state.dead = true
				state.model_hidden = true
				state.mode = Mode.NOTHING
				entity.requests.append(TickEvent.make(TickEvent.Kind.DEATH_PGEN))
			if frog.mode == FrogMode.JUMPING and state.carried_jump_ticks == 0:
				entity.animation.select(0)
				state.carried_jump_ticks = 6
		Mode.NOTHING:
			state.model_hidden = true
			return ""
		_:
			return "Unsupported pink frog mode"
	if hit and state.mode != Mode.ON_FROG:
		if frog == null:
			return "Pink frog pickup requires its single-player carrier"
		state.offset_16 = Vector3i(0, -(20 << 16), -(20 << 16))
		state.parent_entity_index = -1
		state.carrier_index = 0
		state.mode = Mode.ON_FROG
		entity.animation.select(0)
	var carrier: PackedInt32Array = frog.matrix12 if state.carrier_index == 0 and frog != null else parent.matrix12
	var has_parent: bool = state.carrier_index == 0 or (state.parent_entity_index >= 0 and parent.live)
	state.model_hidden = state.dead or not has_parent
	if has_parent:
		var world: Vector3i = PlatformMath.world(carrier, state.offset_16)
		entity.matrix12 = PlatformMath.multiply(carrier, PlatformMath.yaw(state.direction * 1024))
		entity.matrix12[9] = world.x
		entity.matrix12[10] = world.y
		entity.matrix12[11] = world.z
	return ""

static func _hop(entity: EntitySnapshot, form: FormContactDefinition) -> String:
	var state: EntityCustomState = entity.background
	var directions: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var destination: Vector2i = state.cell + directions[state.direction]
	var bounds := Rect2i(Vector2i.ZERO, form.dimensions)
	if not bounds.has_point(destination):
		state.direction = (state.direction + 2) & 3
		destination = state.cell + directions[state.direction]
	if not bounds.has_point(destination):
		return "Baby FORM has no legal autonomous hop"
	var index: int = destination.y * form.dimensions.x + destination.x
	if index >= form.grid_flags.size() or not form.grid_flags[index] & GridSquareFlags.USABLE:
		return "Baby autonomous hop requires a usable FORM cell"
	state.cell = destination
	state.target = Vector3i(destination.x * 256 + form.offsets.x + 128, form.height - 30, destination.y * 256 + form.offsets.y + 128)
	state.count = 6
	state.velocity_16 = Vector3i(PlatformMath.divide((state.target.x << 16) - state.offset_16.x, 6), -((0x100000 * 7) >> 1), PlatformMath.divide((state.target.z << 16) - state.offset_16.z, 6))
	state.mode = Mode.JUMPING
	entity.animation.select(0)
	if state.moving_sound.is_empty():
		state.moving_sound = PackedInt32Array([27, 768, 1536])
		entity.requests.append(TickEvent.moving_sound(27, 768, 1536))
	return ""

## Advances the supported baby-frog update with optional parent and contact state.
static func update_custom(definition: EntityDefinition, entity: EntitySnapshot, parent_live: bool, parent: EntitySnapshot, parent_form: FormContactDefinition, frog: RunSnapshot, hit: bool) -> String:
	if parent != null:
		var issue: String = EntityBaby.update(entity, parent, parent_form, frog if (definition.behavior.execution == EntityBehavior.Execution.CONTACT) else null, hit)
		if not issue.is_empty():
			return issue
		return ""
	if not parent_live or entity.background.mode not in [Mode.SEARCHING, Mode.WAIT_TO_SEARCH_AGAIN]:
		return "Baby parent lifetime no longer satisfies admission"
	if entity.background.mode == Mode.SEARCHING:
		entity.background.search_count += 1
		entity.background.mode = Mode.WAIT_TO_SEARCH_AGAIN
	entity.background.model_hidden = true
	return ""
