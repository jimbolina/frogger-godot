class_name FroggerIds
extends RefCounted
## The fixed numbering the game uses for levels, themes, worlds and other lists.
##
## Tables in the executable refer to levels, themes and so on by number. The
## numbering is compiled into the game (the original source's [code]LEVEL_*[/code]
## and [code]THEME_*[/code] enums), so it is the same for every build and every
## FrogLord mod; FrogLord hard-codes the same lists
## ([code]FroggerMapLevelID[/code], [code]FroggerMapTheme[/code],
## [code]FroggerLevelSelectWorldID[/code], [code]FroggerFlyScoreType[/code],
## [code]FroggerFormDeathType[/code], [code]FroggerMusicTrack[/code]).

## Level codes in level-number order. The level list ("map book") in the
## executable has one row for each of the first 60 (six per theme, the sixth
## being the multiplayer level); ISLAND and QB are unused extras.
const LEVEL_CODES: PackedStringArray = [
	"CAV1", "CAV2", "CAV3", "CAV4", "CAV5", "CAVM",
	"DES1", "DES2", "DES3", "DES4", "DES5", "DESM",
	"FOR1", "FOR2", "FOR3", "FOR4", "FOR5", "FORM",
	"JUN1", "JUN2", "JUN3", "JUN4", "JUN5", "JUNM",
	"ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "ORGM",
	"ARN1", "ARN2", "ARN3", "ARN4", "ARN5", "ARNM",
	"SWP1", "SWP2", "SWP3", "SWP4", "SWP5", "SWPM",
	"SKY1", "SKY2", "SKY3", "SKY4", "SKY5", "SKYM",
	"SUB1", "SUB2", "SUB3", "SUB4", "SUB5", "SUBM",
	"VOL1", "VOL2", "VOL3", "VOL4", "VOL5", "VOLM",
	"ISLAND", "QB",
]

## Theme names in theme-number order (the theme book has one row each).
## RUINS exists in the numbering but has no data in the PC release.
const THEMES: PackedStringArray = [
	"GENERAL", "CAVE", "DESERT", "FOREST", "JUNGLE", "ORIGINAL", "RUINS", "SWAMP", "SKY", "SUBURBIA", "VOLCANO",
]

## Theme number of GENERAL: shared objects such as checkpoints and bugs.
const THEME_GENERAL: int = 0

## World names used by the level-select stack, in number order.
const WORLDS: PackedStringArray = [
	"SUBURBIA", "ORIGINAL", "SEWER", "SKY", "FOREST", "VOLCANO", "DESERT", "CAVES", "JUNGLE_RIVER", "RUINED_CITY",
]

## How the frog dies when a form kills it, in number order.
const DEATH_TYPES: PackedStringArray = [
	"SQUISHED", "DIE_ON_BACK", "DROWN", "BITTEN", "FLOP", "POP", "CRASH", "MOWED",
]

## Bug (pickup) kinds, in number order; the pickup table has one row each.
const FLY_SCORE_TYPES: PackedStringArray = [
	"SCORE_10", "SCORE_25", "SCORE_50", "SCORE_100", "SCORE_200", "SCORE_500", "SCORE_1000", "SCORE_5000",
	"LIGHT_BOOST", "SUPER_LIGHT", "TIME_MIN", "TIME_MED", "TIME_MAX", "REDUCE_SCORE_100", "FAST_TIMER_SPEED",
	"ADD_EXTRA_LIFE", "FROG_SUPER_TONGUE", "FROG_QUICK_JUMP", "FROG_AUTO_HOP",
]

## FrogLord's names for the CD audio tracks of the PC release, by track number.
const MUSIC_TRACK_NAMES: Dictionary[int, String] = {
	2: "CAVE1", 3: "CAVE2", 4: "DESERT1", 5: "DESERT2", 6: "FOREST1", 7: "FOREST2", 8: "VOLCANO1",
	9: "VOLCANO2", 10: "JUNGLE1", 11: "JUNGLE2", 12: "JUNGLE3", 13: "LEVEL_SELECT", 14: "ORIGINAL1",
	15: "ORIGINAL2", 16: "SWAMP1", 17: "SWAMP2", 18: "SKY1", 19: "SKY2", 20: "SUBURBIA1", 21: "SUBURBIA2",
}


## The code of level [param level] (e.g. "SUB1"), or "" when out of range.
static func level_code(level: int) -> String:
	return LEVEL_CODES[level] if level >= 0 and level < LEVEL_CODES.size() else ""


## The level number of [param code] (e.g. "SUB1" gives 48), or -1.
static func level_from_code(code: String) -> int:
	return LEVEL_CODES.find(code.to_upper())


## The name of theme [param theme] (e.g. "SWAMP"), or "" when out of range.
static func theme_name(theme: int) -> String:
	return THEMES[theme] if theme >= 0 and theme < THEMES.size() else ""


## The theme a level belongs to: six levels per theme, starting with CAVE.
## Returns -1 for levels outside the 60 themed ones.
static func theme_of_level(level: int) -> int:
	if level < 0 or level >= 60:
		return -1
	return 1 + level / 6


## The name of death type [param death], or "".
static func death_type_name(death: int) -> String:
	return DEATH_TYPES[death] if death >= 0 and death < DEATH_TYPES.size() else ""


## The name of world [param world], or "".
static func world_name(world: int) -> String:
	return WORLDS[world] if world >= 0 and world < WORLDS.size() else ""


## FrogLord's name for CD track [param track], or "" for an unknown track.
static func music_track_name(track: int) -> String:
	var track_name: String = MUSIC_TRACK_NAMES.get(track, "")
	return track_name
