class_name GameTables
extends Resource
## Every game table read from the player's executable.
##
## Nothing here is compiled into this project: every value comes from the
## player's own executable (retail, or saved by FrogLord with edits), read
## the way FrogLord reads it ([ExeTablesReader]). Each table records whether
## it read cleanly in its [code]error[/code]; [method errors] collects them
## for a report. A table that was not read is null.

## The level list.
@export var map_book_table: MapBook
## The theme list, with every theme's forms.
@export var theme_book_table: ThemeBook
## The texture pointer list (texture id to texture record).
@export var bmp_pointer_table: BmpPointers
## Every texture remap.
@export var remap_table: TextureRemapList
## The entity scripts.
@export var script_table: ScriptTable
## The verified gameplay reward values.
@export var score_table: ScoreTable
## The default main and per-level high-score tables.
@export var high_score_table: HighScoreTable
## The per-level music list.
@export var music_table: MusicTable
## The level-select stacks.
@export var level_select_table: LevelSelectTable
## The attract-mode demo list.
@export var demo_list: DemoTable
## The pickup (bug) appearance table, one entry per bug kind.
@export var pickup_table: Array[PickupData] = []
## Why the pickup table could not be read in full; empty when it read cleanly.
@export var pickup_problems: PackedStringArray = PackedStringArray()
## The sound banks, groups, samples and music pitches.
@export var sound_table: SoundTables
## The particle generator records and tables.
@export var particle_generator_table: ExeParticleGenerators
## The water splash animation lists.
@export var splash_list_table: ExeSplashAnimLists


## The level list.
func map_book() -> MapBook:
	return map_book_table


## The theme list, with every theme's forms.
func theme_book() -> ThemeBook:
	return theme_book_table


## The texture pointer list (texture id to texture record).
func bmp_pointers() -> BmpPointers:
	return bmp_pointer_table


## Every texture remap.
func remaps() -> TextureRemapList:
	return remap_table


## The entity scripts.
func scripts() -> ScriptTable:
	return script_table


## The verified gameplay reward values.
func scores() -> ScoreTable:
	return score_table


## The default main and per-level high-score tables.
func high_scores() -> HighScoreTable:
	return high_score_table


## The per-level music list.
func music() -> MusicTable:
	return music_table


## The level-select stacks.
func level_select() -> LevelSelectTable:
	return level_select_table


## The attract-mode demo list.
func demo_table() -> DemoTable:
	return demo_list


## The pickup (bug) appearance table, one entry per bug kind.
func pickups() -> Array[PickupData]:
	return pickup_table


## The sound banks, groups, samples and music pitches.
func sound_tables() -> SoundTables:
	return sound_table


## The particle generator records and tables.
func particle_generators() -> ExeParticleGenerators:
	return particle_generator_table


## The water splash animation lists.
func splash_lists() -> ExeSplashAnimLists:
	return splash_list_table


## One line per problem in the level, theme, texture, script, music, level
## select, demo and pickup tables; empty when all read cleanly.
func errors() -> PackedStringArray:
	var out := PackedStringArray()
	var checked: Array[Array] = [
		["map book", map_book_table.error if map_book_table != null else ""],
		["theme book", theme_book_table.error if theme_book_table != null else ""],
		["texture pointers", bmp_pointer_table.error if bmp_pointer_table != null else ""],
		["texture remaps", remap_table.error if remap_table != null else ""],
		["scripts", script_table.error if script_table != null else ""],
		["music", music_table.error if music_table != null else ""],
		["level select", level_select_table.error if level_select_table != null else ""],
		["demo table", demo_list.error if demo_list != null else ""],
	]
	for pair: Array in checked:
		var message: String = pair[1]
		if not message.is_empty():
			out.append("%s: %s" % [pair[0], message])
	for problem: String in pickup_problems:
		out.append("pickups: %s" % problem)
	return out
