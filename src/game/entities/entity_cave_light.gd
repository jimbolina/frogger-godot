class_name EntityCaveLight
extends RefCounted
## Frozen frogger-light creation seeding and per-tick crop/decay of the shared radii.

## Source distance between the light's maximum and minimum squared radii.
const BAND: int = 0x100000
const UNSIGNED32: int = 0xffffffff

## Turns the light switch on and seeds the shared environment radii from the precomputed maximum.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot, environment: EntityEnvironmentState) -> void:
	entity.animation = null
	entity.live_flags = 0
	if environment != null:
		environment.light_switch = true
	if definition.cave != null and environment != null:
		_set_maximum(environment, definition.cave.light_max_squared)

## While the light switch is on, crops an enlarged light back to its maximum, then decays it toward the minimum.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	if definition.cave == null:
		return "Cave light update requires its precomputed radii"
	if result.environment == null:
		return "Cave light update requires the candidate entity environment"
	var cave: EntityCaveDefinition = definition.cave
	var environment: EntityEnvironmentState = result.environment
	if not environment.light_switch:
		return ""
	if environment.light_max_squared > cave.light_max_squared:
		_set_maximum(environment, cave.light_max_squared)
	if environment.light_max_squared > cave.light_min_squared:
		_set_maximum(environment, environment.light_max_squared - cave.light_die)
	return ""

static func _set_maximum(environment: EntityEnvironmentState, maximum: int) -> void:
	environment.light_max_squared = maximum & UNSIGNED32
	var minimum: int = (environment.light_max_squared - BAND) & UNSIGNED32
	environment.light_min_squared = 1 if minimum > environment.light_max_squared else minimum
