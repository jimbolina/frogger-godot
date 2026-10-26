class_name ExeTables
extends RefCounted
## Every game table in the executable, each decoded the first time it is asked for.
##
## Nothing here is compiled into this project: every value comes from the
## player's own executable (retail, or saved by FrogLord with edits), read
## the way FrogLord reads it. Each getter returns a table object whose
## [code]error[/code] says whether it read cleanly; [method errors] collects
## them for a report.

## The executable the tables come from.
var exe: ExeImage
## The archive index (names map and demo files).
var mwi: MwiIndex
## FrogLord's name lists, which also give some tables their length.
var names: GameNameLists

var _map_book: MapBook
var _theme_book: ThemeBook
var _bmp_pointers: BmpPointers
var _remaps: TextureRemapList
var _scripts: ScriptTable
var _music: MusicTable
var _level_select: LevelSelectTable
var _demo_table: DemoTable
var _pickups: Array[PickupData] = []
var _pickup_problems := PackedStringArray()
var _pickups_read: bool = false


## Tables of [param image], with its archive index [param index] and name lists [param lists].
func _init(image: ExeImage, index: MwiIndex, lists: GameNameLists) -> void:
	exe = image
	mwi = index
	names = lists


## The level list.
func map_book() -> MapBook:
	if _map_book == null:
		_map_book = MapBook.read(exe)
	return _map_book


## The theme list, with every theme's forms.
func theme_book() -> ThemeBook:
	if _theme_book == null:
		_theme_book = ThemeBook.read(exe, names)
	return _theme_book


## The texture pointer list (texture id to texture record).
func bmp_pointers() -> BmpPointers:
	if _bmp_pointers == null:
		_bmp_pointers = BmpPointers.read(exe)
	return _bmp_pointers


## Every texture remap.
func remaps() -> TextureRemapList:
	if _remaps == null:
		_remaps = TextureRemapList.read(exe, mwi, map_book())
	return _remaps


## The entity scripts.
func scripts() -> ScriptTable:
	if _scripts == null:
		_scripts = ScriptTable.read(exe, names.scripts)
	return _scripts


## The per-level music list.
func music() -> MusicTable:
	if _music == null:
		_music = MusicTable.read(exe)
	return _music


## The level-select stacks.
func level_select() -> LevelSelectTable:
	if _level_select == null:
		_level_select = LevelSelectTable.read(exe)
	return _level_select


## The attract-mode demo list.
func demo_table() -> DemoTable:
	if _demo_table == null:
		_demo_table = DemoTable.read(exe, mwi)
	return _demo_table


## The pickup (bug) appearance table, one entry per bug kind.
func pickups() -> Array[PickupData]:
	if not _pickups_read:
		_pickups = PickupData.read_table(exe, _pickup_problems)
		_pickups_read = true
	return _pickups


## Reads every table and returns one line per problem found; empty when all read cleanly.
func errors() -> PackedStringArray:
	var out := PackedStringArray()
	for pair: Array in [["map book", map_book().error], ["theme book", theme_book().error],
			["texture pointers", bmp_pointers().error], ["texture remaps", remaps().error],
			["scripts", scripts().error], ["music", music().error], ["level select", level_select().error],
			["demo table", demo_table().error]]:
		var message: String = pair[1]
		if not message.is_empty():
			out.append("%s: %s" % [pair[0], message])
	pickups()
	for problem: String in _pickup_problems:
		out.append("pickups: %s" % problem)
	return out
