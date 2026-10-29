class_name CollisionTransposeCache
extends RefCounted
## The source's global MRColl_lw_ptr/MRColl_matrix_ptr/MRColl_transmatrix cache.
## Game code never resets it: the collision rotation is rebuilt only when the
## frame or primitive matrix identity changes, so a recurring identity reuses
## a rotation computed from earlier contents.

## Identities are colon-joined, such as "lw:3:1:4"; an empty matrix key means none.
var frame_key: String = ""
var matrix_key: String = ""
var rotation9: PackedInt32Array = PackedInt32Array()

## Frame identity: the authored map matrix of a stationary MOF, the live
## entity matrix of each creation, or one part of an animated environment's
## stored LW array of each creation.
static func frame_key_for(stationary: bool, animated: bool, entity_index: int, generation: int, part_index: int) -> String:
	if animated:
		return "lw:%d:%d:%d" % [entity_index, generation, part_index]
	if stationary:
		return "map:%d" % entity_index
	return "live:%d:%d" % [entity_index, generation]

## Primitive matrix identity inside its shared source model, or none.
static func matrix_key_for(primitive: EntityPrimitiveDefinition) -> String:
	if primitive.matrix_index < 0:
		return ""
	return "%d:%d:%d" % [primitive.model_resource_id, primitive.part_index, primitive.matrix_index]

## Whether frozen ENTSTRCreateStationaryMOF points the live matrix at the map entity.
static func is_stationary(entity: EntityDefinition) -> bool:
	return entity != null and entity.behavior != null and entity.behavior.kind == EntityBehavior.Kind.STATIC and not entity.is_group_moving()

## Returns the cached rotation, recomputing it from the current frame and
## primitive only when either identity differs from the previous check.
func resolve(next_frame_key: String, next_matrix_key: String, frame12: PackedInt32Array, primitive: EntityPrimitiveDefinition) -> PackedInt32Array:
	if rotation9.size() != 9 or next_frame_key != frame_key or next_matrix_key != matrix_key:
		frame_key = next_frame_key
		matrix_key = next_matrix_key
		rotation9 = EntityPrimitiveQuery.collision_rotation(frame12, primitive)
	return rotation9

## Detaches the cache for an unpublished candidate tick.
func copy() -> CollisionTransposeCache:
	var result := CollisionTransposeCache.new()
	result.frame_key = frame_key
	result.matrix_key = matrix_key
	result.rotation9 = rotation9.duplicate()
	return result
