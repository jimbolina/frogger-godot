class_name ExeTablesReader
extends RefCounted
## Reads every game table ([GameTables]) from the player's executable.


## Decodes every table of [param image], using the archive index
## [param index] (remap names and demo files) and FrogLord's name lists
## [param lists] (form, entity and script names, and the lengths of the theme
## libraries and script table). A table whose inputs are missing records why
## in its error. An empty record is returned for a null [param image].
static func read(image: ExeImage, index: MwiIndex, lists: GameNameLists) -> GameTables:
	var tables := GameTables.new()
	if image == null:
		return tables
	tables.map_book_table = MapBookReader.read(image)
	if lists != null:
		tables.theme_book_table = ThemeBookReader.read(image, lists)
		tables.script_table = ScriptTableReader.read(image, lists.scripts)
	else:
		tables.theme_book_table = ThemeBook.new()
		tables.theme_book_table.error = "FrogLord's name lists are needed"
		tables.script_table = ScriptTable.new()
		tables.script_table.error = "FrogLord's name lists are needed"
	tables.bmp_pointer_table = BmpPointersReader.read(image)
	if index != null:
		tables.remap_table = TextureRemapListReader.read(image, index, tables.map_book_table)
		tables.demo_list = DemoTableReader.read(image, index)
	else:
		tables.remap_table = TextureRemapList.new()
		tables.remap_table.error = "the archive index is needed"
		tables.demo_list = DemoTable.new()
		tables.demo_list.error = "the archive index is needed"
	tables.score_table = ScoreTableReader.read(image)
	tables.high_score_table = HighScoreTableReader.read(image)
	tables.music_table = MusicTableReader.read(image)
	tables.level_select_table = LevelSelectTableReader.read(image)
	tables.pickup_table = PickupDataReader.read_table(image, tables.pickup_problems)
	tables.sound_table = SoundTablesReader.read(image)
	tables.particle_generator_table = ExeParticleGeneratorsReader.read(image, tables.bmp_pointer_table)
	tables.splash_list_table = ExeSplashAnimListsReader.read(image, tables.bmp_pointer_table)
	return tables
