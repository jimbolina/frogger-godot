class_name EntityDefinition
extends RefCounted
## Detached authored entity facts for one bounded entity run.

const HIDDEN: int = 1
const NO_DISPLAY: int = 2
const NO_MOVEMENT: int = 4
const NO_COLLISION: int = 8
const ALIGN_TO_WORLD: int = 16
const PROJECT_ON_LAND: int = 32
const LOCAL_ALIGN: int = 64
const ALL_FLAGS: int = 127

var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var entity_index: int = -1
var source_offset: int = 0
var unique_id: int = 0
var form_grid_id: int = 0
var form_id: int = 0
var form_name: String = ""
var entity_name: String = ""
var script_id: int = 0
var collision_callback: int = 0
var bonus_kind: FormCallback.Kind = FormCallback.Kind.NONE
var bonus_callback: int = 0
var form_flags: int = 0
var flags: int = 0
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var path_definition: PathDefinition = null
var path_start: PathStart = null
## Null preserves the earlier script-free transform API.
var script_definition: EntityScriptDefinition = null
var action_lengths: PackedInt32Array = PackedInt32Array()
var behavior: EntityBehavior = EntityBehavior.new()
var volcano: EntityVolcanoDefinition = null
var forest: EntityForestDefinition = null
var cave: EntityCaveDefinition = null
var desert: EntityDesertDefinition = null
var jungle: EntityJungleDefinition = null
var swamp: EntitySwampDefinition = null
var trigger: EntityTriggerDefinition = null
var radius_squared: int = 0
var movement_speed: int = 0
var authored_delay: int = 0
var pickup_reward: RewardDefinition = null
var pickup_type: int = 0
var butterfly_type: int = -1
var butterfly_reward: RewardDefinition = null
var parent_unique_id: int = -1
## Presentation-only particle generators started from the model's hilites.
var particle_hilites: Array[ParticleHilite] = []

## Returns a copy with independently owned matrix and path records.
func copy() -> EntityDefinition:
	var result := EntityDefinition.new()
	result.source_id = source_id
	result.build_id = build_id
	result.resource_id = resource_id
	result.entity_index = entity_index
	result.source_offset = source_offset
	result.unique_id = unique_id
	result.form_grid_id = form_grid_id
	result.form_id = form_id
	result.form_name = form_name
	result.entity_name = entity_name
	result.script_id = script_id
	result.collision_callback = collision_callback
	result.bonus_kind = bonus_kind
	result.bonus_callback = bonus_callback
	result.form_flags = form_flags
	result.flags = flags
	result.matrix12 = matrix12.duplicate()
	result.path_definition = path_definition.copy() if path_definition != null else null
	result.path_start = path_start.copy() if path_start != null else null
	result.script_definition = script_definition.copy() if script_definition != null else null
	result.action_lengths = action_lengths.duplicate()
	result.behavior = behavior.copy() if behavior != null else null
	result.volcano = volcano.copy() if volcano != null else null
	result.forest = forest.copy() if forest != null else null
	result.cave = cave.copy() if cave != null else null
	result.desert = desert.copy() if desert != null else null
	result.jungle = jungle.copy() if jungle != null else null
	result.swamp = swamp.copy() if swamp != null else null
	result.trigger = trigger.copy() if trigger != null else null
	result.radius_squared = radius_squared
	result.movement_speed = movement_speed
	result.authored_delay = authored_delay
	result.pickup_reward = pickup_reward.copy() if pickup_reward != null else null
	result.pickup_type = pickup_type
	result.butterfly_type = butterfly_type
	result.butterfly_reward = butterfly_reward.copy() if butterfly_reward != null else null
	result.parent_unique_id = parent_unique_id
	for hilite: ParticleHilite in particle_hilites:
		result.particle_hilites.append(hilite.copy())
	return result

## Resolves the frozen entity-book immortal capability from the resolved behavior.
func is_immortal() -> bool:
	return behavior.immortal

## Resolves nonstatic map-group membership independently of path ownership.
func is_group_moving() -> bool:
	return behavior.group_moving
