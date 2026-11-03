class_name EntityHive
extends RefCounted
## Forest hive swarm chase, obstruction, return and logical buzzing pitch.

enum Mode { WAITING, CHASING, MILLING, RETURNING }

## Advances a private swarm against committed source entity and terrain geometry.
## A sting that will deactivate the frog removes it from the following visibility query,
## modelling C's in-tick order after FrogKill.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, neighbors: Array[EntitySnapshot], definitions: Array[EntityDefinition], contacts: Array[FormContactDefinition], grid: GridDefinition, collision: EntityCollisionDefinition, frame_number: int) -> String:
	if definition.forest == null or result.entity.custom_state.swarm == null or frog == null:
		return "Hive requires authored operands, swarm state and a frog"
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	var swarm: EntitySwarmState = custom.swarm
	var frog_position := Vector3i(frog.frog.matrix12[9], frog.frog.matrix12[10], frog.frog.matrix12[11])
	var home := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	var stopped: bool = frog.frog.mode in [FrogMode.DYING, FrogMode.HIT_CHECKPOINT, FrogMode.NO_CONTROL]
	match custom.mode:
		Mode.WAITING:
			if frog.frog.flags & FrogFlags.ACTIVE and frog.frog.flags & FrogFlags.CONTROL_ACTIVE and frog.frog.mode != FrogMode.NO_CONTROL:
				var delta: Vector3i = home - frog_position
				var squared: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
				if int(sqrt(float(maxi(0, squared)))) < definition.forest.release_distance:
					swarm.speed = 0
					swarm.matrix12 = entity.matrix12.duplicate()
					swarm.angles = PackedInt32Array([0, 1280, 2560])
					custom.mode = Mode.CHASING
					result.environment.active_swarms += 1
		Mode.CHASING:
			if stopped:
				custom.mode = Mode.RETURNING
				return ""
			if swarm.speed < definition.forest.swarm_speed:
				swarm.speed = PlatformMath.s32(swarm.speed + 128)
			var direction: Vector3i = frog_position - _position(swarm)
			direction.y = 0
			_face(swarm, direction)
			_move(swarm)
			var issue: String = _follow_height(swarm, grid)
			if not issue.is_empty():
				return issue
			_positions(swarm, 512)
			if frog.frog.flags & FrogFlags.ACTIVE and frog.frog.mode != FrogMode.NO_CONTROL:
				var delta: Vector3i = frog_position - _position(swarm)
				if PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) <= 10000:
					result.death_animation = FrogAnimationCatalog.FLOP
					custom.mode = Mode.RETURNING
					entity.requests.append(TickEvent.sound(65))
			var query_frog: GameplayState = frog
			if result.death_animation >= 0 and Frog.kill_deactivates(frog.frog.lives, frog.cheats.infinite_lives) and not frog.frog.flags & FrogFlags.MUST_DIE:
				query_frog = frog.copy(false)
				query_frog.frog.flags &= ~FrogFlags.ACTIVE
			if ForestVisibilityQuery.first_hit(swarm.matrix12, direction, query_frog, neighbors, definitions, contacts, collision) == ForestVisibilityQuery.Hit.ENTITY:
				custom.mode = Mode.MILLING
				swarm.delay = 0
			swarm.visible = true
		Mode.MILLING:
			if stopped:
				custom.mode = Mode.RETURNING
				return ""
			swarm.speed = 0 if swarm.speed < 512 else PlatformMath.s32(swarm.speed - 256)
			var expired: bool = swarm.delay > 60
			swarm.delay = (swarm.delay + 1) & 4294967295
			if expired:
				custom.mode = Mode.RETURNING
			else:
				_move(swarm)
				var issue: String = _follow_height(swarm, grid)
				if not issue.is_empty():
					return issue
				_positions(swarm, 256)
				if ForestVisibilityQuery.first_hit(swarm.matrix12, frog_position - _position(swarm), frog, neighbors, definitions, contacts, collision) == ForestVisibilityQuery.Hit.FROG:
					custom.mode = Mode.CHASING
				swarm.visible = true
		Mode.RETURNING:
			if swarm.speed < PlatformMath.s32(definition.forest.swarm_speed << 8):
				swarm.speed = PlatformMath.s32(swarm.speed + 256)
			var direction: Vector3i = home - _position(swarm)
			_face(swarm, direction)
			_move(swarm)
			swarm.matrix12[10] = PlatformMath.s32(swarm.matrix12[10] + (swarm.matrix12[5] >> 11))
			_positions(swarm, 128)
			if absi(direction.x) < 128 and absi(direction.y) < 128 and absi(direction.z) < 128:
				var was_negative: bool = result.environment.active_swarms < 0
				result.environment.active_swarms -= 1
				if was_negative:
					result.environment.active_swarms = 0
				swarm.visible = false
				custom.mode = Mode.WAITING
	if custom.moving_voice_active:
		var standard: int = 72 - (result.random.next_value("entity:%d:hive_pitch" % definition.entity_index) & 15) + result.environment.active_swarms * 8
		var sine: int = roundi(sin(float((frame_number << 7) & 4095) * TAU / 4096.0) * 4096.0)
		entity.requests.append(TickEvent.pitch_bend(standard - (sine >> 9)))
	return ""

static func _position(swarm: EntitySwarmState) -> Vector3i:
	return Vector3i(swarm.matrix12[9], swarm.matrix12[10], swarm.matrix12[11])

static func _face(swarm: EntitySwarmState, direction: Vector3i) -> void:
	var normal: Vector3i = EntityTransform._normalise(direction)
	for axis: int in 3:
		swarm.matrix12[axis * 3 + 2] = PlatformMath.s16(normal[axis])

static func _move(swarm: EntitySwarmState) -> void:
	for axis: int in [0, 2]:
		swarm.matrix12[9 + axis] = PlatformMath.s32(swarm.matrix12[9 + axis] + (PlatformMath.s32(swarm.matrix12[axis * 3 + 2] * (swarm.speed >> 8)) >> 12))

static func _follow_height(swarm: EntitySwarmState, grid: GridDefinition) -> String:
	if grid == null:
		return "Hive requires source terrain for swarm height"
	var stack: GridStackDefinition = grid.stack_at(GridQueries.world_to_cell(grid, swarm.matrix12[9], swarm.matrix12[11]))
	if stack != null:
		var square: int = stack.first_square_index + stack.square_count - 1
		if square < 0 or square >= grid.squares.size():
			return "Swarm height resolves an unavailable source grid square"
		swarm.matrix12[10] = GridQueries.square_height(grid.squares[square])
	return ""

static func _positions(swarm: EntitySwarmState, angular_speed: int) -> void:
	for index: int in 3:
		var angle: float = float(swarm.angles[index] & 4095) * TAU / 4096.0
		var cosine: int = roundi(cos(angle) * 4096.0)
		var sine: int = roundi(sin(angle) * 4096.0)
		swarm.positions[index] = Vector3i(PlatformMath.s16(swarm.matrix12[9] + (cosine >> 7)), PlatformMath.s16(swarm.matrix12[10] - index * 64), PlatformMath.s16(swarm.matrix12[11] + (sine >> 7)))
		swarm.angles[index] = PlatformMath.s32(swarm.angles[index] + angular_speed)
