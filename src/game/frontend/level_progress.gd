class_name LevelProgress
extends RefCounted
## Level-select flags, row levels and gold frogs with the frozen unlock rules (SELECT.C, tempopt.c).
##
## Arcade values are parallel to the stack's arcade rows. [member arcade_levels] starts as the
## shipped level of each row and changes only through the jungle rewrite. Flag writes assign,
## as SelectSetLevelFlags does (SELECT.C:704-735); a level missing from its stack is ignored.

const COMPLETED: int = 1 << 0
const SELECTABLE: int = 1 << 1
const ZONE_ACCESSIBLE: int = 1 << 2
const LEVEL_JUNGLE1: int = 18
const LEVEL_JUNGLE2: int = 19
const THEME_JUNGLE: int = 4
const ALL_GOLD_FROGS: int = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10)
const INITIAL_SELECTABLE: PackedInt32Array = [24, 48, 12, 54]
const INITIAL_ZONE_ACCESSIBLE: PackedInt32Array = [25, 26, 27, 28, 49, 50, 51, 52, 13, 55, 56]
const INITIAL_RACE_SELECTABLE: PackedInt32Array = [29, 53, 17, 59, 23]


## What LevelCompleteStartup's arcade arm decided for a completed level (tempopt.c:5850-5946).
class Completion:
	extends RefCounted
	## False when the level is not on the arcade stack; nothing beyond the flag write happened.
	var found: bool = false
	## The next level of the same world, or -1 when the zone is finished.
	var next_level: int = -1
	## True when no further level of the world follows.
	var zone_complete: bool = false
	## True when the level-complete page shows the golden frog.
	var show_gold_frog: bool = false
	## True when this completion rewrote the jungle row (tempopt.c:5878-5883).
	var jungle_rewritten: bool = false


var arcade_levels: PackedInt32Array = PackedInt32Array()
var arcade_worlds: PackedInt32Array = PackedInt32Array()
var arcade_themes: PackedInt32Array = PackedInt32Array()
var arcade_flags: PackedInt32Array = PackedInt32Array()
var race_levels: PackedInt32Array = PackedInt32Array()
var race_flags: PackedInt32Array = PackedInt32Array()
## Gold_frogs: one bit per theme, kept across games and saved.
var gold_frogs: int = 0
## Gold_frogs_current: collected in the current level and not yet shown.
var gold_frogs_current: int = 0
## Gold_frogs_zone: collected in the current zone and not yet shown.
var gold_frogs_zone: int = 0


## Fresh progress for [param stack]: shipped row levels, no gold frogs and SelectLevelInit flags.
static func create(stack: LevelStack) -> LevelProgress:
	var progress := LevelProgress.new()
	for index: int in stack.arcade_count():
		var row: LevelStack.Row = stack.arcade_row(index)
		progress.arcade_levels.append(row.level)
		progress.arcade_worlds.append(row.world)
		progress.arcade_themes.append(row.theme)
		progress.arcade_flags.append(0)
	for index: int in stack.race_count():
		progress.race_levels.append(stack.race_row(index).level)
		progress.race_flags.append(0)
	progress.initialise()
	return progress


## SelectLevelInit (SELECT.C:599-679): clears every flag, then opens ORG1, SUB1, FOR1 and VOL1,
## makes the other levels of those worlds zone-accessible and opens the five race courses.
## Row levels are left as they are, as the source does.
func initialise() -> void:
	arcade_flags.fill(0)
	race_flags.fill(0)
	for level: int in INITIAL_SELECTABLE:
		set_flags(level, SELECTABLE | ZONE_ACCESSIBLE)
	for level: int in INITIAL_ZONE_ACCESSIBLE:
		set_flags(level, ZONE_ACCESSIBLE)
	for level: int in INITIAL_RACE_SELECTABLE:
		set_flags(level, SELECTABLE | ZONE_ACCESSIBLE)


## GameInitialise's gold-frog part (gamesys.C:378-380): forgets the current game's frogs.
func start_game() -> void:
	gold_frogs_current = 0
	gold_frogs_zone = 0


