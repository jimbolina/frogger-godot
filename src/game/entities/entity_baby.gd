class_name EntityBaby
extends RefCounted
## Frozen uncollected ORG baby search, parent loss and autonomous FORM hops.

## Advances one privately owned baby against the parent's pose at this live-list visit.
static func update(entity: EntitySnapshot, parent: EntitySnapshot, form: FormContactDefinition) -> String:
	var state: EntityBackgroundState = entity.background
	if parent == null or form == null or form.dimensions.x <= 0 or form.dimensions.y <= 0:
		return "Baby requires a resolved authored parent and FORM"
	entity.requests.clear()
	match state.mode:
		0:
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
					state.mode = 1
					entity.animation.select(1)
				else:
					state.mode = 5
		5:
			if not parent.live:
				state.mode = 0
		1:
			if not parent.live:
				state.mode = 0
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
		2:
			state.count -= 1
			if state.count == 0:
				state.offset_16 = Vector3i(state.target.x << 16, state.target.y << 16, state.target.z << 16)
				state.velocity_16 = Vector3i.ZERO
				state.mode = 1
				state.delay = 30
				entity.animation.select(1)
			else:
				state.offset_16 += state.velocity_16
		_:
			return "Collected baby behavior is outside guarded exploration"
	state.model_hidden = state.parent_entity_index < 0 or not parent.live
	if not state.model_hidden:
		var world: Vector3i = PlatformMath.world(parent.matrix12, state.offset_16)
		entity.matrix12 = PlatformMath.multiply(parent.matrix12, PlatformMath.yaw(state.direction * 1024))
		entity.matrix12[9] = world.x
		entity.matrix12[10] = world.y
		entity.matrix12[11] = world.z
	return ""

static func _hop(entity: EntitySnapshot, form: FormContactDefinition) -> String:
	var state: EntityBackgroundState = entity.background
	var directions: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var destination: Vector2i = state.cell + directions[state.direction]
	var bounds := Rect2i(Vector2i.ZERO, form.dimensions)
	if not bounds.has_point(destination):
		state.direction = (state.direction + 2) & 3
		destination = state.cell + directions[state.direction]
	if not bounds.has_point(destination):
		return "Baby FORM has no legal autonomous hop"
	var index: int = destination.y * form.dimensions.x + destination.x
	if index >= form.grid_flags.size() or not form.grid_flags[index] & 1:
		return "Baby autonomous hop requires a usable FORM cell"
	state.cell = destination
	state.target = Vector3i(destination.x * 256 + form.offsets.x + 128, form.height - 30, destination.y * 256 + form.offsets.y + 128)
	state.count = 6
	state.velocity_16 = Vector3i(PlatformMath.divide((state.target.x << 16) - state.offset_16.x, 6), -((0x100000 * 7) >> 1), PlatformMath.divide((state.target.z << 16) - state.offset_16.z, 6))
	state.mode = 2
	entity.animation.select(0)
	if state.moving_sound.is_empty():
		state.moving_sound = PackedInt32Array([27, 768, 1536])
		entity.requests.append("moving:27:768:1536")
	return ""
