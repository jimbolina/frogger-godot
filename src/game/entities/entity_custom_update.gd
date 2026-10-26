class_name EntityCustomUpdate
extends RefCounted
## Dispatches resolved custom behavior on private candidate state.

## Updates one entity without publishing partial effects on failure.
static func update(definition: EntityDefinition, previous: EntitySnapshot, environment: EntityEnvironmentState, random: SourceRandom, frog_position: Vector3i, hit: bool, parent_live: bool, parent: EntitySnapshot = null, parent_form: FormContactDefinition = null, frog: GameplayState = null) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	if not definition.behavior.has_custom_update() or environment == null or not environment.validate().is_empty():
		result.error = "Custom background update lacks admitted environment"
		return result
	if hit and definition.behavior.execution != EntityBehavior.Execution.CONTACT:
		result.error = "Contact with an excluded custom neighbor is unsupported"
		return result
	result.entity = previous.copy()
	result.environment = environment.copy()
	result.random = random.copy()
	var issue: String = ""
	match definition.behavior.kind:
		EntityBehavior.Kind.BONUS_FLY:
			issue = EntityFly.update(definition, result)
		EntityBehavior.Kind.BABY_FROG:
			issue = EntityBaby.update_custom(definition, result.entity, parent_live, parent, parent_form, frog, hit)
		EntityBehavior.Kind.CHECKPOINT:
			issue = EntityCheckpoint.update(result.entity, frog_position)
		EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT:
			pass
		_:
			issue = "Unsupported custom behavior kind"
	if not issue.is_empty():
		result = EntityCustomResult.new()
		result.error = issue
	return result