## True for the multiplayer levels, which SelectSetLevelFlags looks up on the race stack.
static func is_race_level(level: int) -> bool:
	return level >= 0 and level < 60 and level % 6 == 5


## SelectSetLevelFlags: assigns [param flags] to the first row now holding [param level].
## Returns false when that stack has no such row.
func set_flags(level: int, flags: int) -> bool:
	var levels: PackedInt32Array = race_levels if is_race_level(level) else arcade_levels
	var index: int = levels.find(level)
	if index < 0:
		return false
	if is_race_level(level):
		race_flags[index] = flags
	else:
		arcade_flags[index] = flags
	return true


## SelectGetLevelFlags (SELECT.C:761-806): the flags of [param level]. JUN1 and JUN2 fall back
## to the first jungle row; any other missing level reads 0.
func flags_of(level: int) -> int:
	if is_race_level(level):
		var race_index: int = race_levels.find(level)
		return race_flags[race_index] if race_index >= 0 else 0
	var index: int = arcade_levels.find(level)
	if index >= 0:
		return arcade_flags[index]
	if level >= LEVEL_JUNGLE1 and level <= LEVEL_JUNGLE2:
		for row: int in arcade_levels.size():
			if arcade_levels[row] >= LEVEL_JUNGLE1 and arcade_levels[row] <= LEVEL_JUNGLE2:
				return arcade_flags[row]
	return 0


## True when [param level] can be chosen on the stack.
func is_selectable(level: int) -> bool:
	return flags_of(level) & SELECTABLE != 0


## True when [param level] has been completed.
func is_completed(level: int) -> bool:
	return flags_of(level) & COMPLETED != 0


## True when [param level] belongs to an opened zone.
func is_zone_accessible(level: int) -> bool:
	return flags_of(level) & ZONE_ACCESSIBLE != 0


## LevelCompleteStartup's arcade arm (tempopt.c:5850-5946): marks [param level] completed,
## finds the next row of the same world, rewrites JUN1 to JUN2 when the stack ends, and moves
## the gold-frog display bits. The next level is opened later by [method open_level] or
## [method open_level_if_closed], as LevelCompleteUpdate does.
func complete_level(level: int) -> Completion:
	var result := Completion.new()
	set_flags(level, COMPLETED | SELECTABLE | ZONE_ACCESSIBLE)
	var index: int = arcade_levels.find(level)
	if index < 0:
		return result
	result.found = true
	var theme_bit: int = 1 << arcade_themes[index]
	if index + 1 >= arcade_levels.size():
		result.zone_complete = true
		if arcade_levels[index] == LEVEL_JUNGLE1:
			arcade_levels[index] = LEVEL_JUNGLE2
			result.jungle_rewritten = true
	elif arcade_worlds[index] == arcade_worlds[index + 1]:
		result.next_level = arcade_levels[index + 1]
	else:
		result.zone_complete = true
	if not result.zone_complete:
		if gold_frogs_current & theme_bit != 0:
			result.show_gold_frog = true
			gold_frogs_current &= ~theme_bit
			gold_frogs_zone |= theme_bit
	else:
		if gold_frogs_current & theme_bit != 0:
			gold_frogs_current &= ~theme_bit
			gold_frogs_zone |= theme_bit
		if gold_frogs_zone & theme_bit != 0:
			result.show_gold_frog = true
			gold_frogs_zone &= ~theme_bit
	return result


## LevelCompleteUpdate's count-down arm (tempopt.c:6058-6063): opens [param level]
## unconditionally, which also clears an earlier COMPLETED flag.
func open_level(level: int) -> void:
	set_flags(level, SELECTABLE | ZONE_ACCESSIBLE)


## LevelCompleteUpdate's triangle arm (tempopt.c:6034-6040): opens [param level] only when it
## is not selectable yet.
func open_level_if_closed(level: int) -> void:
	if not is_selectable(level):
		set_flags(level, SELECTABLE | ZONE_ACCESSIBLE)


