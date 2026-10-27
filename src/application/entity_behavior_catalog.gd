class_name EntityBehaviorCatalog
extends RefCounted
## Resolves supplied FrogLord entity names to existing implementations once at setup.

const KINDS: Dictionary[String, EntityBehavior.Kind] = {
	"ORG_CROC_HEAD": EntityBehavior.Kind.CROC_HEAD,
	"GEN_GOLD_FROG": EntityBehavior.Kind.GOLD_FROG,
	"ORG_LOG_SNAKE": EntityBehavior.Kind.LOG_SNAKE,
	"ORG_BEAVER": EntityBehavior.Kind.BEAVER,
	"STATIC": EntityBehavior.Kind.STATIC,
	"DYNAMIC": EntityBehavior.Kind.STATIC,
	"MOVING_TONGUEABLE": EntityBehavior.Kind.PATH_FOLLOWER,
	"SUB_DOG": EntityBehavior.Kind.DOG,
	"MOVING": EntityBehavior.Kind.PATH_FOLLOWER,
	"SUB_TURTLE": EntityBehavior.Kind.TURTLE,
	"ORG_BABY_FROG": EntityBehavior.Kind.BABY_FROG,
	"ORG_FLY": EntityBehavior.Kind.BONUS_FLY,
	"BONUS_FLY": EntityBehavior.Kind.PICKUP,
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
	result.layout = EntityBehavior.Layout.PATH if result.kind in [EntityBehavior.Kind.PATH_FOLLOWER, EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG] else EntityBehavior.Layout.MATRIX
	result.immortal = name == "DYNAMIC" or result.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER]
	result.group_moving = name == "DYNAMIC" or result.layout == EntityBehavior.Layout.PATH or result.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER]
	result.tongueable = name == "MOVING_TONGUEABLE" or result.kind in [EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.PICKUP]
	result.one_shot = result.kind == EntityBehavior.Kind.BABY_FROG
	if result.kind == EntityBehavior.Kind.TURTLE:
		result.payload_offset = 12
		result.payload_register_count = 3
	elif result.kind == EntityBehavior.Kind.STATIC_NOISE:
		result.payload_offset = 32
		result.payload_register_count = 2
	return result
