class_name ExeTables
extends RefCounted
## Every game table in the player's executable, decoded when the tables are made.
##
## The decoded tables are [member decoded], a [GameTables] record read by
## [ExeTablesReader]; the accessors here return its tables, and [method errors]
## collects their problems for a report. The executable, archive index and
## name lists they were read from stay available beside them.

## The executable the tables come from.
var exe: ExeImage
## The archive index (names map and demo files).
var mwi: MwiIndex
## FrogLord's name lists, which also give some tables their length.
var names: GameNameLists
## The decoded tables.
var decoded: GameTables = GameTables.new()

var _bmp_pointers: BmpPointers:
	get:
		return decoded.bmp_pointer_table
	set(value):
		decoded.bmp_pointer_table = value
var _pickups: Array[PickupData]:
	get:
		return decoded.pickup_table
	set(value):
		decoded.pickup_table = value
var _pickups_read: bool = false


## Tables of [param image], with its archive index [param index] and name
## lists [param lists]; with no [param image] every table is left unread.
func _init(image: ExeImage = null, index: MwiIndex = null, lists: GameNameLists = null) -> void:
	exe = image
	mwi = index
	names = lists
	if image != null:
		decoded = ExeTablesReader.read(image, index, lists)
		_pickups_read = true


## The level list.
func map_book() -> MapBook:
	return decoded.map_book()


## The theme list, with every theme's forms.
func theme_book() -> ThemeBook:
	return decoded.theme_book()


## The texture pointer list (texture id to texture record).
func bmp_pointers() -> BmpPointers:
	return decoded.bmp_pointers()


## Every texture remap.
func remaps() -> TextureRemapList:
	return decoded.remaps()


## The entity scripts.
func scripts() -> ScriptTable:
	return decoded.scripts()


## The verified gameplay reward values.
func scores() -> ScoreTable:
	return decoded.scores()


## The default main and per-level high-score tables.
func high_scores() -> HighScoreTable:
	return decoded.high_scores()


## The per-level music list.
func music() -> MusicTable:
	return decoded.music()


## The level-select stacks.
func level_select() -> LevelSelectTable:
	return decoded.level_select()


## The attract-mode demo list.
func demo_table() -> DemoTable:
	return decoded.demo_table()


## The pickup (bug) appearance table, one entry per bug kind.
func pickups() -> Array[PickupData]:
	return decoded.pickups()


## The sound banks, groups, samples and music pitches.
func sound_tables() -> SoundTables:
	return decoded.sound_tables()


## The particle generator records and tables.
func particle_generators() -> ExeParticleGenerators:
	return decoded.particle_generators()


## The water splash animation lists.
func splash_lists() -> ExeSplashAnimLists:
	return decoded.splash_lists()


## One line per problem found in the tables; empty when all read cleanly.
func errors() -> PackedStringArray:
	return decoded.errors()
