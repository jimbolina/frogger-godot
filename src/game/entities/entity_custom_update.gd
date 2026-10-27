class_name EntityCustomUpdate
extends RefCounted
## Dispatches resolved custom behavior on private candidate state.

## Updates one entity without publishing partial effects on failure.
static func update(definition: EntityDefinition, previous: EntitySnapshot, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool, parent_live: bool, parent: EntitySnapshot = null, parent_form: FormContactDefinition = null, frog: GameplayState = null, neighbors: Array[EntitySnapshot] = [], definitions: Array[EntityDefinition] = [], frame_number: int = 0, grid: GridDefinition = null, collision: EntityCollisionDefinition = null, contacts: Array[FormContactDefinition] = []) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	if not definition.behavior.has_custom_update() or environment == null or not environment.validate().is_empty():
		result.error = "Custom update requires a valid entity environment"
		return result
	if hit and definition.behavior.execution != EntityBehavior.Execution.CONTACT:
		result.error = "Contact with an excluded custom neighbor is unsupported"
		return result
	result.entity = previous.copy()
	result.environment = environment.copy()
	result.random = random.copy()
	var issue: String = ""
	match definition.behavior.kind:
		EntityBehavior.Kind.VOL_COLOUR_SWITCH:
			issue = EntityVolcanoSwitch.update(definition, result)
		EntityBehavior.Kind.VOL_FALLING_PLATFORM:
			issue = EntityVolcanoFallingPlatform.update(definition, result, frog, hit)
		EntityBehavior.Kind.MOVING_PLATFORM:
			issue = EntityVolcanoMovingPlatform.update(definition, result)
		EntityBehavior.Kind.HIVE:
			issue = EntityHive.update(definition, result, frog, neighbors, definitions, contacts, grid, collision, frame_number)
		EntityBehavior.Kind.BREAKING_BRANCH:
			issue = EntityBreakingBranch.update(definition, result, frog, hit, grid)
		EntityBehavior.Kind.SQUIRREL:
			issue = EntitySquirrel.update(definition, result)
		EntityBehavior.Kind.HEDGEHOG:
			issue = EntityHedgehog.update(definition, result, grid)
		EntityBehavior.Kind.DOG:
			issue = EntityDog.update(definition, result, frog, hit)
		EntityBehavior.Kind.BEAVER:
			issue = EntityBeaver.update(definition, result, neighbors, definitions, frog)
		EntityBehavior.Kind.LOG_SNAKE:
			issue = EntityLogSnake.update(definition, result.entity, parent, parent_form)
		EntityBehavior.Kind.CROC_HEAD:
			issue = EntityCrocHead.update(definition, result, frog, hit)
		EntityBehavior.Kind.GOLD_FROG:
			EntityGoldFrog.update(result.entity, hit)
		EntityBehavior.Kind.PICKUP:
			EntityBonusFly.update(definition, result, frame_number)
		EntityBehavior.Kind.BONUS_FLY:
			issue = EntityFly.update(definition, result)
		EntityBehavior.Kind.BABY_FROG:
			issue = EntityBaby.update_custom(definition, result.entity, parent_live, parent, parent_form, frog, hit)
		EntityBehavior.Kind.CHECKPOINT:
			issue = EntityCheckpoint.update(definition, result, frog_position)
		EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT:
			pass
		_:
			issue = "Unsupported custom behavior kind"
	if not issue.is_empty():
		result = EntityCustomResult.new()
		result.error = issue
	return result
