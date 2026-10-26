class_name EntityBackground
extends RefCounted
## Source-proved background branches; unsupported interactions reject explicitly.

## Advances an excluded neighbor without suppressing its logical global effects.
static func update(definition: EntityDefinition, previous: EntitySnapshot, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool, parent_live: bool, parent: EntitySnapshot = null, parent_form: FormContactDefinition = null, frog: RunSnapshot = null) -> EntityBackgroundResult:
	var result := EntityBackgroundResult.new()
	if not definition.background_admitted or environment == null or not environment.validate().is_empty():
		result.error = "Custom background update lacks admitted environment"
		return result
	if hit and not definition.pink_frog_pickup:
		result.error = "Contact with an excluded custom neighbor is unsupported"
		return result
	result.entity = previous.copy()
	result.environment = environment.copy()
	result.random = random.copy()
	var entity: EntitySnapshot = result.entity
	match definition.entity_name:
		"ORG_FLY":
			var custom: EntityBackgroundState = entity.background
			var expired: bool = custom.timer == 0
			custom.timer -= 1
			if expired:
				if custom.mode == 0:
					if result.environment.covered != 0:
						result.error = "Fly requires the admitted uncollected checkpoint state"
						return _failed(result.error)
					custom.checkpoint_index = result.random.next_value("entity:%d:checkpoint" % definition.entity_index) % 5
					var point: Vector3i = environment.checkpoint_positions[custom.checkpoint_index]
					entity.matrix12[9] = point.x
					entity.matrix12[10] = _short(point.y - 256)
					entity.matrix12[11] = _short(point.z - 50)
					result.environment.covered |= 1 << custom.checkpoint_index
					entity.entity_flags &= ~(EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION)
					custom.model_hidden = false
					custom.mode = 1
					custom.timer = 120
				else:
					result.environment.covered &= ~(1 << custom.checkpoint_index)
					custom.checkpoint_index = -1
					custom.mode = 0
					custom.timer = 60
					entity.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
		"ORG_BABY_FROG":
			if parent != null:
				var issue: String = EntityBaby.update(entity, parent, parent_form, frog if definition.pink_frog_pickup else null, hit)
				if not issue.is_empty():
					return _failed(issue)
				return result
			if not parent_live or entity.background.mode not in [0, 5]:
				return _failed("Baby parent lifetime no longer satisfies admission")
			if entity.background.mode == 0:
				entity.background.search_count += 1
				entity.background.mode = 5
			entity.background.model_hidden = true
		"CHECKPOINT":
			var dx: int = frog_position.x - entity.matrix12[9]
			var dz: int = frog_position.z - entity.matrix12[11]
			if dx * dx + dz * dz <= 512 * 512:
				return _failed("Checkpoint croak interaction is outside admitted background behavior")
		"STATIC_NOISE", "GEN_TOP_LEFT", "GEN_BOTTOM_RIGHT":
			pass
		_:
			return _failed("Unsupported custom background name")
	return result

static func _failed(reason: String) -> EntityBackgroundResult:
	var result := EntityBackgroundResult.new()
	result.error = reason
	return result

static func _short(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low
