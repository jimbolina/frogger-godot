class_name EntityCrocHead
extends RefCounted
## Original checkpoint hazard with source warning, bite and reset clocks.

enum Mode { WAITING, APPEARING, APPEARED, RESET }

## Updates one private hazard before frog control and collision.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool) -> String:
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	var environment: EntityEnvironmentState = result.environment
	match custom.mode:
		Mode.WAITING:
			entity.entity_flags |= EntityDefinition.NO_COLLISION
			var expired: bool = custom.timer == 0
			custom.timer -= 1
			if expired:
				var selected: int = result.random.next_value("entity:%d:checkpoint" % definition.entity_index) % 5
				custom.timer = 60
				if not (environment.collected | environment.covered) & (1 << selected):
					if entity.animation == null or entity.animation.lengths.is_empty():
						return "Crocodile head requires animation action zero"
					custom.checkpoint_index = selected
					var point: Vector3i = environment.checkpoint_positions[selected]
					entity.matrix12 = PlatformMath.yaw(2048)
					for index: int in 9:
						entity.matrix12[index] = PlatformMath.divide(entity.matrix12[index], 4) * 3
					entity.matrix12[9] = point.x
					entity.matrix12[10] = PlatformMath.s16(point.y - 100)
					entity.matrix12[11] = PlatformMath.s16(point.z + 50)
					environment.covered |= 1 << selected
					entity.entity_flags &= ~EntityDefinition.HIDDEN
					custom.model_hidden = false
					entity.animation.select(0)
					custom.mode = Mode.APPEARING
					custom.delay = 20
		Mode.APPEARING:
			custom.timer -= 1
			if frog != null and frog.frog.mode == FrogMode.HIT_CHECKPOINT and frog.frog.flags & FrogFlags.ACTIVE:
				_reset(entity, environment)
			if custom.timer == 0:
				var rotation: PackedInt32Array = PlatformMath.yaw(2048)
				for index: int in 9:
					entity.matrix12[index] = rotation[index]
				entity.matrix12[11] -= 100
				entity.entity_flags &= ~EntityDefinition.NO_COLLISION
				environment.collision_disabled |= 1 << custom.checkpoint_index
				custom.mode = Mode.APPEARED
				custom.timer = 120
		Mode.APPEARED:
			var expired: bool = custom.timer == 0
			custom.timer -= 1
			if expired:
				_reset(entity, environment)
			else:
				custom.delay -= 1
				if custom.delay == 0:
					custom.delay = 20
					if custom.moving_sound.is_empty():
						custom.moving_sound = PackedInt32Array([98, 512, 1536])
						entity.requests.append(TickEvent.moving_sound(98, 512, 1536))
				if hit:
					result.death_animation = FrogAnimationCatalog.BITTEN
					entity.requests.append(TickEvent.sound(99))
					custom.mode = Mode.RESET
					custom.timer = 60
		Mode.RESET:
			custom.timer -= 1
			if custom.timer == 0:
				_reset(entity, environment)
	return ""

static func _reset(entity: EntitySnapshot, environment: EntityEnvironmentState) -> void:
	var custom: EntityCustomState = entity.custom_state
	entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
	custom.mode = Mode.WAITING
	custom.timer = 60
	custom.model_hidden = true
	if custom.checkpoint_index >= 0:
		environment.covered &= ~(1 << custom.checkpoint_index)
		environment.collision_disabled &= ~(1 << custom.checkpoint_index)
	custom.checkpoint_index = -1
