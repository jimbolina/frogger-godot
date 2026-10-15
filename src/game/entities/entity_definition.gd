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
var bonus_callback: int = 0
var flags: int = 0
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var path_definition: PathDefinition = null
var path_start: PathStart = null
## Null preserves the earlier script-free transform API.
var script_definition: EntityScriptDefinition = null
var action_lengths: PackedInt32Array = PackedInt32Array()
var animation_one_shot: bool = false
## Enables only the source-proved all-attached background branches.
var background_admitted: bool = false
var parent_unique_id: int = -1

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
	result.bonus_callback = bonus_callback
	result.flags = flags
	result.matrix12 = matrix12.duplicate()
	result.path_definition = path_definition.copy() if path_definition != null else null
	result.path_start = path_start.copy() if path_start != null else null
	result.script_definition = script_definition.copy() if script_definition != null else null
	result.action_lengths = action_lengths.duplicate()
	result.animation_one_shot = animation_one_shot
	result.background_admitted = background_admitted
	result.parent_unique_id = parent_unique_id
	return result
