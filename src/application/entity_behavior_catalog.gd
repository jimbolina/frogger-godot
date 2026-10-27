class_name EntityBehaviorCatalog
extends RefCounted
## Resolves supplied FrogLord entity names to existing implementations once at setup.

const KINDS: Dictionary[String, EntityBehavior.Kind] = {
	"MOVING_PLATFORM": EntityBehavior.Kind.MOVING_PLATFORM,
	"VOL_COLOUR_SWITCH": EntityBehavior.Kind.VOL_COLOUR_SWITCH,
	"VOL_FALLING_PLATFORM": EntityBehavior.Kind.VOL_FALLING_PLATFORM,
	"FOR_HIVE": EntityBehavior.Kind.HIVE,
	"FOR_BREAKING_BRANCH": EntityBehavior.Kind.BREAKING_BRANCH,
	"FOR_SQUIRREL": EntityBehavior.Kind.SQUIRREL,
	"FOR_HEDGEHOG": EntityBehavior.Kind.HEDGEHOG,
	"FOR_SWAYING_BRANCH": EntityBehavior.Kind.STATIC,
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
	"CAV_FROGGER_LIGHT": EntityBehavior.Kind.CAVE_LIGHT,
	"FIREFLY": EntityBehavior.Kind.FIREFLY,
	"CAV_FAT_FIRE_FLY": EntityBehavior.Kind.FAT_FIRE_FLY,
}

## Unknown names resolve to UNKNOWN; the caller reports and omits unsupported records.
static func resolve(name: String) -> EntityBehavior:
	var result := EntityBehavior.new()
	result.kind = KINDS.get(name, EntityBehavior.Kind.UNKNOWN)
	if result.kind == EntityBehavior.Kind.UNKNOWN:
		return result
	result.layout = EntityBehavior.Layout.PATH if result.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.PATH_FOLLOWER, EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG, EntityBehavior.Kind.FIREFLY] else EntityBehavior.Layout.MATRIX
	result.immortal = name in ["DYNAMIC", "FOR_SWAYING_BRANCH"] or result.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM, EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.CAVE_LIGHT]
	result.group_moving = name in ["DYNAMIC", "FOR_SWAYING_BRANCH"] or result.layout == EntityBehavior.Layout.PATH or result.kind in [EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM, EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.CAVE_LIGHT]
	result.tongueable = name == "MOVING_TONGUEABLE" or result.kind in [EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.PICKUP, EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.FAT_FIRE_FLY]
	result.one_shot = result.kind == EntityBehavior.Kind.BABY_FROG
	if result.kind == EntityBehavior.Kind.TURTLE:
		result.payload_offset = 12
		result.payload_register_count = 3
	elif result.kind == EntityBehavior.Kind.STATIC_NOISE:
		result.payload_offset = 32
		result.payload_register_count = 2
	return result
