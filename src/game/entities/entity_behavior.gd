class_name EntityBehavior
extends RefCounted
## Resolved entity implementation and capabilities, independent of source names.

enum Kind { UNKNOWN, STATIC, PATH_FOLLOWER, TURTLE, BABY_FROG, BONUS_FLY, CHECKPOINT, STATIC_NOISE, BOUNDS_TOP_LEFT, BOUNDS_BOTTOM_RIGHT, CROC_HEAD, GOLD_FROG, LOG_SNAKE, BEAVER, PICKUP, DOG, HIVE, BREAKING_BRANCH, SQUIRREL, HEDGEHOG, MOVING_PLATFORM, VOL_COLOUR_SWITCH, VOL_FALLING_PLATFORM, CAVE_LIGHT, FIREFLY, FAT_FIRE_FLY, DES_FALLING_ROCK, DES_ROLLING_ROCK, DES_TUMBLE_WEED, DES_SNAKE, DES_VULTURE, DES_CROC_HEAD, DES_CRACK, JUN_PLANT, JUN_ROPE_BRIDGE, JUN_HIPPO, JUN_SCORPION, JUN_BOUNCY_MUSHROOM, JUN_OUTRO_DOOR, JUN_OUTRO, JUN_PLINTH, JUN_GOLD_FROG, JUN_STONE_FROG, SWP_SQUIRT, SWP_CRUSHER, SWP_PRESS, SWP_RAT, SWP_SLUG, NUCLEAR_BARREL, SWP_STAT_WEIR, TRIGGER }
enum Layout { NONE, MATRIX, PATH }
enum Execution { TRANSFORM, UPDATE, CONTACT }

## Desert custom behaviors, each with a custom update and FORM contact.
const DESERT_KINDS: Array[Kind] = [Kind.DES_FALLING_ROCK, Kind.DES_ROLLING_ROCK, Kind.DES_TUMBLE_WEED, Kind.DES_SNAKE, Kind.DES_VULTURE, Kind.DES_CROC_HEAD, Kind.DES_CRACK]
## Jungle behaviors, each with FORM contact; the matrix kinds also run a custom update, empty where the source has none.
const JUNGLE_KINDS: Array[Kind] = [Kind.JUN_PLANT, Kind.JUN_ROPE_BRIDGE, Kind.JUN_HIPPO, Kind.JUN_SCORPION, Kind.JUN_BOUNCY_MUSHROOM, Kind.JUN_OUTRO_DOOR, Kind.JUN_OUTRO, Kind.JUN_PLINTH, Kind.JUN_GOLD_FROG, Kind.JUN_STONE_FROG]
## Jungle path followers that run only the generic moving update and their scripts.
const JUNGLE_PATH_KINDS: Array[Kind] = [Kind.JUN_HIPPO, Kind.JUN_SCORPION]
## Swamp behaviors, each with FORM contact; the matrix kinds also run a custom update, empty for the weir.
const SWAMP_KINDS: Array[Kind] = [Kind.SWP_SQUIRT, Kind.SWP_CRUSHER, Kind.SWP_PRESS, Kind.SWP_RAT, Kind.SWP_SLUG, Kind.NUCLEAR_BARREL, Kind.SWP_STAT_WEIR]
## Swamp path followers that run only the generic moving update and their scripts.
const SWAMP_PATH_KINDS: Array[Kind] = [Kind.SWP_SLUG, Kind.NUCLEAR_BARREL]

var kind: Kind = Kind.UNKNOWN
var layout: Layout = Layout.NONE
var execution: Execution = Execution.TRANSFORM
var tongueable: bool = false
var immortal: bool = false
var group_moving: bool = false
var one_shot: bool = false
var payload_offset: int = 0
var payload_register_count: int = 0

## Whether this definition executes a custom update in the current run.
func has_custom_update() -> bool:
	return execution >= Execution.UPDATE and (kind in DESERT_KINDS or (kind in JUNGLE_KINDS and kind not in JUNGLE_PATH_KINDS) or (kind in SWAMP_KINDS and kind not in SWAMP_PATH_KINDS) or kind in [Kind.BABY_FROG, Kind.BONUS_FLY, Kind.CHECKPOINT, Kind.STATIC_NOISE, Kind.BOUNDS_TOP_LEFT, Kind.BOUNDS_BOTTOM_RIGHT, Kind.CROC_HEAD, Kind.GOLD_FROG, Kind.LOG_SNAKE, Kind.BEAVER, Kind.PICKUP, Kind.DOG, Kind.HIVE, Kind.BREAKING_BRANCH, Kind.SQUIRREL, Kind.HEDGEHOG, Kind.MOVING_PLATFORM, Kind.VOL_COLOUR_SWITCH, Kind.VOL_FALLING_PLATFORM, Kind.CAVE_LIGHT, Kind.FAT_FIRE_FLY, Kind.TRIGGER])

## Whether the implemented contact rule may run for this entity.
func has_form_contact() -> bool:
	return kind in [Kind.STATIC, Kind.PATH_FOLLOWER, Kind.TURTLE, Kind.CHECKPOINT, Kind.GOLD_FROG, Kind.CROC_HEAD, Kind.LOG_SNAKE, Kind.BEAVER, Kind.BONUS_FLY, Kind.PICKUP, Kind.STATIC_NOISE, Kind.BOUNDS_TOP_LEFT, Kind.BOUNDS_BOTTOM_RIGHT, Kind.DOG, Kind.HIVE, Kind.BREAKING_BRANCH, Kind.SQUIRREL, Kind.HEDGEHOG, Kind.MOVING_PLATFORM, Kind.VOL_COLOUR_SWITCH, Kind.VOL_FALLING_PLATFORM, Kind.TRIGGER] or kind in DESERT_KINDS or kind in JUNGLE_KINDS or kind in SWAMP_KINDS or (kind == Kind.BABY_FROG and execution == Execution.CONTACT)

## Detaches setup capabilities before the run retains them.
func copy() -> EntityBehavior:
	var result := EntityBehavior.new()
	result.tongueable = tongueable
	result.kind = kind
	result.layout = layout
	result.execution = execution
	result.immortal = immortal
	result.group_moving = group_moving
	result.one_shot = one_shot
	result.payload_offset = payload_offset
	result.payload_register_count = payload_register_count
	return result
