class_name EntityBehaviorCatalog
extends RefCounted
## Resolves supplied FrogLord entity names to existing implementations once at setup.

const KINDS: Dictionary[String, EntityBehavior.Kind] = {
	"STATIC": EntityBehavior.Kind.STATIC,
	"MOVING": EntityBehavior.Kind.PATH_FOLLOWER,
	"SUB_TURTLE": EntityBehavior.Kind.TURTLE,
	"ORG_BABY_FROG": EntityBehavior.Kind.BABY_FROG,
	"ORG_FLY": EntityBehavior.Kind.BONUS_FLY,
	"CHECKPOINT": EntityBehavior.Kind.CHECKPOINT,
	"STATIC_NOISE": EntityBehavior.Kind.STATIC_NOISE,
	"GEN_TOP_LEFT": EntityBehavior.Kind.BOUNDS_TOP_LEFT,
	"GEN_BOTTOM_RIGHT": EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT,
}

## Unknown names resolve to UNKNOWN; the caller reports and omits unsupported records.
static func resolve(name: String) -> EntityBehavior:
	var result := EntityBehavior.new()
	result.kind = KINDS.get(name, EntityBehavior.Kind.UNKNOWN)
	if result.kind == EntityBehavior.Kind.UNKNOWN:
		return result
	result.layout = EntityBehavior.Layout.PATH if result.kind in [EntityBehavior.Kind.PATH_FOLLOWER, EntityBehavior.Kind.TURTLE] else EntityBehavior.Layout.MATRIX
	result.immortal = result.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT]
	result.group_moving = result.layout == EntityBehavior.Layout.PATH or result.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY]
	result.one_shot = result.kind == EntityBehavior.Kind.BABY_FROG
	if result.kind == EntityBehavior.Kind.TURTLE:
		result.payload_offset = 12
		result.payload_register_count = 3
	elif result.kind == EntityBehavior.Kind.STATIC_NOISE:
		result.payload_offset = 32
		result.payload_register_count = 2
	return result
