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
	"DES_FALLING_ROCK": EntityBehavior.Kind.DES_FALLING_ROCK,
	"DES_ROLLING_ROCK": EntityBehavior.Kind.DES_ROLLING_ROCK,
	"DES_TUMBLE_WEED": EntityBehavior.Kind.DES_TUMBLE_WEED,
	"DES_SNAKE": EntityBehavior.Kind.DES_SNAKE,
	"DES_VULTURE": EntityBehavior.Kind.DES_VULTURE,
	"DES_CROC_HEAD": EntityBehavior.Kind.DES_CROC_HEAD,
	"DES_CRACK": EntityBehavior.Kind.DES_CRACK,
	"JUN_PLANT": EntityBehavior.Kind.JUN_PLANT,
	"JUN_ROPE_BRIDGE": EntityBehavior.Kind.JUN_ROPE_BRIDGE,
	"JUN_HIPPO": EntityBehavior.Kind.JUN_HIPPO,
	"JUN_SCORPION": EntityBehavior.Kind.JUN_SCORPION,
	"JUN_BOUNCY_MUSHROOM": EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM,
	"JUN_OUTRO_DOOR": EntityBehavior.Kind.JUN_OUTRO_DOOR,
	"JUN_OUTRO": EntityBehavior.Kind.JUN_OUTRO,
	"JUN_PLINTH": EntityBehavior.Kind.JUN_PLINTH,
	"JUN_GOLD_FROG": EntityBehavior.Kind.JUN_GOLD_FROG,
	"JUN_STONE_FROG": EntityBehavior.Kind.JUN_STONE_FROG,
	"SWP_SQUIRT": EntityBehavior.Kind.SWP_SQUIRT,
	"SWP_CRUSHER": EntityBehavior.Kind.SWP_CRUSHER,
	"SWP_PRESS": EntityBehavior.Kind.SWP_PRESS,
	"SWP_RAT": EntityBehavior.Kind.SWP_RAT,
	"SWP_SLUG": EntityBehavior.Kind.SWP_SLUG,
	"NUCLEAR_BARREL": EntityBehavior.Kind.NUCLEAR_BARREL,
	"SWP_STAT_WEIR": EntityBehavior.Kind.SWP_STAT_WEIR,
}

## Unknown names resolve to UNKNOWN; the caller reports and omits unsupported records.
static func resolve(name: String) -> EntityBehavior:
	var result := EntityBehavior.new()
	result.kind = KINDS.get(name, EntityBehavior.Kind.UNKNOWN)
	if result.kind == EntityBehavior.Kind.UNKNOWN:
		return result
	result.layout = EntityBehavior.Layout.PATH if result.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.PATH_FOLLOWER, EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.DOG, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.HEDGEHOG, EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.DES_ROLLING_ROCK, EntityBehavior.Kind.DES_TUMBLE_WEED, EntityBehavior.Kind.DES_SNAKE, EntityBehavior.Kind.DES_VULTURE] + EntityBehavior.JUNGLE_PATH_KINDS + EntityBehavior.SWAMP_PATH_KINDS else EntityBehavior.Layout.MATRIX
	result.immortal = name in ["DYNAMIC", "FOR_SWAYING_BRANCH"] or result.kind in [EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM, EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.STATIC_NOISE, EntityBehavior.Kind.BOUNDS_TOP_LEFT, EntityBehavior.Kind.BOUNDS_BOTTOM_RIGHT, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.CAVE_LIGHT, EntityBehavior.Kind.DES_FALLING_ROCK, EntityBehavior.Kind.DES_ROLLING_ROCK, EntityBehavior.Kind.DES_CROC_HEAD, EntityBehavior.Kind.DES_CRACK] or (result.kind in EntityBehavior.JUNGLE_KINDS and result.kind not in EntityBehavior.JUNGLE_PATH_KINDS + [EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM]) or result.kind in EntityBehavior.SWAMP_KINDS
	result.group_moving = name in ["DYNAMIC", "FOR_SWAYING_BRANCH"] or result.layout == EntityBehavior.Layout.PATH or result.kind in [EntityBehavior.Kind.VOL_COLOUR_SWITCH, EntityBehavior.Kind.VOL_FALLING_PLATFORM, EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.CROC_HEAD, EntityBehavior.Kind.GOLD_FROG, EntityBehavior.Kind.LOG_SNAKE, EntityBehavior.Kind.BEAVER, EntityBehavior.Kind.HIVE, EntityBehavior.Kind.BREAKING_BRANCH, EntityBehavior.Kind.SQUIRREL, EntityBehavior.Kind.CAVE_LIGHT] or result.kind in EntityBehavior.DESERT_KINDS or (result.kind in EntityBehavior.JUNGLE_KINDS and result.kind != EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM) or (result.kind in EntityBehavior.SWAMP_KINDS and result.kind != EntityBehavior.Kind.SWP_STAT_WEIR)
	result.tongueable = name == "MOVING_TONGUEABLE" or result.kind in [EntityBehavior.Kind.BONUS_FLY, EntityBehavior.Kind.PICKUP, EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.FAT_FIRE_FLY]
	result.one_shot = result.kind in [EntityBehavior.Kind.BABY_FROG, EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM]
	if result.kind in [EntityBehavior.Kind.TURTLE, EntityBehavior.Kind.JUN_HIPPO]:
		result.payload_offset = 12
		result.payload_register_count = 3
	elif result.kind == EntityBehavior.Kind.STATIC_NOISE:
		result.payload_offset = 32
		result.payload_register_count = 2
	return result