## True when the gold frog of [param theme] has ever been collected.
func has_gold_frog(theme: int) -> bool:
	return gold_frogs & (1 << theme) != 0


## True when every theme's gold frog is collected (GEN_ALL_GOLD_FROGS).
func has_all_gold_frogs() -> bool:
	return gold_frogs == ALL_GOLD_FROGS


## FrogCollectGoldFrog (FROG.C:2909-2919): records the gold frog of [param theme] and opens the
## first closed world. Returns the level opened, or -1 when the frog was already collected or
## every world was open.
func collect_gold_frog(theme: int) -> int:
	var bit: int = 1 << theme
	if gold_frogs & bit != 0:
		return -1
	gold_frogs |= bit
	gold_frogs_current |= bit
	return open_first_closed_world()


## SelectLevelCollectGoldFrog (SELECT.C:2858-2914): walks consecutive rows of one theme; for the
## first theme with no selectable row, makes all its rows zone-accessible and opens its first
## row. Returns that row's level, or -1 when every theme had a selectable row.
func open_first_closed_world() -> int:
	var index: int = 0
	while index < arcade_levels.size():
		var theme: int = arcade_themes[index]
		var first_level: int = arcade_levels[index]
		var open: bool = false
		while index < arcade_levels.size() and arcade_themes[index] == theme:
			if arcade_flags[index] & SELECTABLE != 0:
				open = true
			index += 1
		if not open:
			for row: int in arcade_levels.size():
				if arcade_themes[row] == theme:
					set_flags(arcade_levels[row], ZONE_ACCESSIBLE)
			set_flags(first_level, SELECTABLE | ZONE_ACCESSIBLE)
			return first_level
	return -1


## The jungle statue (gamesys.C:3484-3490): records the jungle gold frog without opening a world.
func reach_jungle_statue() -> void:
	gold_frogs |= 1 << THEME_JUNGLE


## The end-of-game rewrite (gamesys.C:3969-3978, tempopt.c:5878-5883): the first JUN1 row now
## holds JUN2 and keeps its flags. Returns false when no row holds JUN1.
func rewrite_jungle_row() -> bool:
	var index: int = arcade_levels.find(LEVEL_JUNGLE1)
	if index < 0:
		return false
	arcade_levels[index] = LEVEL_JUNGLE2
	return true


## DecodeSaveData's jungle rule (LoadSave.c:3450-3476): with the jungle gold frog the first JUN1
## row holds JUN2, otherwise the first JUN2 row holds JUN1.
func apply_loaded_jungle_rule() -> void:
	var from_level: int = LEVEL_JUNGLE2
	var to_level: int = LEVEL_JUNGLE1
	if has_gold_frog(THEME_JUNGLE):
		from_level = LEVEL_JUNGLE1
		to_level = LEVEL_JUNGLE2
	var index: int = arcade_levels.find(from_level)
	if index >= 0:
		arcade_levels[index] = to_level


## EncodeSaveData's JUN2 write (LoadSave.c:3549-3559): when a row holds JUN2 it becomes
## completed, selectable and zone-accessible before the flags are saved.
func apply_save_encoding() -> void:
	if arcade_levels.has(LEVEL_JUNGLE2):
		set_flags(LEVEL_JUNGLE2, COMPLETED | SELECTABLE | ZONE_ACCESSIBLE)


## A detached copy of every value.
func copy() -> LevelProgress:
	var result := LevelProgress.new()
	result.arcade_levels = arcade_levels.duplicate()
	result.arcade_worlds = arcade_worlds.duplicate()
	result.arcade_themes = arcade_themes.duplicate()
	result.arcade_flags = arcade_flags.duplicate()
	result.race_levels = race_levels.duplicate()
	result.race_flags = race_flags.duplicate()
	result.gold_frogs = gold_frogs
	result.gold_frogs_current = gold_frogs_current
	result.gold_frogs_zone = gold_frogs_zone
	return result
